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

  group('姿势库完整性（232 条 / 205 个唯一姿势）', () {
    // 数据来源：posemaniacs.com 女性姿势库三大类全收录。
    // 232 条 = 205 个唯一姿势 + 27 个跨组姿势各出现两次（既是坐姿又是跪姿）。
    // 具体数字由 scripts/gen_pose_library.py 依据源数据生成，重复运行应完全一致。
    test('总数为 232，且三个分组数量与源数据一致', () {
      expect(PoseLibrary.all.length, 232);
      expect(PoseLibrary.byGroup(PoseGroup.sit).length, 121);
      expect(PoseLibrary.byGroup(PoseGroup.kneel).length, 59);
      expect(PoseLibrary.byGroup(PoseGroup.lie).length, 52);
    });

    test('跨组姿势共用同一个 id（同一姿势在两组里不该是两个身份）', () {
      // 27 个姿势同时属于两类，去重后必须是 205
      final uniq = PoseLibrary.all.map((p) => p.id).toSet();
      expect(uniq.length, 205);
      // 跨组的姿势，其分组合法且不止一个
      final byId = <String, Set<PoseGroup>>{};
      for (final p in PoseLibrary.all) {
        byId.putIfAbsent(p.id, () => <PoseGroup>{}).add(p.group);
      }
      final cross = byId.values.where((g) => g.length > 1);
      expect(cross.length, 27, reason: '跨组姿势数应与源数据一致');
      for (final g in cross) {
        expect(g.length, 2, reason: '一个姿势最多跨两组');
      }
    });

    test('id 唯一且非空（id 随 options.pose 发给后端，重复会串姿势）', () {
      final ids = PoseLibrary.all.map((p) => p.id).toList();
      // 注意：这里只校验「同一分组内」唯一——跨组姿势本来就该重复出现
      for (final g in PoseGroup.values) {
        final gids = PoseLibrary.byGroup(g).map((p) => p.id).toList();
        expect(gids.toSet().length, gids.length,
            reason: '分组 $g 内存在重复 id');
      }
      for (final p in PoseLibrary.all) {
        expect(p.id.trim(), isNotEmpty, reason: '有空 id');
      }
      expect(ids.length, 232);
    });

    test('code 全局唯一（S/K/L 三组各自连续编号，不能撞号）', () {
      final codes = PoseLibrary.all.map((p) => p.code).toList();
      expect(codes.toSet().length, codes.length, reason: '存在重复编号');
    });

    test('code 前缀与分组一致（防止生成脚本把坐姿编成 K-xxx）', () {
      const prefix = {
        PoseGroup.sit: 'S-',
        PoseGroup.kneel: 'K-',
        PoseGroup.lie: 'L-',
      };
      for (final p in PoseLibrary.all) {
        expect(p.code.startsWith(prefix[p.group]!), isTrue,
            reason: '${p.id} 的 code ${p.code} 与分组 ${p.group} 不符');
      }
    });

    test('每条都有中文标签与英文 prompt（缺一条该姿势就退化成无描述）', () {
      for (final p in PoseLibrary.all) {
        expect(p.name.trim(), isNotEmpty, reason: '${p.id} 缺中文名');
        expect(p.desc.trim(), isNotEmpty, reason: '${p.id} 缺说明');
        expect(p.prompt.trim(), isNotEmpty, reason: '${p.id} 缺 prompt');
        // 英文 prompt 应含英文字母；全是中文说明写错了（实际是给模型看的）
        expect(RegExp(r'[a-zA-Z]').hasMatch(p.prompt), isTrue,
            reason: '${p.id} 的 prompt 不像英文描述：${p.prompt}');
      }
    });

    test('中文名重复率可控（同一 id 可复用名字，但不应大面积雷同）', () {
      // 跨组姿势共用名字是设计使然，所以这里按 id 去重后再看唯一性
      final names = <String, Set<String>>{};
      for (final p in PoseLibrary.all) {
        names.putIfAbsent(p.id, () => <String>{}).add(p.name);
      }
      for (final e in names.entries) {
        expect(e.value.length, 1,
            reason: '${e.key} 跨组时中文名不一致（同一姿势应同名）');
      }
      final uniqNames = names.values.map((s) => s.first).toSet();
      expect(uniqNames.length, greaterThanOrEqualTo(190),
          reason: '205 个姿势只有 ${uniqNames.length} 个不同名字，命名可能批量退化了');
    });

    test('prompt 按唯一姿势互不相同（两条姿势描述雷同 = 白录入）', () {
      // ⚠️ 必须先按 id 去重再查重：232 条里有 27 条是跨组姿势的第二次出现
      //（同一姿势既在「坐姿」又在「跪姿」下各占一行），prompt 相同是设计使然。
      // 真正要防的是「两个不同姿势共用一条 prompt」——实测发生过一次，
      // 两条「坐地斜撑」文案一模一样，看图才发现一个推掌、一个低侧倾。
      final byId = <String, String>{};
      for (final p in PoseLibrary.all) {
        byId.putIfAbsent(p.id, () => p.prompt);
      }
      expect(byId.length, 205);
      final prompts = byId.values.toSet();
      expect(prompts.length, byId.length,
          reason: '有 ${byId.length - prompts.length} 个姿势 prompt 重复');
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
        expect(u, isNotNull, reason: '${p.id} 拼不出图 URL');
        expect(u!.path, '/api/pose-image');
        expect(u.queryParameters['pathname'], p.imagePath);
      }
    });

    test('byId 能反查，且查不到时返回 null', () {
      final first = PoseLibrary.all.first;
      expect(PoseLibrary.byId(first.id)?.code, first.code);
      expect(PoseLibrary.byId('不存在的姿势'), isNull);
    });

    test('每个分组都有可展示的标签与提示文案', () {
      for (final g in PoseGroup.values) {
        expect(PoseLibrary.groupLabels[g]?.trim(), isNotEmpty, reason: '分组 $g 缺标签');
        expect(PoseLibrary.groupHints[g]?.trim(), isNotEmpty, reason: '分组 $g 缺提示');
        expect(PoseLibrary.groupLabelOf(g), contains('${PoseLibrary.byGroup(g).length}'),
            reason: '分组 $g 的展示名里应带条目数，否则 121 条没法找');
      }
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
