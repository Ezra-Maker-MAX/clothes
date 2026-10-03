// 内置姿势库 —— 试衣间可自由挑选的 25 种拍摄姿势（纯文本编码）
//
// ── 编码规则 ────────────────────────────────────────────────
// 25 个姿势按三大组编码，每组内连续编号（与用户参考图 1~25 一一对应）：
//   K 跪姿系（11 个）：K1~K11  → 参考图 1,2,4,8,9,11,14,15,16,19,22
//   S 坐姿系（ 8 个）：S1~S8   → 参考图 3,7,10,12,17,20,23,25
//   L 卧姿系（ 6 个）：L1~L6   → 参考图 5,6,13,18,21,24
// id 是发给后端的稳定标识（options.pose），name/desc 是界面文案，
// prompt 是并入生成请求的英文姿势描述（摄影棚工作语言，模型理解最稳）。
//
// ── 隐私设计（职业拍摄场景，用户敏感）─────────────────────────
// 1. 纯文本：App 内置字符串常量，不联网拉取、不内置任何图片，包体零增加；
// 2. 姿势描述只在点「生成」那一刻随请求发往用户自己配置的模型服务；
// 3. 选中状态只存在试衣页内存里，退出即消失——不写本地存储、不进历史、不上传；
// 4. 与自传姿势参考图（poseImage）互不冲突：都选了就一起发，双重参照。
enum PoseGroup { kneel, sit, lie }

/// 一个预设试衣姿势
class PosePreset {
  const PosePreset({
    required this.id,
    required this.code,
    required this.name,
    required this.desc,
    required this.prompt,
    required this.group,
  });

  final String id; // 稳定标识，随 options.pose 发给后端
  final String code; // 展示编码，如 K1 / S3 / L2
  final String name; // 中文短名（摄影棚工作语言）
  final String desc; // 一句话说明这条姿势看什么（版型/线条/层次）
  final String prompt; // 并入生成 prompt 的英文姿势描述
  final PoseGroup group;
}

class PoseLibrary {
  PoseLibrary._();

