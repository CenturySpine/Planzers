import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';

/// Maximum width/height for image thumbnails in the trip chat list.
const double chatImageBubbleMaxExtent = 280;

/// Opens a full-screen viewer with pinch-to-zoom for a chat image URL.
Future<void> showChatImageViewer({
  required BuildContext context,
  required String imageUrl,
  required CrossCache crossCache,
  String? caption,
}) {
  final cleanUrl = imageUrl.trim();
  if (cleanUrl.isEmpty) return Future.value();

  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) => _ChatImageViewerPage(
        imageUrl: cleanUrl,
        crossCache: crossCache,
        caption: caption?.trim(),
      ),
    ),
  );
}

class _ChatImageViewerPage extends StatelessWidget {
  const _ChatImageViewerPage({
    required this.imageUrl,
    required this.crossCache,
    this.caption,
  });

  final String imageUrl;
  final CrossCache crossCache;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final cleanCaption = caption ?? '';
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Center(
                  child: Image(
                    image: CachedNetworkImage(imageUrl, crossCache),
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(
                          color: Colors.white70,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white54,
                        size: 48,
                      );
                    },
                  ),
                ),
              ),
            ),
            if (cleanCaption.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Text(
                  cleanCaption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
