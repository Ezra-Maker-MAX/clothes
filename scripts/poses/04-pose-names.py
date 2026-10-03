#!/usr/bin/env python3
"""按逐张看图的结果，为 205 个姿势写中文名+ 英文 prompt，并生成 Dart 数据。

为什么不能靠标签自动生成：站点只给 tagCount（标签数量），**不给具体标签**，
也不给任何中文名/描述。所以只能看图说话。这份数据是逐张看过
/tmp/posedata/sheets/sheet_*.png（18 张拼图，每张 12 个）之后写的，
命名规则：
  中文名 = 分组前缀 + 落座/支撑方式 + 手部动作 + 腿部/视线特征
  英文prompt = "主体姿势, 关键细节" 摄影棚工作语言，模型理解最稳

分组以**站点分类**为准（sitting/kneeling/lying），不自己改——
它已经验证过和画面一致（比如 #018 明显是跪姿却被标 lying，那是站点归的 on-back 类）。

数据结构：
  code   展示编码，如 S-001 / K-001 / L-001，按组内序号
  id稳定标识 pm-<poseId>-<modelId>
  name   中文短名
  desc   一句话说明这条姿势看什么
  prompt 英文姿势描述
  group  所属组
  image  Blob 内pathname（poses/<poseId>_<modelId>.webp）
"""

# ── 逐张看图写的命名表：idx → (name, desc, prompt) ──
# idx 与 sheet_index.json 的 idx 一一对应（同一poseId/modelId）
P = {}


def add(idx, name, desc, prompt):
    P[idx] = (name, desc, prompt)


# ════ sheet_00 ════
add(0, '跪坐 · 侧身回眸', '跪姿上身侧转看向镜头，肩线与腰线过渡清晰', 'kneeling upright with the torso twisted to one side, looking back over the shoulder toward the camera')
add(1, '跪坐 · 双手交叠', '跪姿双手在胸前交叠，正面看手臂线条', 'kneeling upright facing the camera, both hands folded together in front of the chest')
add(2, '跪姿 · 双臂过顶', '跪姿双臂上举抱头，腋下与侧腰拉伸', 'kneeling with both arms raised above the head, hands resting behind the head, side waist stretched')
add(3, '跪姿 · 侧倾蜷腿', '侧卧式蜷膝跪姿，身体形成S 形曲线', 'kneeling curled to one side with the legs drawn in, body forming a curved S shape')
add(4, '跪姿 · 手托头侧', '跪姿单手扶头，另一手撑地，颈部线条拉长', 'kneeling with one hand resting behind the head and the other hand on the ground, long neck line')
add(5, '半跪 · 前伸手掌', '单膝跪地双手前伸如捧物，背部线条拉长', 'half kneeling on one knee, both arms extended forward with open palms, elongated back line')
add(6, '跪撑 · 仰头撑地', '双手撑地上身仰起，下巴上抬，颈部线条', 'kneeling with both hands on the ground, upper body leaning back and chin lifted, neck line visible')
add(7, '跪姿 · 单臂上举', '跪姿一臂高举过头顶，另一臂收于腹前，纵向伸展', 'kneeling with one arm raised straight overhead, the other arm resting in front of the torso')
add(8, '跪坐 · 侧分腿举臂', '跪坐双腿侧向打开，一臂上举一手撑地', 'kneeling with the legs opened out to the side, one arm raised and the other hand on the ground')
add(9, '跪姿 · 侧身回首', '跪姿侧身，头转向肩后，颈部与肩胛联动', 'kneeling with the body turned sideways and the head looking back over the shoulder')
add(10, '跪姿 · 手扶髋侧', '跪姿单手叉腰，另一手垂放，正面看胯线', 'kneeling facing the camera with one hand resting on the hip')
add(11, '跪姿 · 深度前屈', '上身伏贴大腿，双臂下垂，脊柱完全弯曲', 'kneeling with the torso folded deeply over the thighs, arms hanging down, spine fully curved')

# ════ sheet_01 ════
add(12, '跪坐 · 俯身触地', '跪坐前俯双手撑地，展示背部与臀部曲线', 'kneeling and folding forward with both hands touching the ground, back and hip line visible')
add(13, '跪姿 · 手臂上举后仰', '跪姿一臂上举，上身后仰，胸腹拉伸', 'kneeling with one arm raised and the upper body leaning back, chest and abdomen stretched')
add(14, '半跪 · 单臂高举', '半跪一腿跪一腿立，高举手臂，肩背线条', 'half kneeling with one leg raised on the knee, one arm lifted high, shoulder and back line visible')
add(15, '半跪 · 双手前推', '半跪双手向前推出，像推开一扇门，胸部打开', 'half kneeling with both hands pushed forward as if pressing a door open, chest expanded')
add(16, '跪姿 · 侧弯腰抬手', '跪姿侧向弯腰，一臂上举侧屈，腰侧拉伸', 'kneeling with the body bent sideways and one arm raised overhead, lateral waist stretch')
add(17, '跪撑 · 正面四点', '四点跪撑正面看，一手前伸，重心偏一侧', 'kneeling on all fours facing the camera, one hand extended forward, weight shifted to one side')
add(18, '跪姿 · 双臂前伸', '跪姿双臂平行前伸，肩背平展', 'kneeling with both arms extended forward parallel, shoulders and back flat')
add(19, '跪姿 · 单膝点地扶头', '单膝跪地一腿立起，双手上举扶后脑，肘部张开', 'kneeling on one knee with the other leg raised upright, both hands behind the head, elbows opened out wide')
add(20, '跪姿 · 侧屈伸展', '跪姿单手撑地身体侧屈，另一臂上举成拱形', 'kneeling leaning sideways supported by one hand, the other arm raised overhead forming an arch')
add(21, '半跪 · 前倾下压', '半跪重心前压，一手撑地一手扶膝', 'half kneeling with the weight pressed forward, one hand on the ground and the other on the knee')
add(22, '跪姿 · 盘腿正中', '跪坐双腿盘于身前，双手交握置于腹前', 'kneeling with both legs folded in front, hands clasped together resting at the abdomen')
add(23, '跪坐 · 侧伸单腿', '跪坐一腿侧向伸直，一手撑地，重心偏斜', 'kneeling with one leg extended out to the side, one hand supporting on the ground')

