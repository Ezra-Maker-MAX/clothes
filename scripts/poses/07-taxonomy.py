#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 56 个源站标签压成 App 可用的分组 + 标签体系。

────────────────────────────────────────────────────────────────────
为什么不能直接拿源站标签当 Tab（实测数据）
────────────────────────────────────────────────────────────────────
源站有 56 个标签，但它们**不是同一个维度**的，直接铺成 Tab 会很难用：

  体位类（决定"摆什么姿势"，适合做 Tab）
      standing 334 / sitting 121 / squatting 86 / kneeling 59 / lying 52
      floating 41 / sitting-on-chair 30 / on-side 20 / on-back 19
      hand-standing 18 / hanging 9 / on-stomach 6
  动作特征类（决定"手怎么放、身子怎么扭"，**不适合**做 Tab）
      raising-arm 283 / twisting-body 234 / twisting-neck 208
      sexy 153 / fighting 140 / dancing 131 / raising-leg 120 ...
  风格类（适合做筛选，不适合做 Tab）
      daily-life 110 / cool 95 / idol 66 / fashion 50 ...

而且体位标签**并不互斥**（实测）：
  · 578 条只有 1 个体位标签，59 条有 2 个，8 条有 3 个
  · **161 条一个体位标签都没有**（占 20%），最常见的是
    raising-arm(69) / twisting-body(56) / twisting-neck(52) / jumping(47)
    → 这些是「站立时抬手」这类，源站只标了动作没标体位
  · on-back(19)、on-side(20) **不完全属于** lying：两者只有 12/13 条交集
    （例如"侧躺"有的被标成 on-side 没标 lying）

所以本脚本的策略：
1. **主分组 = 体位标签**（一个姿势只落一个主 Tab，按优先级取，
   避免 806 条在 Tab 里重复出现）
2. 一个体位标签都没有的 → 归入「其他动态」（跳跃/舞蹈/战斗/奔跑等
   确实没有固定体位的动作），并按特征子标签再细分
3. **动作特征/风格标签 → 存进每条姿势的 tags 字段**，供 UI 做筛选
   （筛选芯片），而不是占Tab 位

标签页与姿势页的对应关系（实测 56/56 全部可筛）:
  https://www.posemaniacs.com/poses/female/{value}
⚠️ query 参数 ?tag=xxx 会被静默忽略（返回未筛选的第1 页），
   必须用路径式。这坑和urls.next 不带 locale 前缀是同一类。
