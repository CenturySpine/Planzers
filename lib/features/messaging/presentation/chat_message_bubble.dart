import 'dart:async';
import 'dart:math' as math;

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/core/presentation/linkified_text.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/presentation/chat_image_viewer.dart';
import 'package:planerz/features/messaging/presentation/reply_widgets.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Width reserved on the left of received messages for the author avatar.
const double chatAvatarSlotWidth = 36;

/// What a message row needs to know about the message it replies to.
@immutable
class ChatQuote {
  const ChatQuote({
    required this.authorLabel,
    required this.text,
    required this.isImage,
  });

  final String authorLabel;
  final String text;
  final bool isImage;
}

/// One message of the conversation: avatar, bubble, reactions and the
/// gestures attached to it (long press, swipe to reply).
class ChatMessageRow extends StatelessWidget {
  const ChatMessageRow({
    super.key,
    required this.message,
    required this.isMine,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.authorLabel,
    required this.authorPhotoUrl,
    required this.timeLabel,
    required this.crossCache,
    required this.highlightedMessageId,
    this.quote,
    this.localImageBytes,
    this.uploadProgress,
    this.onOpenMenu,
    this.onImageTap,
    this.onQuoteTap,
    this.onReactionsTap,
    this.onSwipeReply,
    this.onRetry,
  });

  final TripMessage message;
  final bool isMine;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String authorLabel;
  final String? authorPhotoUrl;
  final String timeLabel;
  final CrossCache crossCache;
  final ValueListenable<String?> highlightedMessageId;
  final ChatQuote? quote;
  final Uint8List? localImageBytes;
  final ValueListenable<double>? uploadProgress;

  /// Called with the bubble position on screen (long press / right click).
  final ValueChanged<Rect>? onOpenMenu;
  final VoidCallback? onImageTap;
  final VoidCallback? onQuoteTap;
  final VoidCallback? onReactionsTap;
  final VoidCallback? onSwipeReply;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final maxBubbleWidth = math.min(screenWidth * 0.8, 480.0);
    final hasReactions = message.reactionsByUser.isNotEmpty;