# ════ sheet_02 ════
add(24, '跪姿 · 手舞足臂', '跪姿双臂大幅张开如展翅，动态感强', 'kneeling with both arms opened wide to the sides, dynamic open gesture')
add(25, '跪姿 · 侧身抚头', '跪姿身体侧转，一手抬至头顶，颈部拉长', 'kneeling with the torso turned to the side and one hand raised to the head, neck lengthened')
add(26, '跪姿 · 举臂侧展', '跪姿一臂高举向侧上方展开，腋下打开', 'kneeling with one arm raised high and opened to the side, underarm exposed')
add(27, '跪姿 · 俯身侧撑', '跪姿俯身一臂撑地，另一手撑髋，背部展开', 'kneeling and leaning forward, one hand on the ground and the other on the hip, back extended')
add(28, '半跪 · 持剑侧身', '半跪单手持剑斜指，戏剧化侧身构图', 'half kneeling holding a sword pointing to the side, dramatic turned composition')
add(29, '半跪 · 张臂侧倾', '半跪双臂张开身体侧倾，肩线打开', 'half kneeling with both arms opened out and the body leaning to one side, shoulders open')
add(30, '跪姿 · 俯首垂臂', '跪姿低头俯身，一手垂放一手撑地，颈背弯曲', 'kneeling with the head bowed forward, one arm hanging down and the other supporting on the ground')
add(31, '跪姿 · 双臂上扬', '跪姿双臂上扬打开，掌心向上，胸腔打开', 'kneeling with both arms raised and opened, palms facing up, chest lifted')
add(32, '仰卧 · 抬腿屈膝', '仰卧双腿屈起交叉，小腿垂直，腹部收紧', 'lying on the back with both knees raised and crossed, lower legs vertical, core engaged')
add(33, '跪坐 · 侧身落地', '跪坐身体侧倒向地面，侧腰贴地', 'kneeling and falling to one side, waist lowered toward the ground')
add(34, '跪姿 · 手托腮侧', '跪姿一手托腮一手撑地，头部侧倚，颈部线条', 'kneeling with one hand cupping the cheek and the other on the ground, head tilted')
add(35, '坐地 · 前伸推掌', '坐地双腿斜伸，一手前伸推掌向镜头，重心偏前', 'sitting on the ground with legs extended diagonally, one palm pushed forward toward the camera, weight shifted forward')

# ════ sheet_03 ════
add(36, '跪姿 · 单膝点地', '单膝跪地一腿立，一手扶大腿，重心偏前', 'kneeling on one knee with the other leg raised, one hand resting on the thigh')
add(37, '半跪 · 横剑胸前', '半跪双手横持剑于胸前，正面构图', 'half kneeling holding a sword horizontally across the chest, front facing composition')
add(38, '半跪 · 屈臂前推', '半跪双肘弯曲前推，肱二头肌收紧', 'half kneeling with both arms bent and pushed forward, biceps engaged')
add(39, '跪坐 · 侧展单臂', '跪坐一腿屈一腿撑地，一臂上举侧展', 'kneeling with one leg bent and the other braced, one arm raised to the side')
add(40, '跪姿 · 双手过顶', '跪姿双臂上举互相交叠，腋下完全打开', 'kneeling with both arms raised above the head, arms crossed, underarms fully open')
add(41, '俯卧 · 单腿高抬', '俯卧上身贴地，单腿垂直高抬，臀部翘起', 'lying prone with the upper body flat and one leg lifted high in the air, hips raised')
add(42, '俯卧 · 交替抬腿', '俯卧双腿交替弯曲上抬，动态', 'lying prone with both legs bent and lifted alternately, dynamic movement')
add(43, '半跪 · 指向前方', '半跪一臂前伸指向远处，身体侧向', 'half kneeling with one arm extended pointing forward, body turned to the side')
add(44, '俯卧 · 侧撑上身', '俯卧一侧手臂撑起上身，另一臂伸直，扭转', 'lying prone propped on one arm with the other extended, torso twisted')
add(45, '仰卧 · 屈膝搭腿', '仰卧屈膝双手搭住膝部，腰部离地', 'lying on the back with knees bent and hands resting on them, lower back lifted')
add(46, '仰卧 · 单腿斜举', '仰卧双腿一屈一伸，伸展腿高举，腹肌发力', 'lying on the back with one leg bent and the other extended upward, core engaged')
add(47, '仰卧 · 屈膝脚踝交叠', '仰卧屈膝双腿交叠成菱形，腹部收紧', 'lying on the back with knees bent and ankles crossed, forming a diamond shape')

