// 内置姿势库 —— 试衣间可自由挑选的拍摄姿势
//
// ── 数据规模 ────────────────────────────────────────────────
// 232 条姿势预设（205 个唯一姿势，其中 27 个同时属于两类，
// 例如既是坐姿又是跪姿，在两个分组里各出现一次共用同一个 id）：
//   S坐姿系 121 条 / K 跪姿系 59 条 / L 卧姿系 52 条
//
// ── 数据来源与命名 ──────────────────────────────────────────
// 姿势参考图来自 posemaniacs.com 的女性姿势库（三大类全收录）。
// ⚠️ 那个站点**只提供 poseId 与标签数量，既没有中文名也没有任何描述**，
// 所以中文名「坐 · 抱膝 · 侧望」和英文 prompt 都是**逐张看图**写出来的
// （共 205 张，人工看图归档），不是从标签自动生成的——自动生成只会
// 产出「坐姿 · 标签1 · 标签2」这种没有信息量的字符串。
//
// ── 已知的数据特征：分组按「源站分类」，不是按实际动作 ──────────
// 有 47/232 条（20%）的中文名首词与所在分组不一致，例如：
//   S-001 在「坐姿」组里但图是跪姿、 L-042 在「卧姿」组里但图是俯卧、
//   K-033 在「跪姿」组里但图是仰卧。
// 原因是 posemaniacs 的分类本身有交叉与遗漏，而我们**刻意不重新归类**：
//   · 重新归类会与源站对不上，以后想核对原图时找不到出处；
//   · 中文名是逐张看图写的，如实描述画面动作，改名会把它改成错的。
// 所以分组只作为**浏览入口**，实际动作以中文名为准。
// [PosePreset.nameLooksOffGroup] 就是给 UI 用的判据：命中时在详情里
// 显式说明「源站归在这一类，图中实际是XX」，避免用户以为是 bug。
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

  /// 中文名首词描述的动作与所在分组不一致（源站分类问题，见文件头说明）。
  /// 47/232 条为true：UI 应在详情里说明来源，而不是当成数据错误。
  bool get nameLooksOffGroup {
    final head = name.split('·').first;
    final kws = switch (group) {
      PoseGroup.sit => const ['坐', '蹲', '盘'],
      PoseGroup.kneel => const ['跪'],
      PoseGroup.lie => const ['卧', '躺'],
    };
    return !kws.any(head.contains);
  }
}

class PoseLibrary {
  PoseLibrary._();

  /// 全部姿势预设（232 条）
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

  /// 分组展示名（含条目数，232 条数据没有数量提示会很难找）
  static String groupLabelOf(PoseGroup g) => '${groupLabels[g]}· ${byGroup(g).length}';

  static const groupLabels = {
    PoseGroup.sit: '坐姿',
    PoseGroup.kneel: '跪姿',
    PoseGroup.lie: '卧姿',
  };

  static const groupHints = {
    PoseGroup.sit: '腿部线条与坐姿比例',
    PoseGroup.kneel: '背部与腰线的主场',
    PoseGroup.lie: '全身曲线的延伸感',
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