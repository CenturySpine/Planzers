import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// A photo ready to be sent in a conversation.
@immutable
class ChatOutgoingImage {
  const ChatOutgoingImage({
    required this.bytes,
    required this.fileExt,
    required this.caption,
    this.width,
    this.height,
  });

  final Uint8List bytes;
  final String fileExt;
  final String caption;
  final double? width;
  final double? height;
}

/// Lets the user choose a photo (gallery or camera), then preview it with an
/// optional caption before sending. Returns null when cancelled.
Future<ChatOutgoingImage?> pickChatImage(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(PhosphorIconsRegular.images),
              title: Text(l10n.accountChooseFromGallery),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(PhosphorIconsRegular.camera),
              title: Text(l10n.accountTakePhoto),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
          ],
        ),
      );
    },
  );
  if (source == null || !context.mounted) return null;

  final picked = await ImagePicker().pickImage(
    source: source,
    maxWidth: 2048,
    maxHeight: 2048,
    imageQuality: 85,
  );
  if (picked == null || !context.mounted) return null;
  final bytes = await picked.readAsBytes();
  if (!context.mounted) return null;

  return Navigator.of(context, rootNavigator: true).push<ChatOutgoingImage>(
    MaterialPageRoute<ChatOutgoingImage>(
      fullscreenDialog: true,
      builder: (_) => ChatImageSendPage(
        initialBytes: bytes,
        initialPath: picked.path,
      ),
    ),
  );
}

String _fileExtension(String path) {
  final match = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(path);
  return match?.group(1)?.toLowerCase() ?? 'jpg';
}

Future<(double, double)?> _decodeImageDimensions(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final width = image.width.toDouble();
    final height = image.height.toDouble();
    image.dispose();
    codec.dispose();
    if (width <= 0 || height <= 0) return null;
    return (width, height);
  } catch (_) {
    return null;
  }
}

/// Full-screen preview of a photo about to be sent: optional crop and
/// caption, then send.
class ChatImageSendPage extends StatefulWidget {
  const ChatImageSendPage({
    super.key,
    required this.initialBytes,
    required this.initialPath,
  });

  final Uint8List initialBytes;
  final String initialPath;

  @override
  State<ChatImageSendPage> createState() => _ChatImageSendPageState();
}

class _ChatImageSendPageState extends State<ChatImageSendPage> {
  final _captionController = TextEditingController();
  late Uint8List _bytes = widget.initialBytes;
  late String _path = widget.initialPath;
  bool _busy = false;

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _crop() async {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final webCropWidth = ((screenSize.width - 140).clamp(260.0, 900.0)).round();
    final webCropHeight =
        ((screenSize.height - 320).clamp(220.0, 700.0)).round();

    final cropped = await ImageCropper().cropImage(
      sourcePath: _path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: l10n.chatCropImageTitle,
          toolbarColor: colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: colorScheme.primary,
          dimmedLayerColor: Colors.black54,
          lockAspectRatio: false,
          initAspectRatio: CropAspectRatioPreset.original,
        ),
        IOSUiSettings(
          title: l10n.chatCropImageTitle,
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
        ),
        if (kIsWeb)
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
            size: CropperSize(width: webCropWidth, height: webCropHeight),
          ),
      ],
    );
    if (cropped == null) return;
    final bytes = await cropped.readAsBytes();
    if (!mounted) return;
    setState(() {
      _bytes = bytes;
      _path = cropped.path;
    });
  }

  Future<void> _send() async {
    if (_busy) return;
    if (_bytes.length > TripMessagesRepository.maxImageBytes) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.chatImageTooLarge),
        ),
      );
      return;
    }
    setState(() => _busy = true);
    final dimensions = await _decodeImageDimensions(_bytes);
    if (!mounted) return;
    Navigator.of(context).pop(
      ChatOutgoingImage(
        bytes: _bytes,
        fileExt: _fileExtension(_path),
        caption: _captionController.text.trim(),
        width: dimensions?.$1,
        height: dimensions?.$2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(PhosphorIconsRegular.x),
          tooltip: l10n.commonCancel,
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(PhosphorIconsRegular.crop),
            tooltip: l10n.chatCropImageTitle,
            onPressed: _busy ? null : () => unawaited(_crop()),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.memory(
                    _bytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _captionController,
                      style: const TextStyle(color: Colors.white),
                      cursorColor: Colors.white,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          TripMessagesRepository.maxTextLength,
                        ),
                      ],
                      decoration: InputDecoration(
                        hintText: l10n.chatImageCaptionHint,
                        hintStyle: const TextStyle(color: Colors.white60),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        filled: true,
                        fillColor: Colors.white.withValues(alpha: 0.14),
                        border: const OutlineInputBorder(
                          borderSide: BorderSide.none,
                          borderRadius: BorderRadius.all(Radius.circular(24)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    icon: const Icon(
                      PhosphorIconsFill.paperPlaneRight,
                      size: 20,
                    ),
                    tooltip: l10n.chatSend,
                    onPressed: _busy ? null : () => unawaited(_send()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
