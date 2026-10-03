#!/usr/bin/env python3
"""把 posemaniacs 原图裁切归一化成适合当生图参考的姿势图。

为什么要处理（实测数据）：
  - 205 张原图里203 张的模型只占画幅 14.5%（中位数），其余是白边。
    直接当ControlNet / 参考图输入，模型看到的是「白底上的一个小人」，
    姿势细节（手的位置、腿的角度）几乎丢失，等于白抓。
  - 原图 1076×1076 RGBA，含 alpha，但主体偏小且不在中心。

处理步骤（每张图）：
  1. 取前景 mask：优先 alpha 通道；alpha 全不透明时退回「非白像素」
  2. 按mask 求包围盒，裁掉白边
  3. 加 6% 留白边（避免贴边裁掉肢体）
  4. 补成正方形（透明底，居中），统一缩放到 768×768
  5. 存WebP q=82，体积可控

输出：/tmp/posedata/norm/{poseId}_{modelId}.webp+ .json 元数据
"""
import concurrent.futures as cf
import glob
import json
import os

import numpy as np
from PIL import Image

SRC = "/tmp/posedata/img"
DST = "/tmp/posedata/norm"
SIZE = 768
PAD_RATIO = 0.06
BG = (255, 255, 255, 0)  # 透明底：白底在内衣试衣场景里容易和浅色衣物混


def foreground_mask(im):
    """优先用 alpha；没有透明信息时用「非白像素」兜底。"""
    rgba = im.convert("RGBA")
    a = np.array(rgba)
    alpha = a[..., 3]
    if alpha.min() < 250:  # 真的有透明像素
        return rgba, alpha > 12
    rgb = a[..., :3].astype(np.int16)
    # 与白色距离足够远才算前景，容忍轻微压缩噪点
    mask = (255 - rgb.min(axis=2)) > 12
    return rgba, mask


def normalize(src, dst):
    im = Image.open(src)
    rgba, mask = foreground_mask(im)
    ys, xs = np.where(mask)
    if len(ys) == 0:
        raise ValueError("空前景")

    h, w = im.size[1], im.size[0]
    y0, y1 = int(ys.min()), int(ys.max()) + 1
    x0, x1 = int(xs.min()), int(xs.max()) + 1

    # 加留白：肢体贴边时不会切掉
    py = int((y1 - y0) * PAD_RATIO)
    px = int((x1 - x0) * PAD_RATIO)
    y0 = max(0, y0 - py); y1 = min(h, y1 + py)
    x0 = max(0, x0 - px); x1 = min(w, x1 + px)

    crop = rgba.crop((x0, y0, x1, y1))
    cw, ch = crop.size

    # 补正方形：crop 里已经加过留白了，这里直接取 max 边长不要再乘系数，
    # 否则等于把主体重新稀释回小占比（实测踩过：乘 1.12 后主体只剩 18%）
    side = max(cw, ch)
    canvas = Image.new("RGBA", (side, side), BG)
    canvas.paste(crop, ((side - cw) // 2, (side - ch) // 2), crop)
    out = canvas.resize((SIZE, SIZE), Image.LANCZOS)

    # 量化后alpha 边缘会有杂色，用一次 alpha 归一化清掉
    arr = np.array(out).astype(np.float32)
    al = arr[..., 3:4] / 255.0
    arr[..., :3] = arr[..., :3] * al + 255.0 * (1 - al)  # 边缘去黑边
    out = Image.fromarray(arr.clip(0, 255).astype(np.uint8), "RGBA")

    out.save(dst, "WEBP", quality=82, method=4)

    # 量的是**裁切后**主体在最终画幅里的占比，这才是决定参考图质量的那个数。
    # （第一版这里返回的是裁切前的原始占比 0.145，看着没提升，其实是量错了对象。）
    _, m2 = foreground_mask(out)
    ys2, xs2 = np.where(m2)
    if len(ys2) == 0:
        raise ValueError("裁切后前景为空")
    bh = ys2.max() - ys2.min() + 1
    bw = xs2.max() - xs2.min() + 1
    return {
        "srcSize": [w, h],
        "crop": [x0, y0, x1 - x0, y1 - y0],
        "subjectRatioBefore": round((y1 - y0) * (x1 - x0) / (w * h), 4),
        "subjectRatio": round(bh * bw / (SIZE * SIZE), 4),
        "outBytes": os.path.getsize(dst),
    }


def main():
    os.makedirs(DST, exist_ok=True)
    files = sorted(glob.glob(os.path.join(SRC, "*")))
    print(f"[归一化] 待处理 {len(files)} 张 → {SIZE}×{SIZE} WebP")

    def job(f):
        base = os.path.splitext(os.path.basename(f))[0]
        dst = os.path.join(DST, base + ".webp")
        try:
            meta = normalize(f, dst)
            return (base, meta, None)
        except Exception as e:
            return (base, None, str(e))

    ok, bad, metas = 0, [], {}
    with cf.ThreadPoolExecutor(8) as ex:
        for base, meta, err in ex.map(job, files):
            if err:
                bad.append((base, err))
            else:
                ok += 1
                metas[base] = meta
    print(f"[归一化] 成功 {ok} 失败 {len(bad)}")
    for b, e in bad[:10]:
        print("   FAIL", b, e)

    if metas:
        sizes = sorted(m["outBytes"] for m in metas.values())
        ratios = sorted(m["subjectRatio"] for m in metas.values())
        print(f"  裁切后主体占画幅: 中位 {ratios[len(ratios)//2]:.3f}（原 0.145）")
        print(f"  体积: 中位 {sizes[len(sizes)//2]/1024:.1f}KB  "
              f"最大 {sizes[-1]/1024:.1f}KB  合计 {sum(sizes)/1048576:.1f}MB")

    with open("/tmp/posedata/norm_meta.json", "w", encoding="utf-8") as f:
        json.dump(metas, f, ensure_ascii=False, indent=1)
    print("→ /tmp/posedata/norm_meta.json")
    return len(bad)


if __name__ == "__main__":
    main()