"""
import json
import os
from collections import Counter, defaultdict

ROOT = os.path.dirname(os.path.abspath(__file__))
P2T = os.path.join(ROOT, 'pose2tags.json')
OUT = os.path.join(ROOT, 'taxonomy.json')

# ── 主分组：按优先级取第一个命中的体位标签 ───────────────────────
# 顺序即优先级。放前面的优先（细分标签排在粗标签前面，
# 例如 on-side 比 lying 更具体，应该先命中）。
GROUPS = [
    ('onSide',       'on-side',        '侧卧',   '侧躺、侧身卧姿的完整线条'),
    ('onBack',       'on-back',        '仰卧',   '正面仰躺，摊开身体'),
    ('onStomach',    'on-stomach',     '俯卧',   '趴卧，突出背部与腿部'),
    ('sittingChair', 'sitting-on-chair', '坐椅', '坐椅子上的日常与职场感'),
    ('handStanding', 'hand-standing',  '倒立',   '手撑倒立，力量感线条'),
    ('hanging',      'hanging',        '悬挂',   '吊挂、单腿挂起等悬空动作'),
    ('squatting',    'squatting',      '蹲姿',   '深蹲半蹲，腿部线条主场'),
    ('kneeling',     'kneeling',       '跪姿',   '跪、跪坐，柔美且有故事感'),
    ('lying',        'lying',          '躺卧',   '各类躺姿的总入口'),
    ('sitting',      'sitting',        '坐姿',   '坐地、坐姿，日常与柔美'),
    ('floating',     'floating',       '漂浮',   '悬浮、跳跃后无重力的姿态'),
    ('standing',     'standing',       '站立',   '站姿与行走，数量最多'),
]

# ── 「其他动态」子分类：给那161 条无体位标签的姿势一个落脚点 ──────
DYNAMIC = [
    ('jump',    'jumping',          '跳跃',   '腾空、跃起的一瞬'),
    ('dance',   'dancing',          '舞动',   '舞蹈、伸展类流动动作'),
    ('fight',   'fighting',         '格斗',   '拳击、格斗、力量对抗'),
    ('run',     'running',          '奔跑',   '跑动、行走中的动态'),
    ('sport',   'sports',           '运动',   '各类球类与健身运动'),
    ('lean',    'leaning',          '倚靠',   '倚墙、倚靠支撑的放松姿态'),
]

# 源站有4 条姿势只打了纯风格标签（sexy / idol / raising-arm / twisting-*），
# 连体位标签都没有。实测这 4 条都是**站立时的姿态**（抬手臂、转头、扭身），
# 源站只是漏标了 standing。归到「站立」比扔进「未分类」更符合画面实际 ——
# 分类的唯一目的是让用户好找姿势，不是忠实反映源站的标注疏漏。
FALLBACK_GROUP = 'standing'

# 归到「其他动态」时按顺序匹配的特征标签（配合 DYNAMIC 使用）
DYNAMIC_TAGS = ['jumping', 'dancing', 'fighting', 'running', 'sports', 'walking',
                'ballet', 'yoga', 'parkour', 'athletics', 'falling', 'fitness',
                'body-building', 'basketball', 'soccer', 'volleyball', 'baseball',
                'swimming', 'sumo', 'punching', 'kicking', 'ball-game', 'throwing',
                'leaning']

# ── 全部 56 个标签的中文名（源站有一部分 label 是英文未翻译）──────
TAG_CN = {
    'standing': '站立', 'lying': '躺卧', 'sitting': '坐姿', 'fighting': '格斗',
    'sexy': '性感', 'squatting': '蹲下', 'body-building': '健美', 'walking': '行走',
    'running': '奔跑', 'yoga': '瑜伽', 'ballet': '芭蕾', 'jumping': '跳跃',
    'sports': '运动', 'dancing': '跳舞', 'falling': '下落', 'parkour': '跑酷',
    'kneeling': '跪姿', 'hand-standing': '倒立', 'daily-life': '日常',
    'fitness': '锻炼', 'floating': '漂浮', 'pushing': '推', 'pulling': '拉',
    'pointing': '指', 'crossing-arms': '交叉臂', 'twisting-body': '扭躯',
    'raising-arm': '抬手', 'raising-leg': '抬腿', 'twisting-neck': '转头',
    'crossing-legs': '翘腿', 'hanging': '悬挂', 'kicking': '踢腿',
    'punching': '拳击', 'leaning': '倚靠', 'baseball': '棒球', 'soccer': '足球',
    'sumo': '相扑', 'volleyball': '排球', 'basketball': '篮球', 'athletics': '田径',
    'swimming': '游泳', 'idol': '偶像', 'damage': '受伤', 'couple': '双人',
    'on-stomach': '俯卧', 'on-back': '仰卧', 'on-side': '侧卧', 'throwing': '投掷',
    'ball-game': '球类', 'sad': '情绪低落', 'hand-on-hip': '叉腰',
    'sitting-on-chair': '坐椅', 'relax': '放松', 'cool': '酷感', 'fashion': '时尚',
    'fool': '搞怪',
}

# 用于搜索的标签（太泛的过滤掉，避免搜索结果等于全库）
SEARCH_TAGS = set(TAG_CN) - {'sexy', 'cool', 'fashion', 'idol', 'daily-life'}


def main():
    p2t = {k: set(v) for k, v in json.load(open(P2T, encoding='utf-8')).items()}

    # 标签 → 姿势（用于筛「某标签下有那些姿势」）
    tag2pose = defaultdict(set)
    for pid, tags in p2t.items():
        for t in tags:
            tag2pose[t].add(pid)

    assign = {}      # poseId → 主分组 key
    dynamic_sub = {}  # poseId → 动态子分类 key
    fallback = []

    for pid, tags in p2t.items():
        hit = None
        for key, tag, _cn, _hint in GROUPS:      # 优先级顺序，第一个命中即止
            if tag in tags:
                hit = key
                break
        if hit:
            assign[pid] = hit
            continue
        # 无体位标签 → 找动态子分类
        sub = None
        for key, tag, _cn, _hint in DYNAMIC:
            if tag in tags:
                sub = key
                break
        if sub is None:
            for t in DYNAMIC_TAGS:
                if t in tags:
                    sub = 'other'
                    break
        if sub:
            dynamic_sub[pid] = sub
            assign[pid] = sub
        else:
            # 见 FALLBACK_GROUP 说明：源站漏标体位标签的，按站立处理
            assign[pid] = FALLBACK_GROUP
            fallback.append((pid, sorted(tags)))

    # 统计
    allkeys = [g[0] for g in GROUPS] + [d[0] for d in DYNAMIC] + ['other', 'misc']
    meta = {g[0]: {'cn': g[2], 'hint': g[3], 'kind': 'pose'} for g in GROUPS}
    meta.update({d[0]: {'cn': d[2], 'hint': d[3], 'kind': 'dynamic'} for d in DYNAMIC})
    meta['other'] = {'cn': '其他动态', 'hint': '有明确肢体动作但无固定体位', 'kind': 'dynamic'}

    cnt = Counter(assign.values())
    print(f'共 {len(p2t)} 条姿势，分成 {len(allkeys)} 个分组：\n')
    total = 0
    for k in allkeys:
        if k not in meta:      # misc 已被 fallback 取代
            continue
        n = cnt.get(k, 0)
        total += n
        print(f'  {meta[k]["cn"]:6s} {k:14s} {n:4d}')
    print(f'  ── 合计 {total}（应等于 {len(p2t)}）')

    if fallback:
        print(f'\n注：{len(fallback)} 条源站漏标体位标签，已按站立归类：')
        for pid, ts in fallback[:15]:
            print(f'  {pid}: {ts}')

    # 标签清单（含每个标签下的姿势数）
    tags_out = {}
    for t in sorted(tag2pose, key=lambda x: -len(tag2pose[x])):
        tags_out[t] = {
            'cn': TAG_CN.get(t, t),
            'count': len(tag2pose[t]),
            'searchable': t in SEARCH_TAGS,
        }

    out = {
        'groups': {k: meta[k] for k in allkeys if cnt.get(k, 0) > 0},
        'order': [k for k in allkeys if cnt.get(k, 0) > 0],
        'assign': assign,
        'dynamicSub': dynamic_sub,
        'fallbackToStanding': [pid for pid, _ in fallback],
        'tags': tags_out,
    }
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print(f'\n→ {OUT}')
    print(f'  分组 {len(out["groups"])}  标签 {len(tags_out)}'
          f'（可搜索 {sum(1 for v in tags_out.values() if v["searchable"])}）')

    # 自检：每个姿势恰好一个分组
    assert len(assign) == len(p2t), '有姿势没被分配'
    assert total == len(p2t), '分组计数与总数不符'
    print('  ✓ 自检通过：每条姿势恰好一个主分组')


if __name__ == '__main__':
    main()