    BuildContext? bubbleContext;
    void openMenu() {
      final box = bubbleContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) return;
      onOpenMenu?.call(box.localToGlobal(Offset.zero) & box.size);
    }

    Widget bubble = Builder(
      builder: (ctx) {
        bubbleContext = ctx;
        return _Bubble(
          message: message,
          isMine: isMine,
          isFirstInGroup: isFirstInGroup,
          isLastInGroup: isLastInGroup,
          authorLabel: authorLabel,
          timeLabel: timeLabel,
          quote: quote,
          maxWidth: maxBubbleWidth,
          crossCache: crossCache,
          localImageBytes: localImageBytes,
          uploadProgress: uploadProgress,
          onImageTap: onImageTap,
          onQuoteTap: onQuoteTap,
          onRetry: onRetry,
        );
      },
    );

    if (hasReactions) {
      bubble = Stack(
        clipBehavior: Clip.none,
        children: [
          Padding(padding: const EdgeInsets.only(bottom: 18), child: bubble),
          Positioned(
            bottom: 0,
            left: isMine ? null : 8,
            right: isMine ? 8 : null,
            child: _ReactionsChip(
              reactionsByUser: message.reactionsByUser,
              onTap: onReactionsTap,
            ),
          ),
        ],
      );
    }

    Widget row = Padding(
      padding: EdgeInsets.fromLTRB(8, isFirstInGroup ? 8 : 2, 8, 0),
      child: Row(
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            SizedBox(
              width: chatAvatarSlotWidth,
              child: isLastInGroup
                  ? Align(
                      alignment: Alignment.bottomLeft,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: hasReactions ? 18 : 0),
                        child: buildProfileBadge(
                          context: context,
                          displayLabel: authorLabel,
                          photoUrl: (authorPhotoUrl?.isEmpty ?? true)
                              ? ''
                              : authorPhotoUrl,
                          size: 28,
                        ),
                      ),
                    )
                  : null,
            ),
          Flexible(child: bubble),
        ],
      ),
    );

    if (onOpenMenu != null) {
      row = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onLongPress: () {
          unawaited(HapticFeedback.mediumImpact());
          openMenu();
        },
        onSecondaryTap: openMenu,
        child: row,
      );
    }

    if (onSwipeReply != null) {
      row = _SwipeToReply(onReply: onSwipeReply!, child: row);
    }

    return ValueListenableBuilder<String?>(
      valueListenable: highlightedMessageId,
      child: row,
      builder: (context, highlightedId, child) {
        final highlighted = highlightedId == message.id;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          color: highlighted
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.14)
              : Colors.transparent,
          child: child,
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.message,
    required this.isMine,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.authorLabel,
    required this.timeLabel,
    required this.quote,
    required this.maxWidth,
    required this.crossCache,
    required this.localImageBytes,
    required this.uploadProgress,
    required this.onImageTap,
    required this.onQuoteTap,
    required this.onRetry,
  });

  final TripMessage message;
  final bool isMine;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final String authorLabel;
  final String timeLabel;
  final ChatQuote? quote;
  final double maxWidth;
  final CrossCache crossCache;
  final Uint8List? localImageBytes;
  final ValueListenable<double>? uploadProgress;
  final VoidCallback? onImageTap;
  final VoidCallback? onQuoteTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background =
        isMine ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final foreground = isMine ? scheme.onPrimaryContainer : scheme.onSurface;
    final metaColor = foreground.withValues(alpha: 0.6);

    const large = Radius.circular(16);
    const small = Radius.circular(5);
    final radius = isMine
        ? BorderRadius.only(
            topLeft: large,
            bottomLeft: large,
            topRight: isFirstInGroup ? large : small,
            bottomRight: isLastInGroup ? large : small,
          )
        : BorderRadius.only(
            topRight: large,
            bottomRight: large,
            topLeft: isFirstInGroup ? large : small,
            bottomLeft: isLastInGroup ? large : small,
          );

    final showAuthor = !isMine && isFirstInGroup && authorLabel.isNotEmpty;
    final text = message.text;
    final hasText = text.isNotEmpty;
    final isImage = message.isImage;

    final meta = _MessageMeta(
      timeLabel: timeLabel,
      color: metaColor,
      sendState: isMine ? message.sendState : null,
      errorColor: scheme.error,
    );

    double? imageWidth;
    double? imageHeight;
    if (isImage) {
      final extent = math.min(maxWidth, chatImageBubbleMaxExtent);
      final w = message.imageWidth ?? 4;
      final h = message.imageHeight ?? 3;
      final aspect = (w > 0 && h > 0 ? w / h : 4 / 3).clamp(0.6, 1.8);
      imageWidth = aspect >= 1 ? extent : extent * aspect;
      imageHeight = imageWidth / aspect;
      // Keep the bubble wide enough for a readable caption or quote.
      if (hasText || quote != null) imageWidth = math.max(imageWidth, 200.0);
    }

    final children = <Widget>[
      if (showAuthor)
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
          child: Text(
            authorLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              color: chatAuthorColor(message.authorId, theme.brightness),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      if (quote != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
          child: QuotedMessageSnippet(
            authorLabel: quote!.authorLabel,
            text: quote!.text,
            isImage: quote!.isImage,
            onTap: onQuoteTap,
          ),
        ),
      if (isImage)
        Padding(
          padding: const EdgeInsets.all(3),
          child: _BubbleImage(
            message: message,
            width: imageWidth! - 6,
            height: imageHeight!,
            crossCache: crossCache,
            localImageBytes: localImageBytes,
            uploadProgress: uploadProgress,
            overlayMeta: hasText ? null : meta,
            onTap: onImageTap,
            onRetry: onRetry,
          ),
        ),
      if (hasText)
        _BubbleText(
          text: text,
          color: foreground,
          linkColor: scheme.primary,
          meta: meta,
          metaWidth: _MessageMeta.estimatedWidth(
            context,
            timeLabel: timeLabel,
            hasStatus: isMine,
          ),
        ),
    ];

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
    content = isImage
        ? SizedBox(width: imageWidth, child: content)
        : IntrinsicWidth(child: content);

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(color: background, borderRadius: radius),
        child: ClipRRect(borderRadius: radius, child: content),
      ),
    );
  }
}

