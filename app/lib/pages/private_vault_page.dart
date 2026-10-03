// 私密空间 —— 内衣模式专属页（设置页 🍑 连点 5 次 + 密码解锁后才能进）
//
// ── 数据去向（全量上云，都在用户自己的基础设施里）──
// 围度/肤色/部位图 URL：Turso private_profile 表（token 鉴权接口读写）
// 图片本体：用户自己的 Vercel Blob（private/ 目录，走 /api/upload）
// 本地 SharedPreferences 只做启动缓存：云端连不上时照常看/改，恢复后再同步
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/image_service.dart';
import '../services/private_body_store.dart';
import '../services/private_mode_service.dart';
import '../theme/app_colors.dart';

class PrivateVaultPage extends StatefulWidget {
  const PrivateVaultPage({super.key});

  @override
  State<PrivateVaultPage> createState() => _PrivateVaultPageState();
}

class _PrivateVaultPageState extends State<PrivateVaultPage> {
  final _bodyCtrls = <String, TextEditingController>{
    for (final f in PrivateBodyStore.measureLabels.keys) f: TextEditingController(),
  };
  bool _savingBody = false;
  String _busyPart = ''; // 正在上传/保存的部位 key
  bool _addingPhoto = false;
  String _cloudNote = '';

  @override
  void initState() {
    super.initState();
    _fillBodyCtrls();
    // 进页面静默刷新一次云端（拉最新）
    PrivateBodyStore.syncFromCloud().then((ok) {
      if (!mounted) return;
      setState(() {
        _cloudNote = ok
            ? ''
            : '云端没连上，当前改动只存在本机，恢复后再同步';
        _fillBodyCtrls();
      });
    });
  }

  void _fillBodyCtrls() {
    for (final f in PrivateBodyStore.measureLabels.keys) {
      final v = PrivateBodyStore.measure(f);
      _bodyCtrls[f]!.text = v == null ? '' : _fmt(v);
    }
  }

  @override
  void dispose() {
    for (final c in _bodyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  // ---- 选图 → 压缩 → 交给调用方（部位图/相册共用） ----
  Future<Uint8List?> _pickBytes(String label) async {
    try {
      final picked = await pickImage(maxWidth: 1600, quality: 88, label: label);
      return picked?.bytes;
    } catch (e) {
      if (mounted) {
        _toast(e.toString().replaceFirst(RegExp(r'^(Exception|StateError):\s*'), ''));
      }
      return null;
    }
  }

  // ---- 围度保存 ----
  Future<void> _saveBody() async {
    if (_savingBody) return;
    setState(() => _savingBody = true);
    final data = <String, double?>{};
    for (final f in PrivateBodyStore.measureLabels.keys) {
      data[f] = double.tryParse(_bodyCtrls[f]!.text.trim());
    }
    final err = await PrivateBodyStore.saveMeasures(data);
    if (!mounted) return;
    setState(() {
      _savingBody = false;
      _cloudNote = err ?? '';
    });
    _toast(err ?? '已保存到你的云端，试衣时才会发给你的模型服务');
  }

  // ---- 部位：肤色选择 ----
  Future<void> _pickSkin(String partKey) async {
    final cur = PrivateBodyStore.partsData[partKey]?.skin ?? '';
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('选${PrivateBodyStore.parts[partKey]!.$1}的肤色',
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final t in PrivateBodyStore.skinTones)
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx, t.$1),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cur == t.$1
                                  ? AppColors.primary
                                  : AppColors.divider,
                              width: cur == t.$1 ? 2 : 1),
                        ),
                        child: Column(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Color(PrivateBodyStore.skinColorValue(t.$1)),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(t.$2,
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.textSub)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    final err = await PrivateBodyStore.savePartSkin(partKey, picked);
    if (mounted) {
      setState(() => _cloudNote = err ?? '');
      _toast(err ?? '肤色已记录');
    }
  }