  /// 全部 25 个预设
  static const List<PosePreset> all = [
    // ════ 跪姿系 K（11 个）════
    PosePreset(
        id: 'kneel-side-glance', code: 'K1',
        name: '跪坐 · 侧身回望',
        desc: '上身侧转看镜头，展示肩线与腰线过渡',
        prompt: 'kneeling upright, torso twisted to one side looking back over the shoulder toward the camera, elegant posture',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-all-fours', code: 'K2',
        name: '跪撑 · 重心后坐',
        desc: '四点撑地重心后压，展示背部线条',
        prompt: 'on all fours on the ground, weight shifted back toward the heels, back arched naturally',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-forward-stretch', code: 'K3',
        name: '跪撑 · 双臂前伸',
        desc: '手臂前伸伏低，展示背部与侧腰线条',
        prompt: 'kneeling with both arms stretched forward on the ground, upper body lowered, elongated back line',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-all-fours-side', code: 'K4',
        name: '跪撑 · 侧望',
        desc: '四点支撑头部侧转，颈部线条拉长',
        prompt: 'on all fours, head turned to the side with a long neck line, relaxed shoulders',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-upright-lean', code: 'K5',
        name: '跪立 · 前倾撑地',
        desc: '直立跪姿上身穿心前倾，展示正面',
        prompt: 'kneeling upright, torso leaning slightly forward with hands resting on the ground between the knees, facing the camera',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-look-back', code: 'K6',
        name: '跪撑 · 回头',
        desc: '撑地回头看镜头，肩背与颈线同时展示',
        prompt: 'on all fours looking back over one shoulder at the camera, spine gently arched',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-upright-front', code: 'K7',
        name: '跪立 · 正面',
        desc: '最正的跪姿，正面看全身比例',
        prompt: 'kneeling upright facing the camera, back straight, hands resting naturally on thighs',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-forward-fold', code: 'K8',
        name: '跪姿 · 深度前屈',
        desc: '上身伏贴大腿，展示背部长线条',
        prompt: 'kneeling with the torso folded forward over the thighs, arms extended on the ground, deep forward fold',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-side-lean', code: 'K9',
        name: '跪坐 · 侧倾支撑',
        desc: '单手侧撑身体侧倾，腰线一侧拉长',
        prompt: 'kneeling while leaning to one side supported by one hand, the opposite arm relaxed, elongated side line',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-arch-down', code: 'K10',
        name: '跪撑 · 弓背低头',
        desc: '背部弓起头低下，展示背部弧线',
        prompt: 'kneeling with the back gently arched upward, head lowered toward the ground, curved spine visible',
        group: PoseGroup.kneel),
    PosePreset(
        id: 'kneel-side-stretch', code: 'K11',
        name: '跪姿 · 侧伸展',
        desc: '侧身单手撑地另一侧上举，纵向拉长',
        prompt: 'kneeling, leaning sideways supported by one hand, the other arm extended upward, full lateral stretch',
        group: PoseGroup.kneel),

    // ════ 坐姿系 S（8 个）════
    PosePreset(
        id: 'sit-cross-lean', code: 'S1',
        name: '盘坐 · 前倾',
        desc: '盘腿上身前倾撑地，展示肩背',
        prompt: 'sitting cross-legged on the ground, torso leaning forward with hands on the ground, relaxed shoulders',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-one-leg-out', code: 'S2',
        name: '侧坐 · 单腿外伸',
        desc: '一腿屈一腿伸，看腿部线条比例',
        prompt: 'sitting with one leg bent under and the other extended to the side, one hand resting on the ground',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-side-hug-knee', code: 'S3',
        name: '侧坐 · 抱膝',
        desc: '侧面坐姿抱住屈膝，收拢安静',
        prompt: 'sitting on the side with knees drawn up, arms gently hugging one knee, composed posture',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-cross-arm-up', code: 'S4',
        name: '盘坐 · 举臂过顶',
        desc: '单臂举过头顶伸展，纵向线条拉满',
        prompt: 'sitting cross-legged with one arm raised and bent over the head, elongated torso line',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-lean-back', code: 'S5',
        name: '坐地 · 后仰撑手',
        desc: '双手后撑上身后仰，展示正面',
        prompt: 'sitting on the ground leaning back supported by both hands behind, legs relaxed to one side',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-hug-knees', code: 'S6',
        name: '坐地 · 抱膝团身',
        desc: '正面抱膝收拢，版型堆叠细节可见',
        prompt: 'sitting on the ground hugging both knees to the chest, facing the camera',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-between-knees', code: 'S7',
        name: '坐地 · 前倾居中',
        desc: '屈膝开坐上身前倾居中，构图对称',
        prompt: 'sitting with knees bent and apart, torso leaning forward centered between the knees, hands on the ground',
        group: PoseGroup.sit),
    PosePreset(
        id: 'sit-cross-side-support', code: 'S8',
        name: '盘坐 · 侧撑',
        desc: '盘腿单手侧撑，重心放松',
        prompt: 'sitting cross-legged leaning slightly to one side supported by one hand, the other arm resting on the knee',
        group: PoseGroup.sit),

    // ════ 卧姿系 L（6 个）════
    PosePreset(
        id: 'lie-stomach-elbows', code: 'L1',
        name: '俯卧 · 撑肘',
        desc: '趴卧双肘撑起上身，小腿上翘',
        prompt: 'lying on the stomach propped up on the elbows, lower legs lifted and crossed in the air',
        group: PoseGroup.lie),
    PosePreset(
        id: 'lie-side-bent-knees', code: 'L2',
        name: '侧卧 · 屈腿',
        desc: '侧躺双腿一前一后屈起，头枕手臂',
        prompt: 'lying on one side with knees bent, one leg in front of the other, head resting on one arm',
        group: PoseGroup.lie),
    PosePreset(
        id: 'lie-back-knees-side', code: 'L3',
        name: '仰卧 · 屈腿侧望',
        desc: '躺卧屈膝头侧转，展示正面与腿部',
        prompt: 'lying on the back with knees bent and drawn to one side, head turned to the side',
        group: PoseGroup.lie),
    PosePreset(
        id: 'lie-back-legs-up', code: 'L4',
        name: '仰卧 · 抬腿交叉',
        desc: '双腿举起交叉，展示腿部线条',
        prompt: 'lying on the back with both legs raised and crossed at the ankles, relaxed arms',
        group: PoseGroup.lie),
    PosePreset(
        id: 'lie-side-head-propped', code: 'L5',
        name: '侧卧 · 撑头',
        desc: '经典侧卧撑头姿势，全身线条',
        prompt: 'lying on one side, head propped up on one hand, legs stacked and slightly bent, full body line visible',
        group: PoseGroup.lie),
    PosePreset(
        id: 'lie-back-twist', code: 'L6',
        name: '仰卧 · 扭身',
        desc: '躺姿下半身扭转，展示腰胯线条',
        prompt: 'lying on the back with the lower body twisted to one side, knees bent and stacked, opposite shoulder on the ground',
        group: PoseGroup.lie),
  ];

  static List<PosePreset> byGroup(PoseGroup g) =>
      all.where((p) => p.group == g).toList();

  static PosePreset? byId(String id) {
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static const groupLabels = {
    PoseGroup.kneel: 'K · 跪姿系',
    PoseGroup.sit: 'S · 坐姿系',
    PoseGroup.lie: 'L · 卧姿系',
  };

  static const groupHints = {
    PoseGroup.kneel: '背部与腰线的主场',
    PoseGroup.sit: '腿部线条与比例',
    PoseGroup.lie: '全身曲线的延伸感',
  };
}
