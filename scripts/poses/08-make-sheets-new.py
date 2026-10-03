#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把待命名的归一化姿势图拼成带索引的拼图，供逐批看图命名。

为什么拼图：站点只给 poseId，没有任何中文名或描述，601 张一张张看
不现实。这里每张 sheet 放 20 个（5列×4 行），一次看 20 个姿势，
命名时只需报 sheet 内序号，映射由 poseId 保证不会错位。

⚠️ 序号必须按sheet_index.json 核对，不能凭记忆写：
   上一批 205 张时就因为凭记忆写 idx，把 add(45,...) 写到了别的姿势上，
   连续两次改错。生成器里内置了add() 的idx 断言来防这个。

用法：
  python3 08-make-sheets-new.py            # 全部 601 张
  python3 08-make-sheets-new.py --start 0 --count 40   # 只出某几批
"""
import json
import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, 'norm')
OUT = os.path.join(ROOT, 'sheets')
TODO = os.path.join(ROOT, 'todo-name.json')
INDEX = os.path.join(ROOT, 'sheet_index_new.json')

COLS, ROWS = 5, 4
PER = COLS * ROWS
CELL = 260
PAD = 6
LABEL_H = 24


def main():
    os.makedirs(OUT, exist_ok=True)
    todo = json.load(open(TODO, encoding='utf-8'))
    # 按 poseId 排序保证可复现
    todo.sort(key=lambda x: (x['poseId'], x['modelId']))

    start = int(sys.argv[sys.argv.index('--start') + 1]) if '--start' in sys.argv else 0
    count = int(sys.argv[sys.argv.index('--count') + 1]) if '--count' in sys.argv else 10 ** 9
    end = min(start + count, len(todo))

    sheets = [todo[i:i + PER] for i in range(0, len(todo), PER)]
    print(f'待命名 {len(todo)} 张 → {len(sheets)} 张 sheet（每张 {PER} 格），'
          f'本次处理 sheet {start}..{min(end, len(sheets))}')

    index = []
    for si in range(start, min(end, len(sheets))):
        batch = sheets[si]
        W = COLS * (CELL + PAD) + PAD
        H = ROWS * (CELL + PAD + LABEL_H) + PAD
        canvas = Image.new('RGB', (W, H), (238, 238, 242))
        dr = ImageDraw.Draw(canvas)
        for j, it in enumerate(batch):
            gi = si * PER + j
            r, c = divmod(j, COLS)
            x = PAD + c * (CELL + PAD)
            y = PAD + r * (CELL + PAD + LABEL_H)
            # 棋盘底：透明区在白底上看不出边界，浅灰格让轮廓可辨
            for cy in range(0, CELL, 20):
                for cx in range(0, CELL, 20):
                    col = (248, 248, 250) if ((cx // 20 + cy // 20) % 2 == 0) else (230, 230, 235)
                    dr.rectangle([x + cx, y + cy, x + min(cx + 20, CELL), y + min(cy + 20, CELL)], fill=col)
            fp = os.path.join(SRC, f"{it['poseId']}_{it['modelId']}.webp")
            if os.path.exists(fp):
                im = Image.open(fp)
                bg = Image.new('RGB', im.size, (255, 255, 255))
                bg.paste(im, mask=im.split()[3])
                bg.thumbnail((CELL - 4, CELL - 4), Image.LANCZOS)
                canvas.paste(bg, (x + (CELL - bg.size[0]) // 2, y + (CELL - bg.size[1]) // 2))
            lab = f"#{gi:03d} {it['poseId']}/{it['modelId']}"
            dr.text((x + 4, y + CELL + 6), lab, fill=(20, 20, 30))
            index.append({'idx': gi, 'sheet': si, 'poseId': it['poseId'],
                          'modelId': it['modelId'], 'file': fp})
        p = os.path.join(OUT, f'nsheet_{si:02d}.png')
        canvas.save(p)
        print(f'  {p}  ({len(batch)} 个)')

    # 追加写索引（分批跑也能累积）
    prev = json.load(open(INDEX, encoding='utf-8')) if os.path.exists(INDEX) else []
    seen = {e['idx'] for e in prev}
    prev += [e for e in index if e['idx'] not in seen]
    prev.sort(key=lambda e: e['idx'])
    json.dump(prev, open(INDEX, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'\n索引累计 {len(prev)}/{len(todo)} → {INDEX}')


if __name__ == '__main__':
    main()