/// Stable, readable colour for an author name.
Color chatAuthorColor(String authorId, Brightness brightness) {
  var hash = 0;
  for (final unit in authorId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7fffffff;
  }
  final hue = (hash % 24) * 15.0;
  return HSLColor.fromAHSL(
    1,
    hue,
    0.6,
    brightness == Brightness.dark ? 0.72 : 0.36,
  ).toColor();
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({
    required this.timeLabel,
    required this.color,
    required this.sendState,
    required this.errorColor,
  });

  static const double _fontSize = 11;
  static const double _iconSize = 14;

  final String timeLabel;
  final Color color;

  /// Null for received messages (no delivery mark).
  final TripMessageSendState? sendState;
  final Color errorColor;

  /// Room to keep free at the end of the last text line.
  static double estimatedWidth(
    BuildContext context, {
    required String timeLabel,
    required bool hasStatus,
  }) {
    final scale = MediaQuery.textScalerOf(context).scale(_fontSize) / _fontSize;
    final textWidth = timeLabel.length * _fontSize * 0.58 * scale;
    return textWidth + (hasStatus ? _iconSize * scale + 3 : 0) + 10;
  }

  @override
  Widget build(BuildContext context) {
    final state = sendState;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          timeLabel,
          style: TextStyle(fontSize: _fontSize, color: color, height: 1.1),
        ),
        if (state != null) ...[
          const SizedBox(width: 3),
          Icon(
            switch (state) {
              TripMessageSendState.sending => PhosphorIconsRegular.clock,
              TripMessageSendState.sent => PhosphorIconsRegular.check,
              TripMessageSendState.failed => PhosphorIconsRegular.warningCircle,
            },
            size: MediaQuery.textScalerOf(context).scale(_iconSize),
            color: state == TripMessageSendState.failed ? errorColor : color,
          ),
        ],
      ],
    );
  }
}

/// True for a message made of one to three emojis only (shown larger).
@visibleForTesting
bool isEmojiOnlyMessage(String text) {
  if (text.isEmpty || text.length > 48) return false;
  var count = 0;
  for (final cluster in text.characters) {
    if (cluster.trim().isEmpty) continue;
    if (!_isEmojiRune(cluster.runes.first)) return false;
    if (++count > 3) return false;
  }
  return count > 0;
}

bool _isEmojiRune(int rune) {
  return (rune >= 0x1F000 && rune <= 0x1FAFF) || // pictographs, flags
      (rune >= 0x2600 && rune <= 0x27BF) || // misc symbols, dingbats
      (rune >= 0x2B00 && rune <= 0x2BFF) || // stars, arrows
      (rune >= 0x2300 && rune <= 0x23FF) || // technical (watch, hourglass)
      rune == 0x203C ||
      rune == 0x2049 ||
      rune == 0x00A9 ||
      rune == 0x00AE;
}

final RegExp _urlRegex = RegExp(
  r'(https?://[^\s]+)|(www\.[^\s]+)',
  caseSensitive: false,
);

/// Message text with tappable links; the time sits at the end of the last
/// line when there is room, like in usual chat apps.
class _BubbleText extends StatefulWidget {
  const _BubbleText({
    required this.text,
    required this.color,
    required this.linkColor,
    required this.meta,
    required this.metaWidth,
  });

  final String text;
  final Color color;
  final Color linkColor;
  final Widget meta;
  final double metaWidth;

  @override
  State<_BubbleText> createState() => _BubbleTextState();
}

class _BubbleTextState extends State<_BubbleText> {
  final _recognizers = <TapGestureRecognizer>[];
  List<InlineSpan>? _spans;

  @override
  void didUpdateWidget(covariant _BubbleText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.linkColor != widget.linkColor) {
      _spans = null;
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  List<InlineSpan> _buildSpans() {
    _disposeRecognizers();
    final text = widget.text;
    if (!text.contains('http') && !text.contains('www.')) {
      return [TextSpan(text: text)];
    }
    final linkStyle = TextStyle(
      color: widget.linkColor,
      decoration: TextDecoration.underline,
      decorationColor: widget.linkColor,
    );
    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in _urlRegex.allMatches(text)) {
      final rawUrl = trimUrlWrappingPunctuation(match.group(0)!);
      if (rawUrl.isEmpty) continue;
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      final href =
          rawUrl.toLowerCase().startsWith('www.') ? 'https://$rawUrl' : rawUrl;
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (mounted) unawaited(openExternalUrl(context, href));
        };
      _recognizers.add(recognizer);
      spans.add(TextSpan(text: rawUrl, style: linkStyle, recognizer: recognizer));
      start = match.start + rawUrl.length;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEmojiOnly = isEmojiOnlyMessage(widget.text);
    final baseStyle = (theme.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      color: widget.color,
      fontSize: isEmojiOnly ? 34 : null,
      height: isEmojiOnly ? 1.2 : 1.3,
    );
    final spans = _spans ??= _buildSpans();
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
          child: Text.rich(
            TextSpan(
              style: baseStyle,
              children: [
                ...spans,
                // Keeps the end of the last line free for the time.
                WidgetSpan(child: SizedBox(width: widget.metaWidth, height: 1)),
              ],
            ),
          ),
        ),
        Positioned(right: 8, bottom: 5, child: widget.meta),
      ],
    );
  }
}

class _BubbleImage extends StatelessWidget {
  const _BubbleImage({
    required this.message,
    required this.width,
    required this.height,
    required this.crossCache,
    required this.localImageBytes,
    required this.uploadProgress,
    required this.overlayMeta,
    required this.onTap,
    required this.onRetry,
  });