# ════ sheet_04 ════
add(48, '仰卧 · 平伸全身', '仰卧双臂双腿平伸舒展，最放松的躺姿', 'lying flat on the back with arms and legs fully extended, relaxed')
add(49, '仰卧 · 俯身弓背', '仰卧上半身离地弓起，双臂前伸，下背贴地', 'lying on the back with the upper body lifted and arched, arms reaching forward')
add(50, '俯卧 · 屈膝脚上提', '俯卧屈膝双腿上提交叠，臀部抬高', 'lying prone with knees bent and feet lifted up crossed, hips raised')
add(51, '侧卧 · 屈腿叠放', '侧卧双腿屈起交叠，双臂前伸，肩线放松', 'lying on one side with knees bent and stacked, arms extended forward')
add(52, '俯卧 · 展体伸直', '俯卧全身伸展，手臂前伸，腿脚并拢', 'lying prone fully extended, arms forward, legs together')
add(53, '侧卧 · 上身撑起', '侧卧一臂撑起上身，双腿屈起，上体离地', 'lying on one side propped up on one arm, knees bent, upper body lifted')
add(54, '仰卧 · 抱头屈腿', '仰卧双手抱头，双腿屈起并拢，腹部收紧', 'lying on the back with hands behind the head and both knees drawn up')
add(55, '侧卧 · 双腿叠伸', '侧卧双腿叠放伸直，一臂枕于头下', 'lying on one side with legs stacked and extended, one arm under the head')
add(56, '半卧 · 侧肘撑起', '侧卧以肘撑起上身，髋部着地，腿部斜伸', 'lying on the side propped up on the elbow, hips on the ground, legs extended diagonally')
add(57, '俯卧 · 屈膝侧摆', '俯卧双腿屈膝向一侧摆动，扭转腰部', 'lying prone with both knees bent and swung to one side, waist twisted')
add(58, '仰卧 · 高抬双腿', '仰卧双腿高举成V 字，双手撑地，腹部核心发力', 'lying on the back with both legs raised high in a V shape, hands pressing the ground, core engaged')
add(59, '仰卧 · 屈膝脚跟并拢', '仰卧屈膝双脚并拢外展，膝部开立', 'lying on the back with knees bent and feet together, knees opened out to the sides')

# ════ sheet_05 ════
add(60, '俯卧 · 抬胸撑肘', '俯卧双肘撑起上身，双腿微抬，胸部打开', 'lying prone propped up on the elbows with the chest lifted, legs slightly raised')
add(61, '仰卧 · 抱腿蜷缩', '仰卧双手抱住双腿，蜷成一团', 'lying on the back hugging both legs toward the chest, curled up')
add(62, '仰卧 · 屈膝侧倒', '仰卧屈膝双腿向一侧倒，头转向反方向', 'lying on the back with knees bent and fallen to one side, head turned the other way')
add(63, '仰卧 · 抬腿抓脚', '仰卧双腿上举，双手抓住脚踝，小腿垂直', 'lying on the back with legs raised, hands holding the ankles, lower legs vertical')
add(64, '侧卧 · 屈腿撑肘', '侧卧一肘撑地，上腿屈起跨在下腿前', 'lying on one side propped on the elbow, top leg bent over the bottom leg')
add(65, '俯卧 · 顶髋举腿', '俯卧双手撑地髋部高举，双腿垂直上举倒立感', 'lying prone with hands on the ground and hips raised high, both legs lifted vertically')
add(66, '俯卧 · 侧展单腿', '俯卧上身贴地，一腿侧向抬起，扭转', 'lying prone with the upper body flat and one leg lifted out to the side, twisted')
add(67, '侧卧 · 上身撑起侧视', '侧卧一臂撑起，髋部离地，双腿叠放', 'lying on one side with one arm supporting, hips lifted off the ground, legs stacked')
add(68, '侧卧 · 平伸叠腿', '侧卧双腿叠放平伸，一手枕于头下', 'lying on the side with both legs extended and stacked, one arm under the head')
add(69, '仰卧 · 抬腿屈膝夹', '仰卧一腿竖直上举，另一腿屈起，髋部扭转', 'lying on the back with one leg raised vertically and the other bent, hips twisted')
add(70, '半蹲 · 单腿立抱腿', '半蹲一腿立起一腿屈，双臂环抱屈膝，上身前倾', 'half squatting with one leg raised and one bent, arms wrapped around the bent knee, torso leaning forward')
add(71, '俯卧 · 上身侧撑', '俯卧一臂撑起头部，另一臂前伸，颈部侧屈', 'lying prone propped on one arm with the head resting on it, the other arm extended')

