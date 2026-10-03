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

  group('姿势库完整性（25 个）', () {
    test('总数为 25', () {
      expect(PoseLibrary.all.length, 25);
    });

    test('id 唯一且非空（id 随 options.pose 发给后端，重复会串姿势）', () {
      final ids = PoseLibrary.all.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length, reason: '存在重复 id：${ids.toSet()} 数量对不上');
      for (final p in PoseLibrary.all) {
        expect(p.id.trim(), isNotEmpty, reason: '有空 id');
      }
    });

    test('code 唯一（K1~K11 / S1~S8 / L1~L6 的编号不能撞）', () {
      final codes = PoseLibrary.all.map((p) => p.code).toList();
      expect(codes.toSet().length, codes.length, reason: '存在重复编号：$codes');
    });

    test('每条都有中文标签与英文 prompt（缺一条该姿势就退化成无描述）', () {
      for (final p in PoseLibrary.all) {
        expect(p.name.trim(), isNotEmpty, reason: '${p.id} 缺中文名');
        expect(p.prompt.trim(), isNotEmpty, reason: '${p.id} 缺 prompt');
        // 英文 prompt 应含逗号分句，便于模型理解；这里只做宽松校验：
        // 全是中文说明写错了（实际是给模型看的英文描述）
        expect(RegExp(r'[a-zA-Z]').hasMatch(p.prompt),
            isTrue, reason: '${p.id} 的 prompt 不像英文描述：${p.prompt}');
      }
    });

    test('prompt 互不相同（两条姿势描述雷同= 白录入）', () {
      final prompts = PoseLibrary.all.map((p) => p.prompt).toSet();
      expect(prompts.length, PoseLibrary.all.length, reason: '有姿势 prompt 重复');
    });

    test('分组归属与数量：跪/坐11 / 坐8 / 躺6', () {
      expect(PoseLibrary.byGroup(PoseGroup.kneel).length, 11);
      expect(PoseLibrary.byGroup(PoseGroup.sit).length, 8);
      expect(PoseLibrary.byGroup(PoseGroup.lie).length, 6);
    });

    test('每个分组都有可展示的标签与提示文案', () {
      for (final g in PoseGroup.values) {
        expect(PoseLibrary.groupLabels[g]?.trim(), isNotEmpty, reason: '分组 $g 缺标签');
        expect(PoseLibrary.groupHints[g]?.trim(), isNotEmpty, reason: '分组 $g 缺提示');
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
