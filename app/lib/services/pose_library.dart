// 内置姿势库 —— 试衣间可自由挑选的拍摄姿势
//
// ── 数据规模 ────────────────────────────────────────────────
// 806 条姿势预设，覆盖 posemaniacs 女性库的**全部**内容。
// 分 19 组，一个姿势只属于一组（不再有跨组重复）。
//   站立 320 / 蹲姿 83 / 坐姿 68 / 跳跃 47 / 跪姿 36 / 漂浮 34 /
//   舞动 34 / 其他动态 29 / 坐椅 28 / 格斗 20 / 侧卧 20 / 躺卧 18 /
//   仰卧 18 / 倒立 16 / 运动 13 / 奔跑 9 / 悬挂 8 / 俯卧 4 / 倚靠 1
//
// ── 分组怎么来的 ────────────────────────────────────────────
// 源站有 56 个标签，但**不是同一个维度**，不能直接铺成 Tab：
//   · 体位类：standing 334 / sitting 121 / squatting 86 / kneeling 59 ...
//   · 动作特征类：raising-arm 283 / twisting-body 234 / twisting-neck 208 ...
//   · 风格类：sexy 153 / fighting 140 / dancing 131 ...
// 而且 806 条里有 161 条**一个体位标签都没有**（源站只标了动作，
// 比如「站立时抬手」只标了 raising-arm）。所以分组策略是：
//   · 体位标签做主分组，按细分优先的固定优先级命中即止
//     （保证一个姿势只落一个组，不会 Tab 里出现重复）
//   · 无体位标签的归入动态组（跳跃/舞动/格斗/奔跑/运动/倚靠/其他）
//   · 其余标签存进 PoseEntry.tags，供 App 内搜索筛选
// 详见 scripts/poses/07-taxonomy.py 顶部的实测数据。
//
// ⚠️ 19 个 Tab 塞不进一行横向 Tab，所以 UI 用「分组下拉 + 搜索」。
//
// ── 数据来源与命名 ──────────────────────────────────────────
// 姿势参考图来自 posemaniacs.com 的女性姿势库。
// ⚠️ 那个站点**只提供 poseId 与标签数量，既没有中文名也没有任何描述**，
// 所以中文名「坐 · 抱膝 · 侧望」和英文 prompt 都是**逐张看图**写出来的
// （共 806 张），不是从标签自动生成的——自动生成只会
// 产出「坐姿 · 标签1 · 标签2」这种没有信息量的字符串。
//
// ⚠️ 这些图是**解剖学人体肌肉模型**渲染图（透明皮肤、可见肌腱骨骼），
// 不是真人照片。当姿势参考没问题，但**直接发给生图模型会得到
// 「半透明肌肉人」**，所以「发送参考图」开关默认关闭，见 tryon_page。
//
// ── 图片存哪 ────────────────────────────────────────────────
// 参考图放在 Vercel **私密** Blob store 的 poses/ 目录下，
// 私有 blob 的 URL 匿名访问直接 403，所以 App 不能像衣橱图那样
// 直接 Image.network(url)，必须走 GET /api/pose-image 代理转发。
// 见 PoseImageUrl 构造。
//
// ── 隐私设计（职业拍摄场景，用户敏感）─────────────────────────
// 1.姿势**元数据**（id/编码/中文名/英文 prompt）是内置字符串常量，
//    不联网拉取，App 包体只增约 60KB；
// 2. 参考图**只在打开姿势库时**按需从 Vercel 拉取并缓存，
//    不预下载、不写本地存储；
// 3. 姿势描述只在点「生成」那一刻随请求发往用户自己配置的模型服务；
// 4. 选中状态只存在试衣页内存里，退出即消失——不写本地存储、不进历史；
// 5. 是否把参考图本身发给模型由用户当次勾选（默认关闭，见 tryon_page），
//    勾选时才随生成请求发出；
// 6. 与自传姿势参考图（poseImage）互不冲突：都选了就一起发，双重参照。
import 'api_client.dart';
import 'pose_library_data.g.dart';

export 'pose_library_data.g.dart' show PoseEntry, PoseGroup, kPoseEntries;

/// 一个预设试衣姿势（对生成数据的只读包装，便于附加派生信息）
class PosePreset {
  const PosePreset(this.entry);

  final PoseEntry entry;

  String get id => entry.id;
  String get code => entry.code;
  String get name => entry.name;
  String get desc => entry.desc;
  String get prompt => entry.prompt;
  PoseGroup get group => entry.group;
  String get imagePath => entry.imagePath;

  /// 供 UI 显示的姿势图URL（经 Vercel 代理，私有 blob 不能直连）
  Uri? get imageUri => poseImageUri(imagePath);

}

