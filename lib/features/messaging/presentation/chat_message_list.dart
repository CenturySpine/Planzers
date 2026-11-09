import 'dart:async';

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/messaging/chat_controller/trip_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/presentation/chat_message_bubble.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Scrollable conversation: newest message at the bottom, day separators,
/// history loaded while scrolling up and a shortcut back to the latest
/// messages.
class ChatMessageList extends StatefulWidget {
  const ChatMessageList({
    super.key,
    required this.controller,
    required this.currentUserId,
    required this.memberLabels,
    required this.memberPhotoUrls,
    required this.fallbackAuthorLabel,
    required this.crossCache,
    this.unreadSince,
    this.onOpenMenu,
    this.onImageTap,
    this.onReactionsTap,
    this.onSwipeReply,
    this.onRetry,
  });

  final TripChatController controller;
  final String? currentUserId;
  final Map<String, String> memberLabels;
  final Map<String, String> memberPhotoUrls;

  /// Name shown for an author who is no longer a known trip member.
  final String fallbackAuthorLabel;
  final CrossCache crossCache;

  /// Messages received after this time are introduced by an "unread" marker.
  final DateTime? unreadSince;

  final void Function(TripMessage message, Rect bubbleRect)? onOpenMenu;
  final ValueChanged<TripMessage>? onImageTap;
  final ValueChanged<TripMessage>? onReactionsTap;
  final ValueChanged<TripMessage>? onSwipeReply;
  final ValueChanged<TripMessage>? onRetry;

  @override
  State<ChatMessageList> createState() => ChatMessageListState();
}

class ChatMessageListState extends State<ChatMessageList> {
  static const double _followThreshold = 80;
  static const double _jumpButtonThreshold = 320;
  static const double _loadOlderThreshold = 800;

  final _scrollController = ScrollController();
  final _rowKeys = <String, GlobalKey>{};
  final _highlightedMessageId = ValueNotifier<String?>(null);
  final _showJumpToBottom = ValueNotifier<bool>(false);
  Timer? _highlightTimer;

  /// First message that was unread when the conversation was opened.
  String? _firstUnreadId;
  bool _unreadResolved = false;

  DateFormat? _timeFormat;
  String? _timeFormatLocale;