# ════ sheet_06 ════
add(72, '站立 · 前倾单臂后展', '站立前倾一腿支撑，另一臂后展，背线拉长', 'standing leaning forward supported on one leg, the other arm extended back, back line stretched')
add(73, '俯卧 · 一腿高抬', '俯卧贴地一腿向后上方高抬，臀部翘起', 'lying prone flat with one leg lifted high behind, hips raised')
add(74, '仰卧 · 屈膝双脚踩地', '仰卧屈膝双脚踩地，膝盖大幅外开成菱形', 'lying on the back with knees bent and both feet planted, knees opened wide into a diamond shape')
add(75, '仰卧 · 倒立举腿', '仰卧臀部落地位支撑，双腿竖直向上，肩背受力', 'lying on the back with the hips lifted and both legs straight up, shoulders bearing weight')
add(76, '侧卧 · 蜷曲抱枕', '侧卧蜷成一团，双膝抱向胸前，安静收拢', 'lying on one side curled up, knees drawn to the chest, composed')
add(77, '仰卧 · 屈膝斜伸', '仰卧一腿屈起一腿斜伸，腿成直角', 'lying on the back with one knee bent and the other leg extended diagonally at a right angle')
add(78, '仰卧 · 平伸展体', '仰卧全身平展，四肢略微张开', 'lying flat on the back fully extended, limbs slightly spread')
add(79, '仰卧 · 抬腿屈膝搭', '仰卧一腿抬起另一腿屈膝交叠，脚踝搭放', 'lying on the back with one leg raised and the other bent and crossed, ankles resting together')
add(80, '侧卧 · 平伸叠腿俯视', '侧卧俯视角度，双腿叠放伸直，臀线清晰', 'lying on one side viewed from above, legs stacked and extended, hip line visible')
add(81, '俯卧 · 全展平伸', '俯卧平伸，头侧向一边，双臂自然展开', 'lying prone fully extended, head turned to one side, arms relaxed')
add(82, '侧卧 · 屈叠双腿', '侧卧双腿屈起叠放，脚踝相搭', 'lying on one side with both legs bent and stacked, ankles resting together')
add(83, '侧卧 · 屈膝叠腿侧躺', '侧卧双膝屈起叠放，上身侧躺贴地，颈部放松', 'lying on one side with both knees bent and stacked, torso resting on the ground, neck relaxed')

# ════ sheet_07 ════
add(84, '跪姿 · 单手撑地侧臂', '跪姿单手撑地，另一臂上举侧展，腋下打开', 'kneeling supported on one hand with the other arm raised to the side, underarm open')
add(85, '坐地 · 屈腿抱膝', '坐地双膝屈起，一手抱膝一手撑地', 'sitting on the ground with knees bent, one arm hugging the knee and the other hand supporting')
add(86, '跪姿 · 双臂后展', '跪姿上身直立双臂向后展开，肩胛收紧', 'kneeling upright with both arms extended behind, shoulder blades engaged')
add(87, '跪坐 · 抱腿侧身', '跪坐身体侧转，双臂环抱屈起的腿', 'kneeling with the body turned to one side, arms wrapped around the bent leg')
add(88, '坐地 · 抱膝正面', '坐地双膝抱起，双臂环抱，正面收拢', 'sitting on the ground hugging both knees to the chest, front facing and compact')
add(89, '跪坐 · 单手撑地', '跪坐一腿立一腿屈，手撑地，另一手扶膝', 'kneeling with one leg raised and one bent, one hand on the ground and the other on the knee')
add(90, '坐地 · 盘腿单手举', '盘腿坐地一手举至面前，另一手扶脚踝', 'sitting cross-legged on the ground with one hand raised in front, the other resting on the ankle')
add(91, '坐地 · 盘腿远伸', '盘腿坐地双腿向远端伸直，上身后倾双手后撑', 'sitting with legs extended forward and the torso leaning back on both hands')
add(92, '俯卧 · 屈膝小腿交叠', '俯卧屈膝双腿小腿交叠上抬，脚背相对', 'lying prone with knees bent and lower legs crossed up, feet facing each other')
add(93, '坐地 · 屈膝分腿撑', '坐地双膝屈起分开，双手撑地于身后', 'sitting on the ground with knees bent and apart, both hands supporting behind')
add(94, '坐地 · 斜伸双腿', '坐地双腿斜向伸直，一手撑地侧身', 'sitting on the ground with legs extended diagonally, one hand supporting to the side')
add(95, '坐地 · 侧撑伸展', '坐地双腿侧向伸直，一臂侧撑上身', 'sitting on the ground with legs extended to the side, one arm supporting the torso')