  // ---- 部位：高清图上传 ----
  Future<void> _uploadPart(String partKey) async {
    if (_busyPart.isNotEmpty) return;
    final bytes = await _pickBytes('部位图');
    if (bytes == null) return;
    setState(() => _busyPart = partKey);
    final err = await PrivateBodyStore.uploadPartImage(partKey, bytes);
    if (!mounted) return;
    setState(() {
      _busyPart = '';
      _cloudNote = err ?? '';
    });
    _toast(err ?? '已传到你的 Blob，试衣时会作为部位细节参照');
  }

  // ---- 相册 ----
  Future<void> _addPhoto() async {
    if (_addingPhoto) return;
    final bytes = await _pickBytes('照片');
    if (bytes == null) return;
    setState(() => _addingPhoto = true);
    final err = await PrivateBodyStore.addPhoto(bytes);
    if (!mounted) return;
    setState(() {
      _addingPhoto = false;
      _cloudNote = err ?? '';
    });
    _toast(err ?? '已放进私密相册');
  }

  Future<void> _removePhoto(String url) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('从相册移除？',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain)),
        content: Text('只从相册列表里拿掉，云端文件保留。',
            style: TextStyle(fontSize: 13, color: AppColors.textSub)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('留着', style: TextStyle(color: AppColors.textSub)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('移除', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
    if (sure != true) return;
    final err = await PrivateBodyStore.removePhoto(url);
    if (mounted) {
      setState(() => _cloudNote = err ?? '');
      _toast(err ?? '已移除');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        scrolledUnderElevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textMain),
        ),
        title: Text('私密空间',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.textMain)),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          _hero(),
          if (_cloudNote.isNotEmpty) ...[
            const SizedBox(height: 12),
            _cloudBanner(),
          ],
          const SizedBox(height: 20),
          _sectionTitle('身体围度', '私密'),
          _bodyCard(),
          const SizedBox(height: 20),
          _sectionTitle(
              '部位高清图 & 肤色（${PrivateBodyStore.partsWithImage}/9）',
              '还原试衣'),
          _partsCard(),
          const SizedBox(height: 20),
          _sectionTitle('私密相册（${PrivateBodyStore.photos.length}）', '上云'),
          _photoCard(),
          const SizedBox(height: 24),
          _logoutButton(),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '数据存在你自己的 Turso，图片存在你自己的 Vercel Blob；'
              '试衣生成时，肤色描述与部位图只发往你自己配置的模型服务。',
              style: TextStyle(
                  fontSize: 11.5, color: AppColors.textHint, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary.withValues(alpha: 0.30), AppColors.card],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.nightlife_rounded,
                color: AppColors.primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('只属于你的空间',
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textMain)),
                const SizedBox(height: 4),
                Text('九个部位的高清图与肤色都录进来，试衣还原度最高。',
                    style: TextStyle(
                        fontSize: 11.5, color: AppColors.textSub, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cloudBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              size: 14, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(_cloudNote,
                style:
                    TextStyle(fontSize: 11.5, color: AppColors.textSub)),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, String? badge) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 0, 10),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textMain)),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(badge,
                  style: TextStyle(fontSize: 10, color: AppColors.primary)),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 围度卡 ----
  Widget _bodyCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('比试衣间更细的围度，出图更贴身',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _numField('underbust')),
            const SizedBox(width: 8),
            Expanded(child: _numField('thighCm')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _numField('calfCm')),
            const SizedBox(width: 8),
            Expanded(child: _numField('shoulderCm')),
          ]),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: FilledButton(
              onPressed: _savingBody ? null : _saveBody,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _savingBody
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : Text('保存到我的云端',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numField(String field) {
    return TextField(
      controller: _bodyCtrls[field],
      keyboardType: TextInputType.number,
      style: TextStyle(fontSize: 14, color: AppColors.textMain),
      decoration: InputDecoration(
        labelText: PrivateBodyStore.measureLabels[field],
        labelStyle: TextStyle(fontSize: 11.5, color: AppColors.textHint),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.divider)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: AppColors.primary)),
      ),
    );
  }

  // ---- 9 部位卡 ----
  Widget _partsCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppColors.radius),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('每个部位都传高清图 + 选肤色，生成时按部位还原',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMain)),
          const SizedBox(height: 6),
          Text('图存你自己的 Blob；肤色会写进生成描述，部位图随请求发给你自己的服务。',
              style: TextStyle(fontSize: 11, color: AppColors.textHint, height: 1.5)),
          const SizedBox(height: 10),
          ...PrivateBodyStore.parts.keys.map(_partRow),
        ],
      ),
    );
  }

  Widget _partRow(String key) {
    final (label, _) = PrivateBodyStore.parts[key]!;
    final part = PrivateBodyStore.partsData[key] ?? const PrivatePart();
    final busy = _busyPart == key;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 部位图缩略：无图显示虚位
          GestureDetector(
            onTap: () => _uploadPart(key),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: busy
                  ? Center(
                      child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary)))
                  : part.imagePath.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                              // 私密图走鉴权代理（Bearer token），直链匿名 403
                              PrivateBodyStore.imageUri(part.imagePath)!.toString(),
                              headers: PrivateBodyStore.imageHeaders,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                  Icons.broken_image_rounded,
                                  size: 18,
                                  color: AppColors.textHint)),
                        )
                      : Icon(Icons.add_a_photo_rounded,
                          size: 18, color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
                const SizedBox(height: 5),
                GestureDetector(
                  onTap: () => _pickSkin(key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: part.skin.isNotEmpty
                          ? Color(PrivateBodyStore.skinColorValue(part.skin))
                          : AppColors.card,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                          color: part.skin.isNotEmpty
                              ? Colors.transparent
                              : AppColors.divider),
                    ),
                    child: Text(
                        part.skin.isEmpty
                            ? '选肤色'
                            : PrivateBodyStore.skinLabel(part.skin),
                        style: TextStyle(
                            fontSize: 10.5,
                            color: part.skin.isNotEmpty
                                ? Colors.black87
                                : AppColors.textSub)),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => _uploadPart(key),
            child: Text(part.imagePath.isEmpty ? '传高清图' : '更换',
                style: TextStyle(fontSize: 12, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  // ---- 私密相册卡 ----
  Widget _photoCard() {
    final photos = PrivateBodyStore.photos;
    return Container(
      padding: const EdgeInsets.all(16),
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
              Expanded(
                child: Text('存到你自己的 Blob（${photos.length} 张）',
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textMain)),
              ),
              _addingPhoto
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary))
                  : TextButton.icon(
                      onPressed: _addPhoto,
                      icon: Icon(Icons.add_a_photo_rounded,
                          size: 16, color: AppColors.primary),
                      label: Text('添加',
                          style: TextStyle(
                              fontSize: 12.5, color: AppColors.primary)),
                    ),
            ],
          ),
          const SizedBox(height: 4),
          Text('长按图片可从相册移除。',
              style: TextStyle(fontSize: 11, color: AppColors.textHint)),
          const SizedBox(height: 12),
          if (photos.isEmpty)
            Container(
              height: 90,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text('还没有照片，点右上角「添加」',
                  style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
              ),
              itemCount: photos.length,
              itemBuilder: (context, i) {
                final uri = PrivateBodyStore.imageUri(photos[i]);
                return GestureDetector(
                  onLongPress: () => _removePhoto(photos[i]),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: uri == null
                        // 没令牌就不发请求（发了必401），直接给占位块
                        ? Container(color: AppColors.bg)
                        : Image.network(
                            uri.toString(),
                            headers: PrivateBodyStore.imageHeaders,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                color: AppColors.bg)), // 加载失败给灰块
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.card,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
              title: Text('退出私密模式？',
                  style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textMain)),
              content: Text('整个 App 会立刻切回日常主题。',
                  style: TextStyle(fontSize: 13, color: AppColors.textSub)),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('不了', style: TextStyle(color: AppColors.textSub)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text('退出', style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          );
          if (ok == true && mounted) {
            await PrivateModeService.lock();
            if (mounted) Navigator.pop(context); // 私密主题已关，本页也不该再停留
          }
        },
        icon: Icon(Icons.lock_open_rounded, size: 16, color: AppColors.textSub),
        label: Text('退出私密模式',
            style: TextStyle(fontSize: 13, color: AppColors.textSub)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.divider),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  void _toast(String msg) {
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
