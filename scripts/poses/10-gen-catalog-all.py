#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
合并两批命名，生成 806 条完整姿势库的 Dart + JSON。

数据来源：
  ·第一批 205 条：assets/poses/index.json（已上线，编号 S/K/L + xx）
  · 第二批 601 条：09-pose-names-new.py（本次新增，编号按分组重排）

⚠️ 关键设计：跨批次的分组不兼容
────────────────────────────────────────────────────────────────────
第一批的分组是**源站的三个分类页**（sitting/kneeling/lying），
所以同一个姿势会出现两次（232 条 → 205 个唯一姿势）。
第二批 601 条走的是**新分组体系**（19 组，一个姿势只属于一组）。

如果直接拼成 806 条，会出现「同一个id 在两套分组里各出现一次」，
而两套分组的语义还不一样 → App 里 Tab 会混乱。

所以这里**统一到新分组体系**：
  · 806 个唯一姿势，各出现一次，共 806 条
  · 分组用 taxonomy.json（体位优先 + 动态兜底）
  · 老数据里那 27 条跨组重复项自然消失
  · 编号规则改为 <分组首字母>-<三位序号>，与分组一致

唯一性断言（上一批就是靠这个抓出 8 条重名 + 4 组重复 prompt）：
  1. id唯一
  2. name 唯一
  3. prompt 唯一（按 id 去重后校验——806 条此时已无跨组重复）
  4. code 唯一且前缀与分组一致
  5. imagePath 匹配服务端白名单 ^poses/\d{7}_\d{5}\.webp$
