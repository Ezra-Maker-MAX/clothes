// 回归测试：AI 结果解析器 + 姿势库完整性 + 肤色 prompt 生成
//
// 为什么是这三组：
//  1) JSON 解析器 —— 模型输出格式不可控（纯 JSON / markdown 围栏 / 带废话 /
//     单对象 / 字段别名），容错分支多，是全项目最容易悄悄改坏的地方；
//  2) 姿势库 —— 25 个姿势是纯文本数据，误删条目不会有任何编译错误，
//     只会在用户点选时才发现，少一个就是功能缺陷；
//  3) skinPromptFragment —— 直接决定生成图的肤色还原质量，格式变了
//     模型就认不出来，而 prompt 写错了不会报错只会「效果变差」。
//
// 运行：flutter test
import 'package:flutter_test/flutter_test.dart';

import 'package:dapei_app/services/model_hub_service.dart';
import 'package:dapei_app/services/pose_library.dart';
import 'package:dapei_app/services/private_body_store.dart';

void main() {
  group('AI 结果解析器 _parseGarmentList', () {
    List<DetectedGarment>? parse(String s) =>
        ModelHubService.parseGarmentListForTest(s);

    test('标准数组 JSON', () {
      final r = parse('[{"name":"米色风衣","categoryHint":"outerwear"}]');
      expect(r, isNotNull);
      expect(r!.length, 1);
      expect(r.first.name, '米色风衣');
      expect(r.first.categoryHint, 'outerwear');
    });

    test('markdown 围栏包裹（模型很常见）', () {
      final r = parse('''
分析结果如下：
```json
[{"name":"黑色西装","categoryHint":"outerwear","colorName":"黑"}]
```
以上。
''');
      expect(r, isNotNull);
      expect(r!.length, 1);
      expect(r.first.name, '黑色西装');
      expect(r.first.colorName, '黑');
    });

    test('无 json 标记的裸围栏', () {
      final r = parse('```\n[{"name":"牛仔裤","categoryHint":"bottoms"}]\n```');
      expect(r, isNotNull);
      expect(r!.first.name, '牛仔裤');
    });

    test('对象包裹数组：garments / items / clothes / result 都认', () {
      for (final key in ['garments', 'items', 'clothes', 'result']) {
        final r = parse('{"$key":[{"name":"衬衫","categoryHint":"tops"}]}');
        expect(r, isNotNull, reason: '键 $key 应被识别');
        expect(r!.first.name, '衬衫', reason: '键 $key 解析结果不对');
      }
    });

    test('单个对象而非数组', () {
      final r = parse('{"name":"连衣裙","categoryHint":"dresses"}');
      expect(r, isNotNull);
      expect(r!.length, 1);
      expect(r.first.name, '连衣裙');
    });

    test('前后有废话时退化抓第一个 {...} 块', () {
      final r = parse('好的，我识别到：{"name":"风衣","categoryHint":"outerwear"} 希望有帮助');
      expect(r, isNotNull);
      expect(r!.first.name, '风衣');
    });

    test('box 支持 bbox / rect 别名并归一化', () {
      final r = parse('[{"name":"T恤","box":[0,0,500,500]}]');
      expect(r!.first.box, isNotNull);
      final b = r.first.box!;
      expect(b.length, 4);
      expect(b[2], closeTo(0.5, 0.001)); // 宽 500/1000
      // 别名也要认
      final r2 = parse('[{"name":"T恤","bbox":[0,0,500,500]}]');
      expect(r2!.first.box, isNotNull);
      final r3 = parse('[{"name":"T恤","rect":[0,0,500,500]}]');
      expect(r3!.first.box, isNotNull);
    });

    test('无名条目被丢弃（name 为空不进入结果）', () {
      final r = parse('[{"name":"","categoryHint":"tops"},{"name":"真货","categoryHint":"tops"}]');
      expect(r!.length, 1);
      expect(r.first.name, '真货');
    });

    test('完全无法解析时返回 null 而不是抛异常', () {
      // 这条很关键：解析失败不能让整个识别流程崩掉
      expect(parse(''), isNull);
      expect(parse('   '), isNull);
      expect(parse('这里没有任何 JSON'), isNull);
      expect(parse('{坏掉的 json'), isNull);
      expect(parse('[{"name":"缺右括号"'), isNull);
      expect(parse('12345'), isNull);
    });
  });

  group('chat/completions content 提取', () {
    test('标准 OpenAI 形态', () {
      final r = ModelHubService.extractContentForTest(
        '{"choices":[{"message":{"content":"hello"}}]}',
      );
      expect(r, 'hello');
    });

    test('多模态数组形态 [{type:text,text:...}]', () {
      final r = ModelHubService.extractContentForTest(
        '{"choices":[{"message":{"content":[{"type":"text","text":"AB"},{"type":"text","text":"CD"}]}}]}',
      );
      expect(r, 'ABCD');
    });

    test('流式 delta 形态', () {
      final r = ModelHubService.extractContentForTest(
        '{"choices":[{"delta":{"content":"chunk"}}]}',
      );
      expect(r, 'chunk');
    });

    test('reasoning_content 兜底（推理模型）', () {
      final r = ModelHubService.extractContentForTest(
        '{"choices":[{"message":{"reasoning_content":"思考"}}]}',
      );
      expect(r, '思考');
    });

    test('结构不符时返回 null', () {
      expect(ModelHubService.extractContentForTest('{"choices":[]}'), isNull);
      expect(ModelHubService.extractContentForTest('{"foo":1}'), isNull);
      expect(ModelHubService.extractContentForTest('[]'), isNull);
    });
  });

  group('姿势库完整性（806 条 / 19 组）', () {
    // 数据来源：posemaniacs.com 女性姿势库**总览页全量806 条**。
    // 806 条 = 一个姿势一条，不存在跨组重复（早期版本按源站三个分类页
    // 收 232 条，里面有 27 个姿势各出现两次，已在新体系里消除）。
    // 数字由 scripts/poses/10-gen-catalog-all.py 从源数据生成。
    test('总数为 806，19 个分组数量与源数据一致', () {
      expect(PoseLibrary.all.length, 806);
      const expected = {
        PoseGroup.standing: 320,
        PoseGroup.sitting: 68,
        PoseGroup.squatting: 83,
        PoseGroup.kneeling: 36,
        PoseGroup.lying: 18,
        PoseGroup.onSide: 20,
        PoseGroup.onBack: 18,
        PoseGroup.onStomach: 4,
        PoseGroup.sittingChair: 28,
        PoseGroup.handStanding: 16,
        PoseGroup.hanging: 8,
        PoseGroup.floating: 34,
        PoseGroup.jump: 47,
        PoseGroup.dance: 34,
        PoseGroup.fight: 20,
        PoseGroup.run: 9,
        PoseGroup.sport: 13,
        PoseGroup.lean: 1,
        PoseGroup.other: 29,
      };
      expect(PoseGroup.values.length, expected.length,
          reason: '分组数变了就该同步更新期望值');
      expect(PoseLibrary.byGroup(PoseGroup.other).length, expected[PoseGroup.other]);
      for (final g in PoseGroup.values) {
        expect(PoseLibrary.byGroup(g).length, expected[g],
            reason: '分组 $g 数量不符（实际 ${PoseLibrary.byGroup(g).length}）');
      }
      // 各组相加必须等于总数，防止「有条目落不进任何组」
      final sum = PoseGroup.values
          .map((g) => PoseLibrary.byGroup(g).length)
          .reduce((a, b) => a + b);
      expect(sum, 806, reason: '分组数量之和 $sum ≠ 806，有姿势漏分配');
    });

    test('id 全局唯一（806 个姿势，不该有跨组重复）', () {
      final ids = PoseLibrary.all.map((p) => p.id).toList();
      expect(ids.toSet().length, 806);
      final imgs = PoseLibrary.all.map((p) => p.imagePath).toList();
      expect(imgs.toSet().length, 806,
          reason: '有姿势共用同一张图，说明数据被写重了');
    });

    test('code 全局唯一且前缀与分组一致', () {
      const prefix = {
        PoseGroup.standing: 'ST-',
        PoseGroup.sitting: 'SI-',
        PoseGroup.squatting: 'SQ-',
        PoseGroup.kneeling: 'KN-',
        PoseGroup.lying: 'LY-',
        PoseGroup.onSide: 'OS-',
        PoseGroup.onBack: 'OB-',
        PoseGroup.onStomach: 'OM-',
        PoseGroup.sittingChair: 'SC-',
        PoseGroup.handStanding: 'HS-',
        PoseGroup.hanging: 'HG-',
        PoseGroup.floating: 'FL-',
        PoseGroup.jump: 'JM-',
        PoseGroup.dance: 'DN-',
        PoseGroup.fight: 'FG-',
        PoseGroup.run: 'RN-',
        PoseGroup.sport: 'SP-',
        PoseGroup.lean: 'LN-',
        PoseGroup.other: 'OT-',
      };
      final codes = PoseLibrary.all.map((p) => p.code).toList();
      expect(codes.toSet().length, codes.length, reason: '存在重复编号');
      for (final p in PoseLibrary.all) {
        expect(p.code.startsWith(prefix[p.group]!), isTrue,
            reason: '${p.id} 的 code ${p.code} 与分组 ${p.group} 不符');
      }
    });

    test('每条都有中文名、说明与英文 prompt（缺一条就退化成无描述）', () {
      for (final p in PoseLibrary.all) {
        expect(p.name.trim(), isNotEmpty, reason: '${p.id} 缺中文名');
        expect(p.desc.trim(), isNotEmpty, reason: '${p.id} 缺说明');
        expect(p.prompt.trim(), isNotEmpty, reason: '${p.id} 缺 prompt');
        expect(RegExp(r'[a-zA-Z]').hasMatch(p.prompt), isTrue,
            reason: '${p.id} 的 prompt 不像英文描述：${p.prompt}');
      }
    });

    test('中文名 806 条全唯一（批量套模板会导致大面积重名）', () {
      // 这一项真的抓到过问题：第一批 205 条里有 8 条中文名完全一样，
      // 肉眼分辨不出来（两条明显不同的姿势文案一模一样）。
      final names = PoseLibrary.all.map((p) => p.name).toList();
      final dup = names.where((n) => names.where((x) => x == n).length > 1).toSet();
      expect(dup, isEmpty, reason: '重复中文名：${dup.take(5).toList()}');
    });

    test('英文 prompt 806 条全唯一（两条姿势描述雷同 = 白录入）', () {
      // 实测发生过：两条「坐地斜撑」文案一模一样，看图才发现一个推掌、一个低侧倾。
      final ps = PoseLibrary.all.map((p) => p.prompt).toList();
      final dup = ps.where((x) => ps.where((y) => y == x).length > 1).toSet();
      expect(dup, isEmpty, reason: '重复 prompt：${dup.take(3).toList()}');
    });

    test('动作细节词足够多样（防止批量套模板）', () {
      // 「站立 · 抬手」「站立 · 抬手」这种只是复制粘贴。
      // 换个有意义的口径：量中文名**后半段**（动作细节）的唯一率。
      // 实测 806 条里有 774 个不同细节词，少数重复是因为真的同一动作
      // 但角度不同（前面已有中文名全唯一的断言兜底）。
      final tails = PoseLibrary.all
          .map((p) => p.name.split('·').last.trim())
          .toList();
      final uniq = tails.toSet();
      expect(uniq.length, greaterThanOrEqualTo(700),
          reason: '806 条只有 ${uniq.length} 个不同动作细节，命名可能批量退化了');
      // 单个细节词不该铺满整库
      final worst = tails.length;
      expect(worst, 806, reason: '细节词统计基准不对');
      for (final t in uniq) {
        final n = tails.where((x) => x == t).length;
        expect(n, lessThanOrEqualTo(6),
            reason: '动作细节「$t」被用了 $n 次，命名退化了');
      }
    });

    test('每条都有可取的参考图路径，且路径形态受控', () {
      // 必须匹配 /api/pose-image 服务端的白名单正则，否则取图必然 400
      final re = RegExp(r'^poses/\d{7}_\d{5}\.webp$');
      for (final p in PoseLibrary.all) {
        expect(re.hasMatch(p.imagePath), isTrue,
            reason: '${p.id} 的图路径不符合白名单：${p.imagePath}');
      }
    });

    test('参考图 URL 指向自家后端代理（私有 blob 不能直连）', () {
      for (final p in PoseLibrary.all) {
        final u = p.imageUri;
        expect(u, isNotNull, reason: '${p.id} 拼不出图URL');
        expect(u!.path, '/api/pose-image');
        expect(u.queryParameters['pathname'], p.imagePath);
      }
    });

    test('byId 能反查，且查不到时返回 null', () {
      final first = PoseLibrary.all.first;
      expect(PoseLibrary.byId(first.id)?.code, first.code);
      expect(PoseLibrary.byId('不存在的姿势'), isNull);
    });

    test('每个分组都有展示标签与提示文案', () {
      for (final g in PoseGroup.values) {
        expect(PoseLibrary.groupLabels[g]?.trim(), isNotEmpty, reason: '分组 $g 缺标签');
        expect(PoseLibrary.groupHints[g]?.trim(), isNotEmpty, reason: '分组 $g 缺提示');
        expect(PoseLibrary.groupLabelOf(g), contains('${PoseLibrary.byGroup(g).length}'),
            reason: '分组 $g 的展示名里应带条目数');
      }
    });

    test('groupOrder 覆盖全部分组且兜底组在最后', () {
      expect(PoseLibrary.groupOrder.length, PoseGroup.values.length);
      expect(PoseLibrary.groupOrder.toSet().length, PoseGroup.values.length,
          reason: 'groupOrder 有重复或漏项');
      expect(PoseLibrary.groupOrder.last, PoseGroup.other,
          reason: '「其他动态」是兜底组，必须排在最后，否则 Tab 中间会出现一个只有 1 条的组');
    });

    test('搜索能命中中文名、编号与英文 prompt', () {
      expect(PoseLibrary.search(''), isEmpty, reason: '空关键词不该返回全库');
      expect(PoseLibrary.search('  '), isEmpty, reason: '空白关键词同样不该返回全库');
      // 精确名
      final first = PoseLibrary.all.first;
      expect(PoseLibrary.search(first.name).map((p) => p.id), contains(first.id));
      // 编号
      expect(PoseLibrary.search(first.code).map((p) => p.id), contains(first.id));
      // 英文词：取 prompt 里最长的那个单词
      final w = first.prompt.split(' ').reduce((a, b) => a.length >= b.length ? a : b);
      expect(PoseLibrary.search(w).map((p) => p.id), contains(first.id),
          reason: '搜英文 prompt 里的词「$w」没命中 ${first.id}');
      // 搜不到的东西不该硬返回结果
      expect(PoseLibrary.search('zzz不存在的姿势zzz'), isEmpty);
    });
  });

  group('肤色 prompt 片段生成', () {
    test('9 个部位定义齐全且中英文映射非空', () {
      expect(PrivateBodyStore.parts.length, 9);
      for (final key in ['head', 'chest', 'waist', 'arm', 'hand', 'hip', 'thigh', 'calf', 'foot']) {
        expect(PrivateBodyStore.parts.containsKey(key), isTrue, reason: '缺部位 $key');
        final v = PrivateBodyStore.parts[key]!;
        expect(v.$1.trim(), isNotEmpty, reason: '$key 缺中文名');
        expect(v.$2.trim(), isNotEmpty, reason: '$key 缺英文描述');
      }
    });

    test('8 档肤色：key/中文/色值/英文四元组都完整且色值合法', () {
      expect(PrivateBodyStore.skinTones.length, 8);
      for (final t in PrivateBodyStore.skinTones) {
        expect(t.$1.trim(), isNotEmpty, reason: '肤色 key 为空');
        expect(t.$2.trim(), isNotEmpty, reason: '${t.$1} 缺中文名');
        expect(RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(t.$3), isTrue,
            reason: '${t.$1} 色值格式不对：${t.$3}');
        expect(t.$4.trim(), isNotEmpty, reason: '${t.$1} 缺英文描述');
      }
    });

    test('肤色 key 唯一', () {
      final keys = PrivateBodyStore.skinTones.map((t) => t.$1).toList();
      expect(keys.toSet().length, keys.length, reason: '存在重复肤色 key');
    });

    test('skinColorValue 能把 hex 转成int 色值', () {
      for (final t in PrivateBodyStore.skinTones) {
        final v = PrivateBodyStore.skinColorValue(t.$1);
        expect(v, isA<int>());
        expect((v >> 24) & 0xFF, 0xFF);
      }
      // 无效 key 回退灰色而非崩溃
      expect(PrivateBodyStore.skinColorValue('不存在的key'), 0xFF9E9E9E);
    });

    test('skinLabel / skinEn 对无效 key 返回空串（不抛异常）', () {
      expect(PrivateBodyStore.skinLabel('nope'), '');
      expect(PrivateBodyStore.skinEn('nope'), '');
      expect(PrivateBodyStore.skinHex('nope'), '');
    });

    test('未设肤色时片段为空串（不能产出 " on head and face" 这种残句）', () {
      // 内存态初始为空：既没有记录就不能凭空造描述，否则 prompt 会被污染
      expect(PrivateBodyStore.skinPromptFragment, '');
    });
  });
}