  final TripMessage message;
  final double width;
  final double height;
  final CrossCache crossCache;
  final Uint8List? localImageBytes;
  final ValueListenable<double>? uploadProgress;

  /// Time shown on top of the image when there is no caption below.
  final _MessageMeta? overlayMeta;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = message.imageUrl ?? '';
    ImageProvider? provider;
    if (localImageBytes != null) {
      provider = MemoryImage(localImageBytes!);
    } else if (url.isNotEmpty) {
      provider = CachedNetworkImage(url, crossCache);
    }
    final cacheWidth =
        (width * MediaQuery.devicePixelRatioOf(context)).round();
    final placeholder = ColoredBox(
      color: scheme.onSurface.withValues(alpha: 0.08),
      child: const SizedBox.expand(),
    );

    final progress = uploadProgress;
    final overlay = overlayMeta;

    return GestureDetector(
      onTap: message.isFailed ? onRetry : onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: SizedBox(
          width: width,
          height: height,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (provider == null)
                placeholder
              else
                Image(
                  image: ResizeImage.resizeIfNeeded(cacheWidth, null, provider),
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, wasSync) {
                    if (wasSync || frame != null) return child;
                    return placeholder;
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Icon(
                      PhosphorIconsRegular.imageBroken,
                      color: scheme.onSurfaceVariant,
                      size: 32,
                    ),
                  ),
                ),
              if (message.isFailed)
                const Center(
                  child: _ImageBadge(
                    child: Icon(
                      PhosphorIconsRegular.arrowClockwise,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                )
              else if (message.isSending && progress != null)
                Center(
                  child: _ImageBadge(
                    child: ValueListenableBuilder<double>(
                      valueListenable: progress,
                      builder: (context, value, _) => SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          value: value <= 0 ? null : value,
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              if (overlay != null)
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      child: _MessageMeta(
                        timeLabel: overlay.timeLabel,
                        color: Colors.white,
                        sendState: overlay.sendState,
                        errorColor: overlay.errorColor,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        shape: BoxShape.circle,
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
  }
}

/// Emojis sorted by popularity, most used first.
List<String> sortedReactionEmojis(Map<String, String> reactionsByUser) {
  final counts = <String, int>{};
  for (final emoji in reactionsByUser.values) {
    counts[emoji] = (counts[emoji] ?? 0) + 1;
  }
  final emojis = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return emojis;
}

class _ReactionsChip extends StatelessWidget {
  const _ReactionsChip({required this.reactionsByUser, required this.onTap});

  final Map<String, String> reactionsByUser;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final emojis = sortedReactionEmojis(reactionsByUser).take(3).join();
    final total = reactionsByUser.length;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              total > 1 ? '$emojis $total' : emojis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lets the reader drag a message to the right to reply to it.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.onReply, required this.child});

  final VoidCallback onReply;
  final Widget child;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply>
    with SingleTickerProviderStateMixin {
  static const double _triggerDistance = 56;
  static const double _maxDistance = 84;

  late final AnimationController _settle = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(() {
      _offset.value = _releasedFrom * (1 - Curves.easeOut.transform(_settle.value));
    });

  final _offset = ValueNotifier<double>(0);
  double _releasedFrom = 0;
  bool _armed = false;

  @override
  void dispose() {
    _settle.dispose();
    _offset.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _settle.stop();
    final next = (_offset.value + details.delta.dx).clamp(0.0, _maxDistance);
    final armed = next >= _triggerDistance;
    if (armed && !_armed) unawaited(HapticFeedback.selectionClick());
    _armed = armed;
    _offset.value = next;
  }

  void _onDragEnd([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    _armed = false;
    _releasedFrom = _offset.value;
    _settle.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _onDragEnd,
      child: ValueListenableBuilder<double>(
        valueListenable: _offset,
        child: widget.child,
        builder: (context, offset, child) {
          final reveal = (offset / _triggerDistance).clamp(0.0, 1.0);
          // Same widget tree whatever the offset, so the row keeps its state.
          return Stack(
            children: [
              if (offset > 0)
                Positioned.fill(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Opacity(
                        opacity: reveal,
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * reveal,
                          child: Icon(
                            PhosphorIconsRegular.arrowBendUpLeft,
                            color: scheme.onSurfaceVariant,
                            size: 22,
                            semanticLabel:
                                AppLocalizations.of(context)!.chatReply,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              Transform.translate(
                key: const ValueKey('swipe-content'),
                offset: Offset(offset, 0),
                child: child,
              ),
            ],
          );
        },
      ),
    );
  }
}