# ════ sheet_08 ════
add(96, '坐地 · 屈膝侧撑', '坐地双膝屈起，一臂侧后撑地，头部侧倚', 'sitting on the ground with knees bent, one arm supporting behind, head tilted')
add(97, '盘坐 · 正面端坐', '盘腿坐地双手扶膝，正面最端正的坐姿', 'sitting cross-legged facing the camera with both hands resting on the knees')
add(98, '坐地 · 屈膝侧靠', '坐地屈膝身体侧倚一手撑地，颈部放松', 'sitting on the ground with knees bent, leaning to one side with one hand supporting')
add(99, '坐地 · 屈腿单手后撑', '坐地一腿屈起一腿半伸，一手后撑', 'sitting on the ground with one leg bent and one half extended, one hand supporting behind')
add(100, '跪坐 · 手掌撑地', '跪坐双手撑地于身前，上身微前倾', 'kneeling with both hands on the ground in front, torso leaning slightly forward')
add(101, '坐地 · 抱膝侧坐', '坐地双膝屈起侧向交叠，双臂环抱', 'sitting on the ground with knees drawn up and crossed to one side, arms wrapped around')
add(102, '坐姿 · 高位伸展', '坐姿双腿斜伸，双臂高举过头顶大幅伸展', 'sitting with legs extended diagonally, both arms raised high overhead in a full stretch')
add(103, '半跪 · 屈膝侧坐', '半跪一腿跪一腿屈立，肘撑大腿上身扭转', 'half kneeling with one leg raised and one bent, elbow on the thigh, torso twisted')
add(104, '坐姿 · 侧倾撑地', '坐姿侧倾一腿屈一腿伸，单手撑地', 'sitting leaning to one side with one leg bent and one extended, one hand on the ground')
add(105, '坐姿 · 手指轻抚', '坐姿一手扶地一手轻触面部，颈部微侧', 'sitting with one hand on the ground and the other touching the face, neck slightly turned')
add(106, '半跪 · 交叉抬膝', '半跪一腿高抬膝盖，两臂在膝上交错', 'half kneeling with one knee raised high, both arms crossed resting on it')
add(107, '站立 · 侧展单臂', '站立一腿立一腿侧点地，一臂上举侧展', 'standing on one leg with the other extended to the side, one arm raised')

# ════ sheet_09 ════
add(108, '坐地 · 斜伸抚腿', '坐地双腿斜伸，一手轻抚小腿，头部微倾', 'sitting on the ground with legs extended diagonally, one hand stroking the shin, head slightly tilted')
add(109, '盘坐 · 侧弯伸展', '盘坐一臂上举侧屈，另一手撑地，肋间拉开', 'sitting cross-legged with one arm raised and the body bent sideways, other hand on the ground')
add(110, '盘坐 · 双手交握', '盘腿坐地双手在腹前交握成环，正面构图', 'sitting cross-legged with both hands clasped together in front of the abdomen')
add(111, '坐地 · 手托头侧坐', '坐地一腿屈一腿伸，手托头部侧倚', 'sitting on the ground with one leg bent and one extended, hand cupping the tilted head')
add(112, '坐地 · 侧撑远望', '坐地双腿斜伸，一手撑地另一手举起，视线远望', 'sitting on the ground with legs extended, one hand supporting and the other raised, gazing into the distance')
add(113, '坐地 · 后撑举臂', '坐地双腿伸直，双手后撑，一臂上举', 'sitting on the ground with legs extended, both hands behind supporting, one arm raised')
add(114, '坐地 · 屈膝俯身', '坐地屈膝上身俯向双腿，双手触地或小腿', 'sitting on the ground with knees bent, torso folded forward over the legs')
add(115, '盘坐 · 手抚颈部', '盘腿坐地一手抚颈侧，一手扶脚踝，颈部伸展', 'sitting cross-legged with one hand touching the side of the neck, the other on the ankle')
add(116, '坐地 · 屈腿侧身', '坐地屈膝侧身，一臂后撑，颈部拉长', 'sitting on the ground with knees bent and body turned sideways, one arm supporting behind')
add(117, '坐地 · 抱膝低头', '坐地抱住双膝低头，下巴抵膝，安静内收', 'sitting on the ground hugging both knees with the head bowed down, quiet and inward')
add(118, '坐地 · 团身埋首', '坐地团成一团双手埋于膝间，完全内收', 'sitting on the ground curled up with the head buried between the knees, fully contracted')
add(119, '盘坐 · 单臂前伸', '盘坐一臂向侧前方伸出，另一手撑地，身体侧转', 'sitting cross-legged with one arm extended forward to the side, the other hand on the ground, torso turned')

