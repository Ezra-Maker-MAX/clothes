// 跨平台选图 + 强制压缩 —— 专治「上传图片 413 FUNCTION_PAYLOAD_TOO_LARGE」
//
// 【Vercel 硬限制】Serverless Function 请求体上限 4.5MB（Hobby 计划不可调），
// 而我们走 JSON + base64，base64 还会让体积膨胀约 33%
// → 原始图片必须 ≤3MB，函数才收得到。
//
// 【为什么不能只靠选图库的压缩参数】实测踩坑（Web 端尤其明显）：
//   · image_picker / file_picker 的 Web 端实现都是 canvas.toBlob，
//     输出格式**跟随原图 mimeType**，于是：
//       - PNG / 截图 → JPEG 的 quality 参数对无损 PNG 完全无效 → 仍是原始大图
//       - HEIC（iPhone 照片）→ 浏览器解不开，插件静默 catch 后**回退原图**
//       - GIF → 插件直接不压缩
//   · 这些情况下 base64 一膨胀就撞穿 4.5MB 上限。
//
// 【本文件的做法】两段式：
//   ① image_picker 选图（原生端 maxWidth/imageQuality 由系统解码器执行，便宜且快）
//   ② 兜底：只要【不是 JPEG】或【仍 >3MB】，就用纯 Dart 的 package:image
//      重新缩放 + 强制编码 JPEG（透明底先铺白），按字节数逐级降质/缩小，
//      直到进安全线。纯 Dart → Android/iOS/Web/桌面行为完全一致。
import 'dart:typed_data';

import 'package:image/image.dart' as img;
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

/// 选一张图（相册/文件）并压缩到安全体积。
/// - [maxWidth]  衣橱单品图 1600 足够（列表/详情最多铺满屏宽）
/// - [quality]   82 是"看不出差别"的档位，再低会出现压缩噪点
/// 返回 null = 用户取消；抛 [StateError] = 图片过大/格式解不开。
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

  final raw = await x.readAsBytes();
  if (raw.isEmpty) throw StateError('这张$label读不出来，换一张试试');

  final mime = (x.mimeType ?? '').toLowerCase();
  final isJpeg = mime.contains('jpeg') || mime.contains('jpg');

  // ① 已经是合规 JPEG → 直接用（绝大多数情况零开销）
  if (isJpeg && raw.length <= kMaxUploadBytes) {
    return PickedImage(
      bytes: raw,
      filename: x.name.isEmpty ? 'upload.jpg' : x.name,
      contentType: 'image/jpeg',
    );
  }

  // ② 兜底：非 JPEG（PNG/HEIC/GIF/未知）或仍超限 → 纯 Dart 重新编码
  final fixed = _forceJpeg(raw, maxWidth: maxWidth, quality: quality);
  if (fixed == null) {
    throw StateError(
      '浏览器解不开这张$label（如果是 iPhone 拍的 HEIC 照片，'
      '请在相册里点开另存/截图，或者先裁剪一下再传）。',
    );
  }
  final base = x.name.isEmpty ? 'upload' : x.name.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return PickedImage(
    bytes: fixed,
    filename: '$base.jpg',
    contentType: 'image/jpeg',
  );
}

/// 纯 Dart 缩放 + 强制 JPEG 编码；解码不了返回 null。
/// 逐步降质/缩小直到进安全线，仍不行返回 null（交调用方提示）。
Uint8List? _forceJpeg(Uint8List raw, {required int maxWidth, required int quality}) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return null; // HEIC 等格式：package:image 也解不开

  // 等比缩到 maxWidth 以内
  var w = decoded.width;
  var h = decoded.height;
  if (w <= 0 || h <= 0) return null;
  if (w > maxWidth) {
    h = (h * maxWidth / w).round().clamp(1, 100000);
    w = maxWidth;
  }

  var resized = img.copyResize(decoded, width: w, height: h, interpolation: img.Interpolation.average);
  // JPEG 无透明通道：PNG 抠图/透明图先铺白底，避免变黑块
  if (resized.numChannels == 4) {
    final flat = img.Image(width: resized.width, height: resized.height, numChannels: 3);
    img.fill(flat, color: img.ColorRgb8(255, 255, 255));
    img.compositeImage(flat, resized);
    resized = flat;
  }

  var q = quality;
  var out = img.encodeJpg(resized, quality: q);
  // ① 先降质
  while (out.length > kMaxUploadBytes && q > 45) {
    q -= 12;
    out = img.encodeJpg(resized, quality: q);
  }
  // ② 还超就逐步缩小（每轮 0.8 倍）
  while (out.length > kMaxUploadBytes && resized.width > 720) {
    final nw = (resized.width * 0.8).round();
    final nh = (resized.height * 0.8).round();
    resized = img.copyResize(resized, width: nw, height: nh, interpolation: img.Interpolation.average);
    out = img.encodeJpg(resized, quality: q);
  }
  return out.length <= kMaxUploadBytes ? out : null;
}