"""
import importlib.util
import json
import os
import re
from collections import Counter, OrderedDict

ROOT = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(ROOT, '..', '..'))

# ── 分组定义（顺序即 App 里Tab 的顺序，按「常用度」排）──────────────
GROUPS = OrderedDict([
    ('standing',   ('ST', '站立', '站姿与行走，数量最多')),
    ('sitting',    ('SI', '坐姿', '坐地坐姿，日常与柔美')),
    ('squatting',  ('SQ', '蹲姿', '深蹲半蹲，腿部线条主场')),
    ('kneeling',   ('KN', '跪姿', '跪、跪坐，柔美且有故事感')),
    ('lying',      ('LY', '躺卧', '各类躺姿的总入口')),
    ('onSide',     ('OS', '侧卧', '侧躺、侧身卧姿的完整线条')),
    ('onBack',     ('OB', '仰卧', '正面仰躺，摊开身体')),
    ('onStomach',  ('OM', '俯卧', '趴卧，突出背部与腿部')),
    ('sittingChair', ('SC', '坐椅', '坐椅子上的日常与职场感')),
    ('handStanding', ('HS', '倒立', '手撑倒立，力量感线条')),
    ('hanging',    ('HG', '悬挂', '吊挂、单腿挂起等悬空动作')),
    ('floating',   ('FL', '漂浮', '悬浮、跳跃后无重力的姿态')),
    ('jump',       ('JM', '跳跃', '腾空、跃起的一瞬')),
    ('dance',      ('DN', '舞动', '舞蹈、伸展类流动动作')),
    ('fight',      ('FG', '格斗', '拳击、格斗、力量对抗')),
    ('run',        ('RN', '奔跑', '跑动、行走中的动态')),
    ('sport',      ('SP', '运动', '各类球类与健身运动')),
    ('lean',       ('LN', '倚靠', '倚墙、倚靠支撑的放松姿态')),
    ('other',      ('OT', '其他动态', '有明确肢体动作但无固定体位')),
])

# 中文名首词 → 应该在哪个组（用于发现明显错配，只警告不阻断）
HEAD2GROUP = {
    '站立': 'standing', '站姿': 'standing', '行走': 'standing', '奔跑': 'run',
    '坐姿': 'sitting', '坐地': 'sitting', '蹲姿': 'squatting', '深蹲': 'squatting',
    '跪姿': 'kneeling', '跪坐': 'kneeling', '半跪': 'kneeling',
    '躺卧': 'lying', '仰卧': 'onBack', '俯卧': 'onStomach', '侧卧': 'onSide',
    '坐椅': 'sittingChair', '倒立': 'handStanding', '手撑倒立': 'handStanding',
    '悬挂': 'hanging', '漂浮': 'floating', '跳跃': 'jump', '舞动': 'dance',
    '舞蹈': 'dance', '格斗': 'fight', '运动': 'sport', '倚靠': 'lean',
}


def load_new_names():
    spec = importlib.util.spec_from_file_location(
        'pn', os.path.join(ROOT, '09-pose-names-new.py'))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    got, missing = m.coverage(601)
    assert not missing, f'命名缺失 {len(missing)} 条：{missing[:10]}'
    return {i: (n, d, p) for i, n, d, p in m.all_names()}


def main():
    tax = json.load(open(os.path.join(ROOT, 'taxonomy.json'), encoding='utf-8'))
    sheet = json.load(open(os.path.join(ROOT, 'sheet_index_new.json'), encoding='utf-8'))
    old = json.load(open(os.path.join(REPO, 'assets', 'poses', 'index.json'), encoding='utf-8'))
    p2t = {k: set(v) for k, v in json.load(
        open(os.path.join(ROOT, 'pose2tags.json'), encoding='utf-8')).items()}

    new_names = load_new_names()
    sheet_by_idx = {e['idx']: e for e in sheet}

    # ── 组装 806 条：老205 条 + 新 601 条 ────────────────────────
    #老数据是 232 条但只有 205 个唯一姿势（27 个同时属于源站两个分类，
    # 在 sitting/kneeling/lying 各占一行共用同一张图）。新分组体系下
    # 「一个姿势只属于一个组」，所以这里按 id 去重，那 27 条自然消失。
    items = []
    seen = {}
    for it in old['items']:
        key = f"{it['srcPoseId']}_{it['srcModelId']}"
        if key in seen:
            continue
        seen[key] = True
        pid, mid = it['srcPoseId'], it['srcModelId']
        g = tax['assign'][pid]
        items.append({
            'poseId': pid, 'modelId': mid, 'group': g,
            'name': it['name'], 'desc': it['desc'], 'prompt': it['prompt'],
        })
    for idx, e in sheet_by_idx.items():
        n, d, p = new_names[idx]
        pid, mid = e['poseId'], e['modelId']
        g = tax['assign'][pid]
        key = f'{pid}_{mid}'
        if key in seen:# 与老数据重合（实测为 0，留着当保险）
            continue
        seen[key] = True
        items.append({'poseId': pid, 'modelId': mid, 'group': g,
                      'name': n, 'desc': d, 'prompt': p})

    assert len(items) == 806, f'应有 806 条，实得 {len(items)}'
    assert len(seen) == 806, f'唯一 id 应为 806，实得 {len(seen)}'

    # ── 编号：按分组顺序连号 ──────────────────────────────────────
    counter = Counter()
    for it in sorted(items, key=lambda x: x['poseId']):
        pre = GROUPS[it['group']][0]
        counter[it['group']] += 1
        it['code'] = f'{pre}-{counter[it["group"]]:03d}'
        it['id'] = f'pm-{it["poseId"]}-{it["modelId"]}'
        it['imagePath'] = f'poses/{it["poseId"]}_{it["modelId"]}.webp'
        it['tags'] = sorted(p2t.get(it['poseId'], []))
        # 中文名去掉体位前缀后作为名（App 里分组已有标签，不用重复）
        head, _, tail = it['name'].partition(' · ')
        it['action'] = tail or head
        it['cnHead'] = head

    # ── 唯一性断言 ────────────────────────────────────────────────
    def uniq(key, label):
        c = Counter(x[key] for x in items)
        dup = {k: v for k, v in c.items() if v > 1}
        assert not dup, f'{label}重复：{list(dup.items())[:5]}'

    uniq('id', 'id')
    uniq('code', '编号')
    uniq('name', '中文名')
    uniq('prompt', '英文 prompt')
    uniq('imagePath', '图片路径')

    for it in items:
        assert re.match(r'^poses/\d{7}_\d{5}\.webp$', it['imagePath']), it['imagePath']
        assert re.search(r'[a-zA-Z]', it['prompt']), it['id']
        assert GROUPS[it['group']][0] == it['code'][:2], \
            f'{it["id"]} 编号前缀与分组不符'

    # 分组覆盖：每条都得有分组
    assert all(it['group'] in GROUPS for it in items), '有姿势的分组不在GROUPS 里'

    # ── 写 JSON ─────────────────────────────────────────────────
    out = {
        'source': 'posemaniacs.com 女性姿势库（总览页全量 806 条）',
        'count': len(items),
        'groups': [{'key': k, 'code': v[0], 'cn': v[1], 'hint': v[2],
                    'count': counter.get(k, 0)} for k, v in GROUPS.items()],
        'tagCount': len(tax['tags']),
        'items': sorted(items, key=lambda x: x['code']),
    }
    jpath = os.path.join(REPO, 'assets', 'poses', 'index.json')
    json.dump(out, open(jpath, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
    print(f'→ {jpath}（{len(items)} 条，{len(GROUPS)} 组）')

    # ── 写 Dart ─────────────────────────────────────────────────
    def q(s):
        return s.replace('\\', '\\\\').replace("'", r"\'").replace('$', r'\$')

    L = []
    L.append('// GENERATED CODE - 由 scripts/poses/10-gen-catalog-all.py 生成，请勿手改。')
    L.append('//')
    L.append(f'// 姿势库：{len(items)} 条，覆盖 posemaniacs 女性库全部内容。')
    L.append('// 分组 19 个（体位优先 + 动态动作兜底），每个姿势只属于一个组。')
    L.append('//')
    L.append('// ⚠️ 中文名与英文 prompt 都是**逐张看图**写出来的，源站没有这两样东西。')
    L.append('// 改这个文件没有意义，要改请改scripts/poses/09-pose-names-new.py 后重新生成。')
    L.append('')
    L.append('/// 姿势分组。体位类决定"摆什么姿势"，动态类是无固定体位的动作。')
    L.append('enum PoseGroup {')
    for k in GROUPS:
        L.append(f'  {k},')
    L.append('}')
    L.append('')
    L.append('/// 一条姿势预设。')
    L.append('class PoseEntry {')
    L.append('  const PoseEntry({')
    L.append('    required this.id,')
    L.append('    required this.code,')
    L.append('    required this.group,')
    L.append('    required this.name,')
    L.append('    required this.desc,')
    L.append('    required this.prompt,')
    L.append('    required this.imagePath,')
    L.append('    this.tags = const [],')
    L.append('  });')
    L.append('')
    L.append('  /// 形如 pm-0000038-00004，源站 poseId + modelId')
    L.append('  final String id;')
    L.append('  /// 形如 SI-042，编号前缀与分组一致')
    L.append('  final String code;')
    L.append('  final PoseGroup group;')
    L.append('  /// 中文短名，形如「坐姿 · 抱膝侧望」')
    L.append('  final String name;')
    L.append('  /// 中文动作说明')
    L.append('  final String desc;')
    L.append('  /// 英文提示词 —— **真正发给生图模型的就是这条**')
    L.append('  final String prompt;')
    L.append('  /// 参考图在私密 blob 里的相对路径（经 /api/pose-image 代理取）')
    L.append('  final String imagePath;')
    L.append('  /// 源站标签原始值，用于 App 内搜索/筛选')
    L.append('  final List<String> tags;')
    L.append('}')
    L.append('')
    L.append('/// 全部姿势预设。')
    L.append(f'const List<PoseEntry> kPoseEntries = [')
    for it in out['items']:
        tg = ', '.join(f"'{q(t)}'" for t in it['tags'])
        L.append("  PoseEntry(")
        L.append(f"    id: '{q(it['id'])}',")
        L.append(f"    code: '{q(it['code'])}',")
        L.append(f"    group: PoseGroup.{it['group']},")
        L.append(f"    name: '{q(it['name'])}',")
        L.append(f"    desc: '{q(it['desc'])}',")
        L.append(f"    prompt: '{q(it['prompt'])}',")
        L.append(f"    imagePath: '{q(it['imagePath'])}',")
        L.append(f"    tags: [{tg}],")
        L.append('  ),')
    L.append('];')
    L.append('')
    dpath = os.path.join(REPO, 'app', 'lib', 'services', 'pose_library_data.g.dart')
    open(dpath, 'w', encoding='utf-8').write('\n'.join(L))
    print(f'→ {dpath}')

    # ── 报告 ───────────────────────────────────────────────────
    print(f'\n共 {len(items)} 条 / {len(GROUPS)} 组：')
    for k, v in GROUPS.items():
        print(f'  {v[1]:6s} {v[0]}-{counter.get(k,0):3d}条  {v[2]}')
    print(f'\n图片文件：{len({x["imagePath"] for x in items})} 个唯一'
          f'（806 条里可能有跨组的同一张图，但新体系下已无重复）')
    print('全部断言通过：id / code / name / prompt / imagePath 唯一，'
          '编号前缀与分组一致，路径形态符合服务端白名单')


if __name__ == '__main__':
    main()