# ════ sheet_10 ════
add(120, '跪姿 · 侧身垂手', '跪姿侧身双臂垂放，背线垂直', 'kneeling with the body turned sideways and both arms hanging down, back line vertical')
add(121, '盘坐 · 侧撑远伸', '盘坐双腿斜伸，一手撑地侧身，颈部拉长', 'sitting cross-legged with legs extended diagonally, one hand supporting, neck lengthened')
add(122, '坐地 · 屈膝环抱小腿', '坐地双膝屈起贴近胸前，双臂环抱小腿，上身低伏', 'sitting on the ground with both knees drawn up close to the chest, arms wrapped around the shins, torso lowered')
add(123, '盘坐 · 抱膝侧倾', '盘坐抱住双膝身体侧倾，脚掌相对', 'sitting cross-legged hugging both knees, body leaning to one side, feet facing each other')
add(124, '跪姿 · 侧坐举臂', '跪姿侧坐双腿侧屈，一臂上举一手撑地', 'kneeling seated to the side with legs bent, one arm raised and one hand on the ground')
add(125, '跪姿 · 双臂屈举', '跪姿双肘弯曲双手举起如持物，肩背打开', 'kneeling with both elbows bent and hands raised as if holding something, shoulders open')
add(126, '坐姿 · 侧身单臂高展', '坐姿一臂高举向侧上方，腿部侧向延伸', 'sitting with one arm raised high to the side and legs extended laterally')
add(127, '坐地 · 低侧倾撑', '坐地双腿并拢斜伸，上身低伏侧倾单手撑地', 'sitting low on the ground with both legs extended together, torso leaning heavily to the side supported on one hand')
add(128, '跪坐 · 仰头双手扶头', '双膝跪坐仰头，双手置于头后，颈部充分伸展', 'kneeling on both knees with the head tilted back, both hands behind the head, neck fully extended')
add(129, '坐地 · 屈膝抱头', '坐地屈膝一手抱头一手扶踝，颈部侧屈', 'sitting on the ground with knees bent, one hand holding the head and the other on the ankle')
add(130, '坐地 · 屈腿单手撑', '坐地屈膝单手侧撑，另一手扶地，上身扭转', 'sitting on the ground with knees bent, one hand supporting and the other on the ground, torso twisted')
add(131, '跪姿 · 俯首触地', '跪姿上身完全前俯，双手触地，脊柱弯曲', 'kneeling with the torso folded fully forward, both hands touching the ground, spine curved')

# ════ sheet_11 ════
add(132, '盘坐 · 单手扶额', '盘坐一腿屈一腿伸，一手扶额，颈部侧倾', 'sitting cross-legged with one leg bent and one extended, one hand at the forehead, neck tilted')
add(133, '跪坐 · 交叉前臂', '跪坐双臂交叉抱于胸前，正面收拢', 'kneeling with both arms crossed in front of the chest, compact front pose')
add(134, '跪坐 · 抱头俯身', '跪坐双手抱头，上身前俯，肩背隆起', 'kneeling with both hands behind the head, torso folded forward, shoulders rounded')
add(135, '坐地 · 屈腿手扶头', '坐地屈膝侧坐，一手扶头，颈部倾斜', 'sitting on the ground with knees bent to one side, one hand supporting the head, neck tilted')
add(136, '站姿 · 交叉腿立', '站立双腿交叉，重心偏一侧，颈部歪头', 'standing with legs crossed, weight shifted to one side, head tilted')
add(137, '坐姿 · 俯身垂首', '坐姿屈膝上身深俯，头部低垂，双手垂放', 'sitting with knees bent, torso folded deeply forward, head hanging down, arms relaxed')
add(138, '蹲姿 · 前倾扶膝', '深蹲双脚踩地，双手扶膝，上身前倾', 'squatting with both feet planted, hands resting on the knees, torso leaning forward')
add(139, '坐姿 · 单腿叠踩', '坐姿一腿屈一腿直，单腿脚踩在另一腿上', 'sitting with one leg bent and one straight, the foot of one resting on the other thigh')
add(140, '坐地 · 屈腿侧倚', '坐地屈膝侧倚，一手轻触太阳穴', 'sitting on the ground with knees bent, leaning to one side, one hand at the temple')
add(141, '单腿立 · 抬膝平衡', '单腿站立另一腿抬起，双手扶膝保持平衡', 'standing on one leg with the other lifted, both hands on the knee for balance')
add(142, '跪姿 · 团身前俯', '跪姿全身团起双手撑地，头部低垂', 'kneeling curled forward with both hands on the ground and the head lowered')
add(143, '半跪 · 转身回望', '半跪身体扭转向后回望，一手撑地', 'half kneeling with the body twisted to look back, one hand on the ground')

# ════ sheet_12 ════
add(144, '坐姿 · 侧坐扶膝', '坐姿侧坐一手扶膝，颈部微倾', 'sitting to the side with one hand resting on the knee, neck slightly tilted')
add(145, '坐姿 · 翘腿前伸', '坐姿双腿叠放小腿交叉前伸，正面', 'sitting with legs crossed and lower legs extended forward, front facing')
add(146, '跪姿 · 弓背低头', '跪姿背部弓起头低下，脊柱明显弯曲', 'kneeling with the back arched and the head lowered, spine clearly curved')
add(147, '坐姿 · 侧撑翘腿', '坐姿一腿翘起一手撑地，身体扭转', 'sitting with one leg raised and one hand on the ground, torso twisted')
add(148, '盘坐 · 正面端坐开腿', '盘腿坐地双膝大幅打开，双手置于腿间', 'sitting cross-legged with knees opened wide, both hands resting between the legs')
add(149, '坐姿 · 抬腿悬空', '坐姿一腿屈起悬空，另一手侧撑，动态', 'sitting with one leg bent and lifted in the air, the other hand supporting, dynamic')
add(150, '坐地 · 双掌后撑', '坐地双腿斜伸，双掌撑地于身后，胸部打开', 'sitting on the ground with legs extended diagonally, both palms supporting behind, chest open')
add(151, '坐姿 · 侧抚膝', '坐姿屈膝一手抚膝，侧身线条', 'sitting with knees bent and one hand resting on the knee, side line visible')
add(152, '坐姿 · 手掌前伸', '坐姿一腿屈一腿伸，一手向前伸出，动态', 'sitting with one leg bent and one extended, one hand reaching forward, dynamic')
add(153, '坐地 · 团身抱膝俯首', '坐地团身抱住双膝俯首，下巴抵膝，背部隆起', 'sitting on the ground curled up hugging both knees with the head bowed, chin on the knees, back rounded')
add(154, '坐地 · 抱臂侧身', '坐地双腿斜伸，双臂抱于胸前侧身', 'sitting on the ground with legs extended diagonally, arms folded across the chest, turned to the side')
add(155, '盘坐 · 双手扶踝', '盘腿坐地双手扶住脚踝，上身微微后倾', 'sitting cross-legged with both hands holding the ankles, torso leaning slightly back')