  TripChatController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _resolveFirstUnread();
  }

  @override
  void didUpdateWidget(covariant ChatMessageList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _rowKeys.clear();
      _unreadResolved = false;
      _firstUnreadId = null;
      _resolveFirstUnread();
    }
    if (oldWidget.unreadSince != widget.unreadSince) {
      _unreadResolved = false;
      _firstUnreadId = null;
      _resolveFirstUnread();
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _highlightTimer?.cancel();
    _scrollController.dispose();
    _highlightedMessageId.dispose();
    _showJumpToBottom.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    _resolveFirstUnread();
    _rowKeys.removeWhere((id, _) => _controller.indexOfMessage(id) == null);
  }

  /// Freezes the unread marker on the first loaded content, so it does not
  /// move while the user reads.
  void _resolveFirstUnread() {
    if (_unreadResolved || _controller.isLoading) return;
    _unreadResolved = true;
    final since = widget.unreadSince;
    if (since == null) return;
    final myUid = widget.currentUserId;
    String? firstUnread;
    for (final message in _controller.messages) {
      if (!message.createdAt.isAfter(since)) break;
      if (message.authorId != myUid) firstUnread = message.id;
    }
    _firstUnreadId = firstUnread;
  }

  // ── Public actions ─────────────────────────────────────────────────────

  /// Brings the latest message into view.
  void scrollToBottom({bool animated = true}) {
    _controller.setFollowingLatest(true);
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels <= position.minScrollExtent) return;
    if (!animated || position.pixels > 3000) {
      position.jumpTo(position.minScrollExtent);
    } else {
      unawaited(position.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      ));
    }
  }

  /// Scrolls to a message and flashes it. Loads older history when needed.
  Future<void> scrollToMessage(String messageId) async {
    var attempts = 0;
    while (_controller.indexOfMessage(messageId) == null &&
        _controller.hasMoreOlder &&
        attempts < 5) {
      attempts++;
      await _controller.loadOlder();
      if (!mounted) return;
    }
    final targetIndex = _controller.indexOfMessage(messageId);
    if (targetIndex == null || !_scrollController.hasClients) return;

    // Rows are built lazily: walk towards the target until it exists.
    for (var step = 0; step < 80; step++) {
      final targetContext = _rowKeys[messageId]?.currentContext;
      if (targetContext != null) break;
      final position = _scrollController.position;
      final towardsOlder = targetIndex > (_anyBuiltIndex() ?? -1);
      final delta = position.viewportDimension * 0.9;
      final next = (position.pixels + (towardsOlder ? delta : -delta))
          .clamp(position.minScrollExtent, position.maxScrollExtent);
      if (next == position.pixels) break;
      position.jumpTo(next);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }

    final targetContext = _rowKeys[messageId]?.currentContext;
    if (targetContext == null || !targetContext.mounted) return;
    await Scrollable.ensureVisible(
      targetContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    if (!mounted) return;
    _flash(messageId);
  }

  /// Tints a message while its menu is open; null clears the tint.
  void setHighlightedMessage(String? messageId) {
    _highlightTimer?.cancel();
    _highlightedMessageId.value = messageId;
  }

  int? _anyBuiltIndex() {
    for (final entry in _rowKeys.entries) {
      if (entry.value.currentContext != null) {
        return _controller.indexOfMessage(entry.key);
      }
    }
    return null;
  }

  void _flash(String messageId) {
    _highlightTimer?.cancel();
    _highlightedMessageId.value = messageId;
    _highlightTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) _highlightedMessageId.value = null;
    });
  }

  // ── Scrolling ──────────────────────────────────────────────────────────

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final metrics = notification.metrics;
    // Reversed list: pixels grow while moving back in time.
    _controller.setFollowingLatest(metrics.pixels <= _followThreshold);
    _showJumpToBottom.value = metrics.pixels > _jumpButtonThreshold;
    if (metrics.extentAfter < _loadOlderThreshold) {
      unawaited(_controller.loadOlder());
    }
    return false;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  DateFormat _timeFormatter(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    if (_timeFormat == null || _timeFormatLocale != locale) {
      _timeFormatLocale = locale;
      _timeFormat = DateFormat.Hm(locale);
    }
    return _timeFormat!;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final l10n = AppLocalizations.of(context)!;
        final messages = _controller.messages;
        if (messages.isEmpty) {
          if (_controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _controller.hasError
                    ? l10n.chatLoadImpossible
                    : l10n.chatEmptyState,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          );
        }

        final showLoader = _controller.hasMoreOlder;
        final timeFormat = _timeFormatter(context);
        final now = DateTime.now();

        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: ListView.builder(
                controller: _scrollController,
                reverse: true,
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                itemCount: messages.length + (showLoader ? 1 : 0),
                findChildIndexCallback: (key) {
                  if (key is! ValueKey<String>) return null;
                  return _controller.indexOfMessage(key.value);
                },
                itemBuilder: (context, index) {
                  if (index >= messages.length) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    );
                  }
                  return _buildItem(
                    context,
                    messages: messages,
                    index: index,
                    timeFormat: timeFormat,
                    now: now,
                    l10n: l10n,
                  );
                },
              ),
            ),
            Positioned(
              right: 12,
              bottom: 12,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showJumpToBottom,
                builder: (context, visible, _) => _JumpToBottomButton(
                  visible: visible || _controller.heldIncomingCount > 0,
                  pendingCount: _controller.heldIncomingCount,
                  tooltip: l10n.chatGoBottom,
                  onPressed: scrollToBottom,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required List<TripMessage> messages,
    required int index,
    required DateFormat timeFormat,
    required DateTime now,
    required AppLocalizations l10n,
  }) {
    final message = messages[index];
    final older = index + 1 < messages.length ? messages[index + 1] : null;
    final newer = index > 0 ? messages[index - 1] : null;
    final createdAt = message.createdAt.toLocal();

    final startsDay =
        older == null || !_isSameDay(older.createdAt.toLocal(), createdAt);
    final startsUnread = message.id == _firstUnreadId;
    final isFirstInGroup =
        startsDay || startsUnread || older.authorId != message.authorId;
    final isLastInGroup = newer == null ||
        newer.authorId != message.authorId ||
        newer.id == _firstUnreadId ||
        !_isSameDay(newer.createdAt.toLocal(), createdAt);

    final myUid = widget.currentUserId;
    final isMine = myUid != null && message.authorId == myUid;
    final canInteract = !message.isFailed &&
        (message.sendState == TripMessageSendState.sent ||
            message.hasServerTimestamp);

    ChatQuote? quote;
    final replyId = message.replyToMessageId;
    if (replyId != null) {
      final original = _controller.quotedMessage(replyId);
      if (original != null) {
        quote = ChatQuote(
          authorLabel: _authorLabel(original.authorId),
          text: original.previewText,
          isImage: original.isImage,
        );
      }
    }

    final row = ChatMessageRow(
      key: _rowKeys.putIfAbsent(message.id, GlobalKey.new),
      message: message,
      isMine: isMine,
      isFirstInGroup: isFirstInGroup,
      isLastInGroup: isLastInGroup,
      authorLabel: _authorLabel(message.authorId),
      authorPhotoUrl: widget.memberPhotoUrls[message.authorId],
      timeLabel: timeFormat.format(createdAt),
      crossCache: widget.crossCache,
      highlightedMessageId: _highlightedMessageId,
      quote: quote,
      localImageBytes: _controller.localImageBytes(message.id),
      uploadProgress: _controller.uploadProgress(message.id),
      onOpenMenu: widget.onOpenMenu == null
          ? null
          : (rect) => widget.onOpenMenu!(message, rect),
      onImageTap: widget.onImageTap == null
          ? null
          : () => widget.onImageTap!(message),
      onQuoteTap:
          replyId == null ? null : () => unawaited(scrollToMessage(replyId)),
      onReactionsTap: widget.onReactionsTap == null
          ? null
          : () => widget.onReactionsTap!(message),
      onSwipeReply: canInteract && widget.onSwipeReply != null
          ? () => widget.onSwipeReply!(message)
          : null,
      onRetry:
          widget.onRetry == null ? null : () => widget.onRetry!(message),
    );

    if (!startsDay && !startsUnread) {
      return KeyedSubtree(key: ValueKey<String>(message.id), child: row);
    }
    return Column(
      key: ValueKey<String>(message.id),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (startsDay)
          _CenteredChip(label: _dayLabel(context, createdAt, now, l10n)),
        if (startsUnread)
          _CenteredChip(label: l10n.chatUnreadSeparator, emphasized: true),
        row,
      ],
    );
  }

  String _authorLabel(String authorId) {
    final label = widget.memberLabels[authorId]?.trim() ?? '';
    return label.isEmpty ? widget.fallbackAuthorLabel : label;
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _dayLabel(
    BuildContext context,
    DateTime day,
    DateTime now,
    AppLocalizations l10n,
  ) {
    if (_isSameDay(day, now)) return l10n.commonToday;
    if (_isSameDay(day, now.subtract(const Duration(days: 1)))) {
      return l10n.commonYesterday;
    }
    final locale = Localizations.localeOf(context).toString();
    final format = day.year == now.year
        ? DateFormat.MMMMEEEEd(locale)
        : DateFormat.yMMMMd(locale);
    return format.format(day);
  }
}

class _CenteredChip extends StatelessWidget {
  const _CenteredChip({required this.label, this.emphasized = false});

  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: emphasized
                ? scheme.primary.withValues(alpha: 0.12)
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color:
                        emphasized ? scheme.primary : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JumpToBottomButton extends StatelessWidget {
  const _JumpToBottomButton({
    required this.visible,
    required this.pendingCount,
    required this.tooltip,
    required this.onPressed,
  });

  final bool visible;
  final int pendingCount;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedScale(
        scale: visible ? 1 : 0,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        child: Badge(
          isLabelVisible: pendingCount > 0,
          label: Text(pendingCount > 99 ? '99+' : '$pendingCount'),
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 3,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: IconButton(
              tooltip: tooltip,
              icon: const Icon(PhosphorIconsRegular.arrowDown, size: 20),
              color: scheme.onSurfaceVariant,
              onPressed: onPressed,
            ),
          ),
        ),
      ),
    );
  }
}
