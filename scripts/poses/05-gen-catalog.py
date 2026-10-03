#!/usr/bin/env python3
"""合并命名表 + 站点元数据 → 生成 App用的 Dart 姿势库。

分组归属用**站点的分类**（sitting/kneeling/lying），
但展示顺序按idx（也就是拼图顺序，同组聚在一起），
编码在组内重新连续编号 S-001 / K-001 / L-001。
跨组姿势（27 个，同时属于两类）在两个组里各出现一次，共用同一个 id。

输出：
  /workspace/dapei-app/app/lib/services/pose_library_data.g.dart
  /workspace/dapei-app/assets/poses/index.json   （给 UI 网格用的清单）
"""
import json
import os
from collections import OrderedDict, defaultdict

from pose_names import P

SRC = "/tmp/posedata/poses2.json"
OUT_DART = "/workspace/dapei-app/app/lib/services/pose_library_data.g.dart"
OUT_JSON = "/workspace/dapei-app/assets/poses/index.json"

GROUP_LABEL = {"sit": "坐姿", "kneel": "跪姿", "lie": "卧姿"}
GROUP_CODE = {"sit": "S", "kneel": "K", "lie": "L"}
# slug → code，与 poses2.json 的 groups 保持一致
SLUG2CODE = {"sitting": "sit", "kneeling": "kneel", "lying": "lie"}


