// 分类管理弹层 —— 对应竞品「编辑分类」：拖动调整排序、重命名、新建（映射引擎
// 适配类别）、删除。内置分类可重命名不可删除（id=引擎 key，改名不影响引擎）。
// 每个操作即时落库（/api/categories），关闭后由父页刷新。
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/api_client.dart';
import '../theme/app_colors.dart';

class CategoryManageSheet extends StatefulWidget {
  const CategoryManageSheet({super.key, required this.categories});

  final List<CategoryInfo> categories;

  @override
  State<CategoryManageSheet> createState() => _CategoryManageSheetState();
}

class _CategoryManageSheetState extends State<CategoryManageSheet> {
  late List<CategoryInfo> _list;
  bool _adding = false;
  final _newNameCtrl = TextEditingController();
  String _newEngineKey = 'tops'; // 新分类映射的引擎适配类别

  /// 引擎适配类别候选（固定 6 类，推荐引擎只认这些）
  static const _engineOptions = [
    ('tops', '上衣'), ('bottoms', '裤装'), ('dresses', '裙装'),
    ('outerwear', '外套'), ('shoes', '鞋子'), ('accessories', '配饰'),
  ];

  @override
  void initState() {
    super.initState();
    _list = List.of(widget.categories);
  }

  @override
  void dispose() {
    _newNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _persistOrder() async {
    try {
      await ApiClient.reorderCategories(_list.map((c) => c.id).toList());
    } catch (e) {
      _snack('排序没存上：${_short(e)}');
    }
  }

  Future<void> _rename(CategoryInfo c) async {
    final ctrl = TextEditingController(text: c.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('重命名分类',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 12,
          style: TextStyle(fontSize: 15, color: AppColors.textMain),
          decoration: InputDecoration(
            hintText: '分类名称',
            counterText: '',
            filled: true,
            fillColor: AppColors.bg,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('取消', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text('保存', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || name == c.name) return;
    try {
      await ApiClient.renameCategory(id: c.id, name: name);
      if (mounted) {
        setState(() {
          _list = _list
              .map((x) => x.id == c.id
                  ? CategoryInfo(id: x.id, name: name, engineKey: x.engineKey, sortOrder: x.sortOrder, isBuiltin: x.isBuiltin)
                  : x)
              .toList();
        });
      }
    } catch (e) {
      _snack('没改上：${_short(e)}');
    }
  }

  Future<void> _delete(CategoryInfo c) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('删掉这个分类？',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textMain)),
        content: Text('「${c.name}」将从分类列表移除。${c.isBuiltin ? '内置分类不可删除。' : '分类下的单品不受影响，但需要先移走才能删。'}',
            style: TextStyle(fontSize: 13.5, color: AppColors.textSub)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('算了', style: TextStyle(color: AppColors.textSub))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Color(0xFFB4654A), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (sure != true) return;
    try {
      await ApiClient.deleteCategory(c.id);
      if (mounted) setState(() => _list.removeWhere((x) => x.id == c.id));
    } catch (e) {
      _snack(_short(e)); // 服务端会提示"还有单品，先移走"
    }
  }

  Future<void> _create() async {
    final name = _newNameCtrl.text.trim();
    if (name.isEmpty) {
      _snack('先给新分类起个名字');
      return;
    }
    try {
      await ApiClient.createCategory(name: name, engineKey: _newEngineKey);
      if (mounted) {
        final fresh = await ApiClient.getCategories();
        setState(() {
          _list = fresh;
          _adding = false;
          _newNameCtrl.clear();
        });
      }
    } catch (e) {
      _snack('没建上：${_short(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Text('管理分类',
                    style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textMain)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: AppColors.textSub),
                ),
              ],
            ),
            Text('长按拖动调整排序；新建分类会映射到推荐引擎的适配类别，不影响搭配推荐。',
                style: TextStyle(fontSize: 11.5, color: AppColors.textHint)),
            const SizedBox(height: 8),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: _list.length,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final moved = _list.removeAt(oldIndex);
                    _list.insert(newIndex, moved);
                  });
                  _persistOrder();
                },
                itemBuilder: (_, i) {
                  final c = _list[i];
                  return Container(
                    key: ValueKey(c.id),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.bg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: i,
                          child: Icon(Icons.drag_indicator_rounded, size: 20, color: AppColors.textHint),
                        ),
                        const SizedBox(width: 6),
                        Text(c.emoji, style: const TextStyle(fontSize: 15)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(c.name,
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMain)),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _rename(c),
                          icon: Icon(Icons.edit_outlined, size: 18, color: AppColors.textSub),
                        ),
                        if (!c.isBuiltin)
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _delete(c),
                            icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Color(0xFFB4654A)),
                          )
                        else
                          const SizedBox(width: 42),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            // ---- 新建分类 ----
            if (_adding) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _newNameCtrl,
                      autofocus: true,
                      maxLength: 12,
                      style: TextStyle(fontSize: 14.5, color: AppColors.textMain),
                      decoration: InputDecoration(
                        hintText: '新分类名称，如「吊带打底」',
                        counterText: '',
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('搭配推荐时按哪个类别算适配度？',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSub)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (key, label) in _engineOptions)
                          GestureDetector(
                            onTap: () => setState(() => _newEngineKey = key),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _newEngineKey == key ? AppColors.primary : AppColors.card,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: _newEngineKey == key ? AppColors.primary : AppColors.divider),
                              ),
                              child: Text(label,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight:
                                          _newEngineKey == key ? FontWeight.bold : FontWeight.w500,
                                      color: _newEngineKey == key ? Colors.white : AppColors.textSub)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => setState(() => _adding = false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textSub,
                              side: BorderSide(color: AppColors.divider),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text('取消'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _create,
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            ),
                            child: const Text('创建'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _adding = true),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('新建分类', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _short(Object e) {
    var msg = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
    return msg.length > 70 ? '${msg.substring(0, 70)}…' : msg;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: 13)),
        backgroundColor: AppColors.textMain,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }
}
