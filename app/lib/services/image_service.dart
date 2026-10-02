// 跨平台选图 + 压缩 —— 专治「上传图片 413 FUNCTION_PAYLOAD_TOO_LARGE」
//
// 根因：Vercel Serverless Function 请求体硬上限 4.5MB（Hobby 计划不可调），
// 而我们走 JSON + base64 上传，base64 还会让体积膨胀约 33%，
// 也就是原始图片必须压到 3MB 以内，函数才收得到。
// 之前用 file_picker 的 compressionQuality 在 Android 上【完全不生效】
//（该参数仅 iOS / macOS / Web 支持），手机选图拿到的是原图（3~8MB）→ 必然 413。
//
// 现改为 image_picker：maxWidth / imageQuality 由 Android 原生解码器执行，
// Android / iOS / Web / 桌面行为一致，压完通常 200~600KB。
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

class PickedImage {
  final Uint8List bytes;
  final String filename;
  final String contentType;

  const PickedImage({
    required this.bytes,
    required this.filename,
    required this.contentType,
  });

  double get mb => bytes.length / 1024 / 1024;
}

/// 上传安全线：base64 后必须 < 4.5MB → 原图 < 3.2MB，留 3MB 余量
const int kMaxUploadBytes = 3 * 1024 * 1024;

/// 选一张图（相册/文件）并压缩。
/// - [maxWidth]  衣橱单品图 1600 足够（列表/详情最多铺满屏宽）
/// - [quality]   82 是"看不出差别"的档位，再低会出现压缩噪点
/// 返回 null = 用户取消；抛 [StateError] = 图片过大/不可读。
Future<PickedImage?> pickImage({
  int maxWidth = 1600,
  int quality = 82,
  String label = '图片',
}) async {
  final picker = ImagePicker();
  final x = await picker.pickImage(
    source: ImageSource.gallery,
    maxWidth: maxWidth.toDouble(),
    imageQuality: quality,
  );
  if (x == null) return null;

  final bytes = await x.readAsBytes();
  if (bytes.isEmpty) throw StateError('这张$label读不出来，换一张试试');

  final mime = x.mimeType ?? '';
  final isPng = mime.contains('png') || x.name.toLowerCase().endsWith('.png');

  if (bytes.length > kMaxUploadBytes) {
    throw StateError(
      '这张$label有 ${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB，太大了'
      '（上限 3MB）。换一张，或先用手机相册裁剪一下再试。',
    );
  }

  return PickedImage(
    bytes: bytes,
    filename: x.name.isEmpty ? 'upload.jpg' : x.name,
    contentType: isPng ? 'image/png' : 'image/jpeg',
  );
}