def main():
    d = json.load(open(SRC, encoding="utf-8"))
    index = json.load(open("/tmp/posedata/sheet_index.json", encoding="utf-8"))
    assert len(index) == len(d["unique"]) == 205

    # idx →站点元数据
    meta = {i["idx"]: i for i in index}

    # 跨组归属：主组用 slug，alsoIn 里的是附加组
    memberships = defaultdict(list)  # idx -> [code, ...]
    for it in d["unique"]:
        pass
    for idx, i in meta.items():
        codes = [SLUG2CODE[i["slug"]]]
        for extra in (i.get("alsoIn") or []):
            c = SLUG2CODE.get(extra)
            if c and c not in codes:
                codes.append(c)
        memberships[idx] = codes

    # 组内按 idx 顺序编号
    counters = {"sit": 0, "kneel": 0, "lie": 0}
    rows = []
    for idx in range(205):
        name, desc, prompt = P[idx]
        i = meta[idx]
        pid = f"pm-{i['poseId']}-{i['modelId']}"
        image = f"poses/{i['poseId']}_{i['modelId']}.webp"
        for c in memberships[idx]:
            counters[c] += 1
            rows.append({
                "id": pid,
                "code": f"{GROUP_CODE[c]}-{counters[c]:03d}",
                "name": name,
                "desc": desc,
                "prompt": prompt,
                "group": c,
                "image": image,
                "srcPoseId": i["poseId"],
                "srcModelId": i["modelId"],
            })

    # 校验
    names = [r["name"] for r in rows]
    assert len(set(names)) >= 200, f"名称重复过多：{len(names)}行/{len(set(names))}个唯一名"
    ids = [r["id"] for r in rows]
    per_id_groups = defaultdict(set)
    for r in rows:
        per_id_groups[r["id"]].add(r["group"])
    for pid, gs in per_id_groups.items():
        assert len(gs) == len([r for r in rows if r["id"] == pid]), f"{pid} 组内重复"

    # prompt 必须按**唯一姿势**去重后校验：跨组姿势本来就重复出现，
    # 但两个不同姿势共用一条 prompt 说明我写重了（实测发生过一次：
    # 两条「坐地斜撑」文案完全一样，看图才发现一个推掌一个低侧倾）。
    # 这类错误靠人工几乎发现不了，靠断言拦住。
    by_id = {}
    for r in rows:
        by_id.setdefault(r["id"], r)
    pm = defaultdict(list)
    for r in by_id.values():
        pm[r["prompt"]].append(f"{r['code']}/{r['id']}")
    dup = {k: v for k, v in pm.items() if len(v) > 1}
    assert not dup, "以下姿势共用同一条 prompt，请逐个看图后改写：\n" + "\n".join(
        f"  {v}→ {k}" for k, v in dup.items()
    )
    nm = defaultdict(list)
    for r in by_id.values():
        nm[r["name"]].append(f"{r['code']}/{r['id']}")
    dupn = {k: v for k, v in nm.items() if len(v) > 1}
    assert not dupn, "以下姿势共用同一个中文名：\n" + "\n".join(
        f"  {v} → {k}" for k, v in dupn.items()
    )

    counts = defaultdict(int)
    for r in rows:
        counts[r["group"]] += 1
    print(f"总行数 {len(rows)}（唯一姿势 {len(per_id_groups)}，跨组 {sum(1 for g in per_id_groups.values() if len(g)>1)}）")
    for g in ("sit", "kneel", "lie"):
        print(f"  {GROUP_LABEL[g]}({g}): {counts[g]}")

    # ── Dart ──
    def esc(s):
        return s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$")

    lines = [
        "// GENERATED FILE —— 请勿手改",
        "// 由 scripts/gen_pose_library.py 生成（源数据见 assets/poses/index.json）。",
        "//",
        "// 数据来源：posemaniacs.com 女性姿势库（坐/跪/卧三大类，205 个唯一姿势）。",
        "// 中文名与英文 prompt 是**逐张看图**写的（站点只给 poseId + tagCount，",
        "// 既无中文名也无描述，无法靠标签自动生成）。",
        "//",
        "// 图片存在 Vercel **私密** Blob store 的 poses/ 目录下，",
        "// App 通过 GET /api/pose-image 代理取流（私有 blob 的 URL 匿名访问会 403）。",
        "",
        "/// 姿势库分组（与站点分类一致）",
        "enum PoseGroup { kneel, sit, lie }",
        "",
        "/// 一条姿势预设",
        "class PoseEntry {",
        "  const PoseEntry({",
        "    required this.id,",
        "    required this.code,",
        "    required this.name,",
        "    required this.desc,",
        "    required this.prompt,",
        "    required this.group,",
        "    required this.imagePath,",
        "  });",
        "",
        "  /// 稳定标识，同一姿势跨组共用（如 pm-0001039-00002）",
        "  final String id;",
        "  /// 展示编码，组内连续编号，如 S-001 / K-012 / L-033",
        "  final String code;",
        "  /// 中文短名（摄影棚工作语言）",
        "  final String name;",
        "  /// 一句话说明这条姿势看什么",
        "  final String desc;",
        "  /// 并入生成prompt 的英文姿势描述",
        "  final String prompt;",
        "  final PoseGroup group;",
        "  /// 私密Blob 内的相对路径，需经 /api/pose-image 代理访问",
        "  final String imagePath;",
        "}",
        "",
        f"/// 全部姿势预设（{len(rows)} 条，{len(per_id_groups)} 个唯一姿势）",
        "const List<PoseEntry> kPoseEntries = [",
    ]
    for r in rows:
        g = r["group"]
        lines.append(
            f"  PoseEntry(id: '{r['id']}', code: '{r['code']}', group: PoseGroup.{g},"
        )
        lines.append(f"      name: '{esc(r['name'])}', desc: '{esc(r['desc'])}',")
        lines.append(
            f"      prompt: '{esc(r['prompt'])}', imagePath: '{r['image']}'),"
        )
    lines.append("];")
    lines.append("")
    os.makedirs(os.path.dirname(OUT_DART), exist_ok=True)
    with open(OUT_DART, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    # ── UI 清单 ──
    os.makedirs(os.path.dirname(OUT_JSON), exist_ok=True)
    with open(OUT_JSON, "w", encoding="utf-8") as f:
        json.dump({
            "source": "https://www.posemaniacs.com",
            "count": len(rows),
            "uniquePoses": len(per_id_groups),
            "groups": [
                {"code": g, "label": GROUP_LABEL[g], "count": counts[g]}
                for g in ("sit", "kneel", "lie")
            ],
            "items": rows,
        }, f, ensure_ascii=False, indent=1)

    print(f"\n→ {OUT_DART}  ({len(lines)} 行)")
    print(f"→ {OUT_JSON}  ({len(rows)} 条)")


if __name__ == "__main__":
    main()