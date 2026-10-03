#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
抓取「女性全部姿势」总览页里尚未收录的原图。

背景：之前只收sitting/kneeling/lying 三个分类（205 条），
总览页 /poses/female 实有 806 条唯一姿势 → 待新增 601 条。

⚠️ 三个踩过的坑（沿用 01-scrape.py 的教训）：
1. **绝对不能用 thumbnail 字段自己拼 URL**：扩展名不固定
   （实测 444 个 .webp / 362 个 .png），文件名也不等于 modelId。
   一律原样取thumbnail 字段值。
2. **urls.next 不带 /zh-Hans locale 前缀**：拼上去直接 404。
   必须挂到裸域名 https://www.posemaniacs.com 上。
3. CDN 是 cdn2.posemaniacs.com（不是 www 也不是裸域），
   页面里的缩略图路径要拼在这个域上。

只负责下载原图（PNG/WebP 混存），归一化交给 02-normalize.py。
"""
import json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

UA = {'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120 Safari/537.36'}
BARE = 'https://www.posemaniacs.com'
CDN = 'https://cdn2.posemaniacs.com'
ROOT = os.path.dirname(os.path.abspath(__file__))
RAW = os.path.join(ROOT, 'raw')            # 原始下载（未裁切）
ALL = os.path.join(ROOT, 'all_female.json')  # 806 条总览页清单


def fetch(args):
    r, outdir = args
    dst = os.path.join(outdir, r['poseId'] + '_' + r['modelId'] + os.path.splitext(r['thumbnail'])[1])
    if os.path.exists(dst) and os.path.getsize(dst) > 2000:
        return ('skip', dst, os.path.getsize(dst))
    try:
        req = urllib.request.Request(CDN + r['thumbnail'], headers=UA)
        b = urllib.request.urlopen(req, timeout=45).read()
        if len(b) < 2000:
            return ('small', dst, len(b))
        with open(dst + '.tmp', 'wb') as f:
            f.write(b)
        os.replace(dst + '.tmp', dst)
        return ('ok', dst, len(b))
    except Exception as e:
        return ('fail', r['thumbnail'], str(e))


def main():
    rows = json.load(open(ALL))
    cur = json.load(open(os.path.join(ROOT, '..', '..', 'assets', 'poses', 'index.json')))
    have = {(it['srcPoseId'], it['srcModelId']) for it in cur['items']}
    todo = [r for r in rows if (r['poseId'], r['modelId']) not in have]
    print(f'总览页 {len(rows)} 条，已收录 {len(have)} 条，本次待下载 {len(todo)} 条')
    if '--limit' in sys.argv:
        n = int(sys.argv[sys.argv.index('--limit') + 1])
        todo = todo[:n]
        print(f'--limit 生效，只下 {n} 条')

    os.makedirs(RAW, exist_ok=True)
    stats = {'ok': 0, 'skip': 0, 'fail': 0, 'small': 0}
    fails = []
    #并发 6：再高容易触发 429，实测单张 20-270KB
    with ThreadPoolExecutor(max_workers=6) as ex:
        for i, (st, path, info) in enumerate(ex.map(fetch, [(r, RAW) for r in todo]), 1):
            stats[st] += 1
            if st == 'fail':
                fails.append((path, info))
            if i % 50 == 0 or i == len(todo):
                print(f'  [{i}/{len(todo)}] 成功{stats["ok"]} 跳过{stats["skip"]} '
                      f'失败{stats["fail"]} 过小{stats["small"]}')

    print(f'\n完成：成功 {stats["ok"]}，跳过 {stats["skip"]}，失败 {stats["fail"]}')
    if fails:
        print('失败明细（前 20）：')
        for p, e in fails[:20]:
            print(f'  {p}  {e}')
        json.dump(fails, open(os.path.join(ROOT, 'fetch-fails.json'), 'w'), ensure_ascii=False, indent=1)
    tot = sum(os.path.getsize(os.path.join(RAW, f)) for f in os.listdir(RAW))
    print(f'原图目录合计 {tot/1048576:.1f}MB，共 {len(os.listdir(RAW))} 个文件')


if __name__ == '__main__':
    main()