class PoseLibrary {
  PoseLibrary._();

  /// 全部姿势预设（806 条）
  static List<PosePreset> get all =>
      _all ??= kPoseEntries.map(PosePreset.new).toList(growable: false);
  static List<PosePreset>? _all;

  static List<PosePreset> byGroup(PoseGroup g) =>
      all.where((p) => p.group == g).toList(growable: false);

  static PosePreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 分组展示名（含条目数，806 条没有数量提示会很难找）
  static String groupLabelOf(PoseGroup g) => '${groupLabels[g]}· ${byGroup(g).length}';

  /// 分组展示顺序。不能直接用 PoseGroup.values：兜底组（其他动态）
  /// 必须排最后，否则 Tab 上会出现一个条目数个位的组夹在中间。
  static final List<PoseGroup> groupOrder = () {
    const tail = {PoseGroup.other};
    return [
      ...PoseGroup.values.where((g) => !tail.contains(g)),
      ...PoseGroup.values.where(tail.contains),
    ];
  }();

  /// 按中文名/描述/编号/英文 prompt 搜索。806 条靠翻找不现实。
  /// 同时搜英文 prompt 是为了「知道动作但记不住中文名」的情况。
  static List<PosePreset> search(String q) {
    final k = q.trim().toLowerCase();
    if (k.isEmpty) return const [];
    return all
        .where((p) =>
            p.name.toLowerCase().contains(k) ||
            p.desc.toLowerCase().contains(k) ||
            p.code.toLowerCase().contains(k) ||
            p.prompt.toLowerCase().contains(k))
        .toList(growable: false);
  }

  static const groupLabels = {
    PoseGroup.standing: '站立',
    PoseGroup.sitting: '坐姿',
    PoseGroup.squatting: '蹲姿',
    PoseGroup.kneeling: '跪姿',
    PoseGroup.lying: '躺卧',
    PoseGroup.onSide: '侧卧',
    PoseGroup.onBack: '仰卧',
    PoseGroup.onStomach: '俯卧',
    PoseGroup.sittingChair: '坐椅',
    PoseGroup.handStanding: '倒立',
    PoseGroup.hanging: '悬挂',
    PoseGroup.floating: '漂浮',
    PoseGroup.jump: '跳跃',
    PoseGroup.dance: '舞动',
    PoseGroup.fight: '格斗',
    PoseGroup.run: '奔跑',
    PoseGroup.sport: '运动',
    PoseGroup.lean: '倚靠',
    PoseGroup.other: '其他动态',
  };

  static const groupHints = {
    PoseGroup.standing: '站姿与行走，数量最多',
    PoseGroup.sitting: '坐地坐姿，日常与柔美',
    PoseGroup.squatting: '深蹲半蹲，腿部线条主场',
    PoseGroup.kneeling: '跪、跪坐，柔美且有故事感',
    PoseGroup.lying: '各类躺姿的总入口',
    PoseGroup.onSide: '侧躺、侧身卧姿的完整线条',
    PoseGroup.onBack: '正面仰躺，摊开身体',
    PoseGroup.onStomach: '趴卧，突出背部与腿部',
    PoseGroup.sittingChair: '坐椅子上的日常与职场感',
    PoseGroup.handStanding: '手撑倒立，力量感线条',
    PoseGroup.hanging: '吊挂、单腿挂起等悬空动作',
    PoseGroup.floating: '悬浮、跳跃后无重力的姿态',
    PoseGroup.jump: '腾空、跃起的一瞬',
    PoseGroup.dance: '舞蹈、伸展类流动动作',
    PoseGroup.fight: '拳击、格斗、力量对抗',
    PoseGroup.run: '跑动、行走中的动态',
    PoseGroup.sport: '各类球类与健身运动',
    PoseGroup.lean: '倚墙、倚靠支撑的放松姿态',
    PoseGroup.other: '有明确肢体动作但无固定体位',
  };
}

/// 构造姿势图 URL：指向自家Vercel 的取流代理。
///
/// 为什么必须走代理而不能直接用 blob URL：姿势图存在 access=private 的
/// store 里，私有对象的 URL 对匿名请求返回 403。所以
/// `{API_BASE_URL}/api/pose-image?pathname=poses/xxx.webp`。
///
/// 返回可空：baseUrl 配错时 Uri 解析失败，此时 UI 应显示占位图而不是崩。
Uri? poseImageUri(String pathname) {
  final base = Uri.tryParse(ApiClient.baseUrl);
  if (base == null) return null;
  return base.replace(
    path: '/api/pose-image',
    queryParameters: {'pathname': pathname},
  );
}