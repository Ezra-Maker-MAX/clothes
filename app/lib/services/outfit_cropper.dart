// 穿搭拆图 —— 把「一整身照片」按模型给的位置框裁成单件图
//
// 为什么裁剪放在客户端：图片压缩后仍要直发用户自己的模型服务 / 上传 Blob，
// 全程不经过衣念服务端（与试衣一致的隐私红线）。服务端裁剪会把用户照片
// 送到第三方存储，性质就变了。
//
// 位置框（box）是模型给的 0~1 归一化坐标，这里做三重防御：
//   1. 裁剪范围必须落在原图内（模型偶尔会给越界坐标）
//   2. 边长不小于原图的 4%（防止「box 退化成整图」或「退化成一条线」）
//   3. 裁完若过小（< 40px）视为无效，退回使用整图 —— 大宁可小不小
import 'dart:typed_data';

import 'package:image/image.dart' as img;

class CropResult {
  const CropResult({required this.bytes, required this.ok, this.note});

  final Uint8List bytes;
  final bool ok; // false 表示用了兜底（原图），note 说明原因
  final String? note;
}

class OutfitCropper {
  /// 归一化位置框 → 裁剪出的 JPEG 字节
  /// [box] = [left, top, width, height]，取值 0~1
  static CropResult crop({
    required Uint8List original,
    required List<double> box,
    int maxWidth = 1280,
    int quality = 88,
  }) {
    final decoded = img.decodeImage(original);
    if (decoded == null) {
      return CropResult(bytes: original, ok: false, note: '这张图解不开，用原图');
    }

    final iw = decoded.width;
    final ih = decoded.height;

    // 归一化 → 像素，并夹到图内
    var x = (box[0] * iw).round();
    var y = (box[1] * ih).round();
    var w = (box[2] * iw).round();
    var h = (box[3] * ih).round();

    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x + w > iw) w = iw - x;
    if (y + h > ih) h = ih - y;

    // 太小 → 判定为模型给的框不可用，退回原图
    if (w < iw * 0.04 || h < ih * 0.04 || w < 40 || h < 40) {
      return CropResult(bytes: original, ok: false, note: '模型给的位置太小，这件先用整图');
    }

    var piece = img.copyCrop(decoded, x: x, y: y, width: w, height: h);

    // 过大的先等比缩小，后面统一编码
    if (piece.width > maxWidth) {
      piece = img.copyResize(piece,
          width: maxWidth, interpolation: img.Interpolation.average);
    }
    // 透明底铺白，避免转 JPEG 变黑
    if (piece.numChannels == 4) {
      final white = img.Image(width: piece.width, height: piece.height, numChannels: 3);
      img.fill(white, color: img.ColorRgb8(255, 255, 255));
      img.compositeImage(white, piece);
      piece = white;
    }
    return CropResult(bytes: img.encodeJpg(piece, quality: quality), ok: true);
  }
}
