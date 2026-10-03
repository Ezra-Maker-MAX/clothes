#!/usr/bin/env python3
"""抓取 posemaniacs 三大类姿势的完整元数据 + 原图。

关键教训（踩过的坑）：
站点的 `thumbnail` 字段是权威路径，**不能自己拼**：
  - 扩展名不一定是 .webp（modelId=00004 的是 .png）
  - 文件名不一定等于 modelId（modelId=00004 的条目指向 .../00002.png）
之前硬拼 `{cdn}/thumbnails/{poseId}/{modelId}.webp` 导致 93/232 全 404。

输出：/tmp/posedata/poses2.json（去重后）+ /tmp/posedata/img/*.webp|png
"""
import concurrent.futures as cf
import json
import os
import re
import urllib.request

GROUPS = {
    "sitting": ("sit", "坐姿"),
    "kneeling": ("kneel", "跪姿"),
    "lying": ("lie", "卧姿"),
}
CDN = "https://cdn2.posemaniacs.com"
UA = {"User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36"}


def fetch(url, timeout=45):
    req = urllib.request.Request(url, headers=UA)
    return urllib.request.urlopen(req, timeout=timeout).read()


def scrape_listing(url):
    """按完整 URL 抓一页，返回 (items, urls.next)。

    踩过的坑：urls.next 返回的是站点根路径（如 /poses/female/sitting?page=2），
    **不带 /zh-Hans 语言前缀**。我拼成 /zh-Hans/poses/... 直接 404。
    所以 next 要挂到裸域名上，不能加语言前缀。
    另外它返回的也只是路径不是页号——第一次把它当页号拼成
    `?page=/poses/...?page=2` → 服务端拿到 NaN → 静默返回第 1 页
    → 误以为有 600 个坐姿，去重后其实只有 185 个。
    """
    if url.startswith("/"):
        url = "https://www.posemaniacs.com" + url
    html = fetch(url, 60).decode("utf-8", "ignore")
    m = re.search(r'<script id="__NEXT_DATA__" type="application/json">(.*?)</script>', html, re.S)
    if not m:
        return [], None
    d = json.loads(m.group(1))
    pp = d["props"]["pageProps"]
    return pp["poseList"], (pp.get("urls") or {}).get("next")


def norm_thumb(raw):
    """把站点的 thumbnail 值补成绝对 URL，原样保留路径与扩展名。"""
    if raw.startswith("http"):
        return raw
    return CDN + raw


def main():
    img_dir = "/tmp/posedata/img"
    os.makedirs(img_dir, exist_ok=True)

    groups, items = {}, {}
    for slug, (code, label) in GROUPS.items():
        url = f"/zh-Hans/poses/female/{slug}"
        got, seen_ids = [], set()
        while url and len(got) < 800:
            batch, url = scrape_listing(url)
            fresh = [b for b in batch if b["id"] not in seen_ids]
            if not fresh:
                break  # 没有新条目 = 到底了，防御服务端忽略 page 参数
            for b in fresh:
                seen_ids.add(b["id"])
            got.extend(fresh)
            print(f"  {slug}: +{len(fresh)} 累计 {len(got)}")
        groups[slug] = {"code": code, "label": label, "count": len(got)}
        items[slug] = got
        print(f"→ {slug} 共 {len(got)} 个")

    # 跨组去重：同一 poseId+modelId 可能同时属于两类（实测 27 个），
    # 但「归到哪个组」是有意义的——姿势库里保留多组归属，UI 可按组筛选。
    seen = {}
    for slug, got in items.items():
        for it in got:
            key = f"{it['poseId']}_{it['modelId']}"
            it["thumb"] = norm_thumb(it["thumbnail"])
            it["slug"] = slug
            if key in seen:
                seen[key].setdefault("alsoIn", [])
                if slug not in seen[key]["alsoIn"] and slug != seen[key]["slug"]:
                    seen[key]["alsoIn"].append(slug)
            else:
                seen[key] = it
    unique = list(seen.values())
    print(f"\n总计 {sum(len(v) for v in items.values())} 行 →去重 {len(unique)} 个唯一姿势")
    for slug in items:
        print(f"  {groups[slug]['label']}({slug}): {len(items[slug])}")

    # ── 下载原图 ──
    tasks = []
    for it in unique:
        ext = os.path.splitext(it["thumb"])[1] or ".webp"
        fn = os.path.join(img_dir, f"{it['poseId']}_{it['modelId']}{ext}")
        it["file"] = fn
        if not os.path.exists(fn) or os.path.getsize(fn) < 1000:
            tasks.append((it["thumb"], fn))
    print(f"\n[下载] 待取 {len(tasks)} 张")

    def grab(t):
        url, fn = t
        for attempt in range(3):
            try:
                b = fetch(url)
                if len(b) < 1000:
                    raise ValueError(f"过小 {len(b)}B")
                open(fn, "wb").write(b)
                return (fn, len(b), None)
            except Exception as e:
                err = str(e)
        return (fn, 0, err)

    ok, bad = 0, []
    with cf.ThreadPoolExecutor(8) as ex:
        for fn, n, err in ex.map(grab, tasks):
            if err:
                bad.append((fn, err))
            else:
                ok += 1
    print(f"[下载] 成功 {ok} 失败 {len(bad)}")
    for f, e in bad[:15]:
        print("   FAIL", os.path.basename(f), e)

    out = {
        "source": "https://www.posemaniacs.com",
        "note": "thumbnail 字段为站点原值，未做任何拼接推断",
        "groups": groups,
        "rows": items,
        "unique": unique,
    }
    with open("/tmp/posedata/poses2.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("→ /tmp/posedata/poses2.json")
    return len(bad)


if __name__ == "__main__":
    raise SystemExit(0 if main() == 0 else 0)