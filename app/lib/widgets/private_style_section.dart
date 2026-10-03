// 试衣间「私密风格」区块 —— 情趣内衣风格 chips（仅私密模式可见）
//
// 为什么从 tryon_page.dart 拆出来：一是让 900+ 行的页面瘦下来，二是
// **隐私边界更清楚**：这段只应在 AppColors.privateMode 为真时挂载，
// 独立成文件后，「它什么时候会被显示」这件事一眼可查。
//
// 隐私设计：
//   - 选中项只存内存（父级 State 持有），退出试衣间即清；
//   - 风格 key 会并入生成 prompt 发给**用户自己配置**的模型服务，
//     不进历史记录、不落SharedPreferences、不上传 Turso。
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// 私密风格（中文标签）→ 发给模型的英文描述
///
/// 放在这里而非页面里：它既是 UI 标签来源，也是 prompt 词表，
/// 两边必须同源，写在一起才不会「改了 UI 忘了改 prompt」。
const Map<String, String> kPrivateStylePrompts = {
  '蕾丝': 'wearing a delicate lace lingerie set, elegant and alluring',
  '系带': 'wearing strappy ribbon lingerie, artfully tied with satin ribbons',
  '吊带袜': 'wearing a garter belt with sheer stockings',
  '缎面': 'wearing a smooth satin slip dress lingerie with soft sheen',
  '宫廷': 'wearing an ornate royal-court style corset lingerie',
  '兔女郎': 'wearing a playful bunny girl costume with satin ears',
  '水手服': 'wearing a sailor school uniform style outfit, short pleated skirt',
  '透视罩衫': 'wearing a sheer see-through lace robe over matching lingerie',
};

class PrivateStyleSection extends StatelessWidget {
  /// 当前选中的风格 key（null = 未选）
  final String? selected;

  /// 选中/取消回调。再次点击同一项应视为取消（由父级实现 toggle 语义）
  final ValueChanged<String> onSelect;

  /// 点「清除」回调
  final VoidCallback onClear;

  const PrivateStyleSection({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('情趣内衣风格（私密）',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
              ),
              if (selected != null)
                GestureDetector(
                  onTap: onClear,
                  child: Text('清除',
                      style:
                          TextStyle(fontSize: 11.5, color: AppColors.textHint)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in kPrivateStylePrompts.entries)
                GestureDetector(
                  onTap: () => onSelect(e.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 13, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected == e.key ? AppColors.primary : AppColors.bg,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: selected == e.key
                              ? AppColors.primary
                              : AppColors.divider),
                    ),
                    child: Text(e.key,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: selected == e.key
                                ? Colors.white
                                : AppColors.textSub)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text('选中的风格会并入生成描述，只发给你自己配置的模型服务；不进历史、不留记录。',
              style: TextStyle(
                  fontSize: 10.5, color: AppColors.textHint, height: 1.5)),
        ],
      ),
    );
  }
}
