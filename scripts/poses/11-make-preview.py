#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成 806 条姿势库的单文件HTML 预览（与 App 效果一致）。

用法：python3 11-make-preview.py
输出：/workspace/姿势库预览/index.html

为什么要内联base64：单文件、离线可看、能直接发给用户看效果。
806 张图内联后约 6MB（768px WebP q=82，单张中位 32KB）。
每张图同时生成 200px 的缩略图版给网格用，详情弹窗才用大图，
否则 6MB 全塞进 DOM 首屏会卡。
"""
import base64
import io
import json
import os
from collections import Counter

from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(ROOT, '..', '..'))
IMG_DIRS = [os.path.join(ROOT, 'norm'),
            os.path.join(REPO, 'assets', 'poses', 'img'),
            '/tmp/posedata/norm']
OUT_DIR = '/workspace/姿势库预览'
THUMB = 200          # 单份图上限；详情弹窗用 CSS 放大，不另存大图

# 分组顺序 = 生成器里的 GROUPS 顺序
GROUP_ORDER = ['standing', 'sitting', 'squatting', 'kneeling', 'lying', 'onSide',
               'onBack', 'onStomach', 'sittingChair', 'handStanding', 'hanging',
               'floating', 'jump', 'dance', 'fight', 'run', 'sport', 'lean', 'other']


def find_img(fname):
    for d in IMG_DIRS:
        p = os.path.join(d, fname)
        if os.path.exists(p):
            return p
    return None


def to_b64(path, size=None):
    im = Image.open(path)
    if im.mode != 'RGBA':
        im = im.convert('RGBA')
    if size:
        im = im.copy()
        im.thumbnail((size, size), Image.LANCZOS)
    buf = io.BytesIO()
    im.save(buf, 'WEBP', quality=80, method=4)
    return base64.b64encode(buf.getvalue()).decode()


def main():
    data = json.load(open(os.path.join(REPO, 'assets', 'poses', 'index.json'), encoding='utf-8'))
    gmap = {g['key']: g for g in data['groups']}
    # ⚠️ 必须按 GROUP_ORDER 重排，不能用清单里的顺序：
    # 清单是按 poseId 排的（为了生成时稳定），直接用会让「全部」视图
    # 变成按 id 随机穿插，站立(320) 这种大组被拆散在 19 个组之间。
    items = sorted(data['items'],
                   key=lambda it: (GROUP_ORDER.index(it['group'])
                                   if it['group'] in GROUP_ORDER else 99,
                                   it['code']))

    print(f'处理 {len(items)} 条...')
    out = []
    miss = []
    for i, it in enumerate(items, 1):
        fn = it['imagePath'].split('/')[-1]
        p = find_img(fn)
        if not p:
            miss.append(fn)
            continue
        try:
            out.append({
                'code': it['code'], 'group': it['group'],
                'name': it['name'], 'desc': it['desc'], 'prompt': it['prompt'],
                'tags': it.get('tags', []),
                # 只存一份图（200px）。曾试过「网格小图 + 详情大图」两份，
                # poses.js 立刻涨到 44.6MB —— base64 把体积放大 33%，
                # 两份等于白扔 30MB。详情弹窗用 CSS 放大同一张即可。
                'b': to_b64(p, THUMB),
            })
        except Exception as e:
            miss.append(f'{fn}: {e}')
        if i % 100 == 0:
            print(f'  {i}/{len(items)}')
    assert not miss, f'缺图 {len(miss)}：{miss[:5]}'

    os.makedirs(OUT_DIR, exist_ok=True)
    json_out = os.path.join(OUT_DIR, 'poses.js')
    # 必须带 const POSE_DATA= 前缀：HTML 里直接 <script src> 引入，
    # 裸 JSON 数组不是合法 JS 声明，会报 POSE_DATA is not defined。
    with open(json_out, 'w', encoding='utf-8') as f:
        f.write('const POSE_DATA=')
        json.dump(out, f, ensure_ascii=False)
        f.write(';')

    # 统计
    cnt = Counter(x['group'] for x in out)
    print('\n分组:')
    for k in GROUP_ORDER:
        if cnt.get(k):
            print(f'  {gmap[k]["cn"]:6s} {cnt[k]:4d}  {gmap[k]["hint"]}')
    # 分组元数据另出一个 meta.js：index.html 靠它渲染下拉与提示文案。
    # 分两文件是因为姿势数据 6MB，下拉选项不需要跟着重复一遍。
    meta = {
        'G_ORDER': GROUP_ORDER,
        'G_LABELS': {k: gmap[k]['cn'] for k in GROUP_ORDER if k in gmap},
        'G_HINTS': {k: gmap[k]['hint'] for k in GROUP_ORDER if k in gmap},
    }
    with open(os.path.join(OUT_DIR, 'meta.js'), 'w', encoding='utf-8') as f:
        f.write('const G_ORDER=%s,G_LABELS=%s,G_HINTS=%s;\n' % (
            json.dumps(meta['G_ORDER'], ensure_ascii=False),
            json.dumps(meta['G_LABELS'], ensure_ascii=False),
            json.dumps(meta['G_HINTS'], ensure_ascii=False)))
    print(f'→ {OUT_DIR}/meta.js')

    size = os.path.getsize(json_out) / 1048576
    print(f'\n→ {json_out}（{len(out)} 条，{size:.1f}MB）')
    print('→ 接着运行 make_preview_html.py 生成 index.html')


if __name__ == '__main__':
    main()
