import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:planerz/features/activities/data/activity_photo.dart';

/// A photo ready to upload: the stored version and its thumbnail, both JPEG.
typedef PreparedActivityPhoto = ({Uint8List photo, Uint8List thumbnail});

class ActivityPhotoUnreadableException implements Exception {
  const ActivityPhotoUnreadableException();
}

/// Brings a picked photo to the stored sizes. The picker already resizes and
/// compresses JPEG photos, which are kept as they are; anything else (PNG
/// screenshot, WebP, oversized file) is re-encoded as JPEG.
Future<PreparedActivityPhoto> prepareActivityPhoto(Uint8List picked) async {
  var longestSide = 0;
  final thumbnail = await _encodeJpeg(
    await _decode(
      picked,
      maxSide: activityPhotoThumbMaxSide,
      onIntrinsicSize: (width, height) =>
          longestSide = math.max(width, height),
    ),
    quality: 70,
  );
  final keepAsIs = _isJpeg(picked) &&
      longestSide <= activityPhotoMaxSide &&
      picked.lengthInBytes <= activityPhotoMaxFileSizeBytes;
  final photo = keepAsIs
      ? picked
      : await _encodeJpeg(
          await _decode(picked, maxSide: activityPhotoMaxSide),
          quality: 80,
        );
  if (photo.lengthInBytes > activityPhotoMaxFileSizeBytes) {
    throw const ActivityPhotoUnreadableException();
  }
  return (photo: photo, thumbnail: thumbnail);
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

/// Decodes [bytes] with its longest side reduced to [maxSide] (never
/// enlarged), keeping the aspect ratio.
Future<ui.Image> _decode(
  Uint8List bytes, {
  required int maxSide,
  void Function(int width, int height)? onIntrinsicSize,
}) async {
  try {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final codec = await ui.instantiateImageCodecWithSize(
      buffer,
      getTargetSize: (width, height) {
        onIntrinsicSize?.call(width, height);
        if (math.max(width, height) <= maxSide) {
          return const ui.TargetImageSize();
        }
        return width >= height
            ? ui.TargetImageSize(width: maxSide)
            : ui.TargetImageSize(height: maxSide);
      },
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    throw const ActivityPhotoUnreadableException();
  }
}

Future<Uint8List> _encodeJpeg(
  ui.Image image, {
  required int quality,
}) async {
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (data == null) throw const ActivityPhotoUnreadableException();
    final pixels = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: data.buffer,
      bytesOffset: data.offsetInBytes,
      numChannels: 4,
    );
    return img.encodeJpg(pixels, quality: quality, chroma: img.JpegChroma.yuv420);
  } finally {
    image.dispose();
  }
}
