#!/usr/bin/env python3
"""把 205 张归一化姿势图拼成带索引的拼图，供逐批人工/模型命名。

为什么要这么做：站点只给poseId，没有任何中文名或描述。
而 205 张图一张张看不现实。这里拼成 4×3 的sheet、每张带序号，
一次看 12 个姿势，命名时只需报序号，映射由poseId 保证不会错位。
"""
import json
import math
import os

from PIL import Image, ImageDraw

SRC = "/tmp/posedata/norm"
OUT = "/tmp/posedata/sheets"
COLS, ROWS = 4, 3
CELL = 300
PAD = 6
LABEL_H = 26


def main():
    os.makedirs(OUT, exist_ok=True)
    d = json.load(open("/tmp/posedata/poses2.json", encoding="utf-8"))
    uniq = sorted(d["unique"], key=lambda x: (x["slug"], x["poseId"]))

    per = COLS * ROWS
    sheets = []
    for i in range(0, len(uniq), per):
        sheets.append(uniq[i:i + per])

    index = []
    for si, batch in enumerate(sheets):
        W = COLS * (CELL + PAD) + PAD
        H = ROWS * (CELL + PAD + LABEL_H) + PAD
        canvas = Image.new("RGB", (W, H), (238, 238, 242))
        dr = ImageDraw.Draw(canvas)
        for j, it in enumerate(batch):
            gi = si * per + j
            r, c = divmod(j, COLS)
            x = PAD + c * (CELL + PAD)
            y = PAD + r * (CELL + PAD + LABEL_H)
            # 棋盘底：透明区在白底图上看不出边界，这里用浅灰格
            for cy in range(0, CELL, 20):
                for cx in range(0, CELL, 20):
                    col = (246, 246, 248) if ((cx // 20 + cy // 20) % 2 == 0) else (232, 232, 236)
                    dr.rectangle([x + cx, y + cy, x + min(cx + 20, CELL), y + min(cy + 20, CELL)], fill=col)
            fp = os.path.join(SRC, f"{it['poseId']}_{it['modelId']}.webp")
            if os.path.exists(fp):
                im = Image.open(fp)
                bg = Image.new("RGB", im.size, (255, 255, 255))
                bg.paste(im, mask=im.split()[3])
                bg.thumbnail((CELL - 4, CELL - 4), Image.LANCZOS)
                canvas.paste(bg, (x + (CELL - bg.size[0]) // 2, y + (CELL - bg.size[1]) // 2))
            lab = f"#{gi:03d} {it['poseId']}/{it['modelId']}"
            dr.text((x + 4, y + CELL + 6), lab, fill=(20, 20, 30))
            index.append({
                "idx": gi, "sheet": si,
                "poseId": it["poseId"], "modelId": it["modelId"],
                "slug": it["slug"], "alsoIn": it.get("alsoIn"),
                "file": fp,
            })
        p = os.path.join(OUT, f"sheet_{si:02d}.png")
        canvas.save(p)
        print(f"{p}  ({len(batch)} 个)")

    json.dump(index, open("/tmp/posedata/sheet_index.json", "w", encoding="utf-8"),
              ensure_ascii=False, indent=1)
    print(f"\n共 {len(sheets)} 张 sheet，覆盖 {len(index)} 个姿势")
    print("→ /tmp/posedata/sheet_index.json")


if __name__ == "__main__":
    main()