# ════ sheet_13 ════
add(156, '坐姿 · 深蹲坐凳', '坐姿如坐凳，双膝深屈脚掌着地，双臂前伸', 'sitting as if on a stool, knees deeply bent with feet planted, arms reaching forward')
add(157, '坐姿 · 抚额侧坐', '坐姿屈膝一手扶额，肘部张开，颈部侧倾', 'sitting with knees bent and one hand at the forehead, elbow open, neck tilted')
add(158, '坐姿 · 俯身托腮', '坐姿俯身一手托腮，肘撑大腿，颈部侧屈', 'sitting leaning forward with one hand cupping the cheek, elbow on the thigh, neck bent')
add(159, '坐姿 · 侧坐翘腿', '坐姿侧坐双腿交叠，双手扶膝，颈部侧倾', 'sitting to the side with legs crossed, both hands on the knees, neck tilted')
add(160, '坐姿 · 抱膝侧转', '坐姿抱膝身体侧转，腿部交叠', 'sitting hugging the knees with the body turned sideways, legs crossed')
add(161, '坐地 · 单掌撑地', '坐地一腿屈一腿伸，一掌撑地，头部低垂', 'sitting on the ground with one leg bent and one extended, one palm on the ground, head lowered')
add(162, '坐地 · 侧撑躺卧', '坐地近乎侧躺，一手撑地，腿部斜伸', 'sitting on the ground almost lying on the side, one hand supporting, legs extended diagonally')
add(163, '坐姿 · 撑地侧身', '坐姿一腿屈一腿伸，一臂侧撑，身体扭转', 'sitting with one leg bent and one extended, one arm supporting to the side, torso twisted')
add(164, '坐姿 · 屈肘侧撑', '坐姿屈膝一肘撑膝，另一手叉腰，颈部侧倾', 'sitting with knees bent, one elbow on the knee and the other hand on the hip, neck tilted')
add(165, '坐姿 · 正面端坐翘腿', '坐姿正面双腿叠放，双手置于膝上，最端正', 'sitting facing the camera with legs crossed, both hands on the knees, most upright')
add(166, '半跪 · 屈臂侧坐', '半跪一腿跪一腿屈立，一臂屈起，颈部侧转', 'half kneeling with one leg raised and one bent, one arm bent, head turned')
add(167, '坐姿 · 侧坐抬手', '坐姿侧坐双腿交叠，一手举起，动态', 'sitting to the side with legs crossed, one hand raised, dynamic')

# ════ sheet_14 ════
add(168, '坐地 · 侧撑远伸', '坐地双腿斜向伸直，一手撑地，颈部拉长', 'sitting on the ground with legs extended diagonally, one hand supporting, neck lengthened')
add(169, '半跪 · 起身侧望', '半跪身体上升过程中侧头，动态', 'half kneeling rising upward with the head turned to the side, dynamic movement')
add(170, '坐姿 · 交叉叠腿', '坐姿双腿大腿交叉叠放，双手扶膝', 'sitting with legs crossed at the thigh, both hands resting on the knees')
add(171, '坐姿 · 坐姿交叠', '坐姿双腿交叠，双臂垂放两侧，正面', 'sitting with legs crossed and both arms hanging at the sides, front facing')
add(172, '坐姿 · 前倾俯首', '坐姿双腿并拢前倾，低垂头部', 'sitting with legs together, leaning forward with the head lowered')
add(173, '坐地 · 侧撑斜伸', '坐地双腿斜伸，一手侧撑，头部侧倚', 'sitting on the ground with legs extended diagonally, one hand supporting, head tilted')
add(174, '深蹲 · 俯身撑膝', '深蹲双脚踩地，俯身双手扶膝，正面', 'squatting with both feet planted, leaning forward with hands on the knees, front facing')
add(175, '坐地 · 正面侧倚', '坐地双腿并拢斜伸，双手置于腿侧，颈部微侧', 'sitting on the ground with legs together and extended diagonally, hands at the sides, neck slightly turned')
add(176, '跪姿 · 四点跪撑', '四点跪撑双手双膝着地，头部低垂', 'kneeling on all fours with both hands and knees on the ground, head lowered')
add(177, '跪姿 · 单掌前推', '跪姿一掌向前推出，另一手扶膝，重心前移', 'kneeling with one palm pushed forward and the other hand on the knee, weight shifted forward')
add(178, '坐姿 · 侧身撑地', '坐姿屈膝一腿立起，一手撑地，身体扭转', 'sitting with one knee raised, one hand on the ground, torso twisted')
add(179, '站姿 · 侧倾插腰', '站立双腿分开，一手叉腰身体侧倾', 'standing with legs apart, one hand on the hip, body leaning to the side')

# ════ sheet_15 ════
add(180, '深蹲 · 双手扶膝', '深蹲双脚踩地宽开，双手扶膝，胸部前压', 'squatting with feet planted wide, both hands on the knees, chest pressed forward')
add(181, '坐姿 · 抬膝扶额', '坐姿一腿盘起一手扶额，另一手扶小腿', 'sitting with one leg folded up, one hand at the forehead and the other on the shin')
add(182, '坐姿 · 侧身翘腿', '坐姿侧身双腿交叠，双手扶膝，颈部侧转', 'sitting turned sideways with legs crossed, both hands on the knees, head turned')
add(183, '坐姿 · 侧坐抱膝', '坐姿侧坐双臂环抱屈膝，头部侧倚', 'sitting to the side with arms wrapped around bent knees, head tilted')
add(184, '坐姿 · 单腿侧抬', '坐姿一腿侧向抬起，另一手撑地保持平衡', 'sitting with one leg lifted out to the side, the other hand on the ground for balance')
add(185, '深蹲 · 双手撑地', '深蹲双脚踩地，双手撑地于身前，头部抬起', 'squatting with feet planted, both hands on the ground in front, head lifted')
add(186, '坐姿 · 交叉立腿', '坐姿双腿交叉立起，上身微侧，颈部拉长', 'sitting with legs crossed and raised, torso slightly turned, neck lengthened')
add(187, '仰卧 · 抱膝蜷缩', '仰卧双腿抬起抱向胸前，团成一团', 'lying on the back with legs lifted and hugged to the chest, curled up')
add(188, '坐姿 · 抬单腿抱膝', '坐姿一腿屈起抬高，双手抱住小腿，单腿离地', 'sitting with one leg lifted and bent, both hands hugging the shin, one foot off the ground')
add(189, '站姿 · 屈膝轻抬', '站立微屈膝，一手轻抬，动态', 'standing with knees slightly bent, one hand lightly raised, dynamic')
add(190, '坐姿 · 叠腿侧身', '坐姿双腿交叠侧身，一手扶膝，颈部微侧', 'sitting with legs crossed and body turned sideways, one hand on the knee, neck slightly tilted')
add(191, '盘坐 · 手抚面部', '盘腿坐地一手轻抚面部，另一手置于膝上', 'sitting cross-legged with one hand touching the face and the other resting on the knee')

# ════ sheet_16 ════
add(192, '跪姿 · 双手抱头', '跪姿双手抱头，肘部外张，颈部收紧', 'kneeling with both hands behind the head, elbows flared, neck engaged')
add(193, '跪姿 · 单手抚颈', '跪姿一手举至颈侧，下巴抬起，颈部线条', 'kneeling with one hand raised to the side of the neck, chin lifted')
add(194, '跪姿 · 双手前屈', '跪姿双拳举至胸前，肘部弯曲，肩背收紧', 'kneeling with both fists raised in front of the chest, elbows bent, shoulders engaged')
add(195, '坐姿 · 抱膝侧倚', '坐姿屈膝侧倚，一手扶膝一手撑地', 'sitting with knees bent and leaning to one side, one hand on the knee and one supporting')
add(196, '盘坐 · 掌心相对', '盘腿坐地双手在胸前掌心相对，颈部微倾', 'sitting cross-legged with both palms facing each other in front of the chest, neck slightly tilted')
add(197, '坐姿 · 抱膝低头', '坐姿抱住双膝低头，下巴抵膝，肩背拱起', 'sitting hugging both knees with the head bowed, chin resting on the knees, back rounded')
add(198, '跪姿 · 四点侧首', '四点跪撑头转向一侧，颈部拉长，肩背平展', 'kneeling on all fours with the head turned to one side, neck lengthened, back flat')
add(199, '坐姿 · 抬膝握脚', '坐姿一腿屈起，双手握住脚踝，脚尖相对', 'sitting with one leg bent, both hands holding the ankle, toes facing each other')
add(200, '坐地 · 侧撑屈腿', '坐地双腿屈起向侧，一手撑地，头部微倾', 'sitting on the ground with both legs bent to one side, one hand supporting, head slightly tilted')
add(201, '盘坐 · 横剑身前', '盘腿坐地双手横持长剑于身前，正面构图', 'sitting cross-legged holding a sword horizontally in front, front facing composition')
add(202, '坐姿 · 抱臂侧坐', '坐姿侧坐双臂交叉抱于胸前，双腿叠放', 'sitting to the side with arms crossed over the chest, legs stacked')
add(203, '盘坐 · 双手扶膝', '盘腿坐地双手置于膝上，正面最稳的坐姿', 'sitting cross-legged with both hands on the knees, the most stable front pose')

# ════ sheet_17 ════
add(204, '坐姿 · 前倾垂臂', '坐姿屈膝上身微俯，双臂自然下垂', 'sitting with knees bent, torso slightly forward, both arms hanging naturally')

assert len(P) == 205, f"命名表只写了 {len(P)} 条，应为 205"