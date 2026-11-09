import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Quick reactions offered above a pressed message.
const List<String> chatQuickReactionEmojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

enum ChatMessageAction { reply, copy, edit, delete, retry }

/// What the user picked in the message menu.
@immutable
class ChatMessageMenuResult {
  const ChatMessageMenuResult.reaction(String this.emoji)
      : action = null,
        wantsMoreEmojis = false;

  const ChatMessageMenuResult.moreEmojis()
      : emoji = null,
        action = null,
        wantsMoreEmojis = true;

  const ChatMessageMenuResult.action(ChatMessageAction this.action)
      : emoji = null,
        wantsMoreEmojis = false;

  final String? emoji;
  final ChatMessageAction? action;
  final bool wantsMoreEmojis;
}

/// Handle on an open message menu.
class ChatMessageMenuHandle {
  ChatMessageMenuHandle._(this._entry, this._stateKey, this._completer);

  final OverlayEntry _entry;
  final GlobalKey<_ChatMessageMenuState> _stateKey;
  final Completer<ChatMessageMenuResult?> _completer;

  /// Completes with the user's choice, or null when the menu is dismissed.
  Future<ChatMessageMenuResult?> get result => _completer.future;

  bool get isOpen => !_completer.isCompleted;

  /// Closes the menu without a choice.
  void dismiss() => _close(null);

  void _close(ChatMessageMenuResult? result) {
    if (_completer.isCompleted) return;
    _completer.complete(result);
    final state = _stateKey.currentState;
    if (state == null) {
      _entry.remove();
      return;
    }
    unawaited(state.playClose().whenComplete(() {
      if (_entry.mounted) _entry.remove();
    }));
  }
}

/// Shows the reactions bar and the actions of a message right next to its
/// bubble ([anchor], in global coordinates).
///
/// Displayed in an overlay rather than a route so the keyboard and the text
/// being typed stay untouched.
ChatMessageMenuHandle showChatMessageMenu({
  required BuildContext context,
  required Rect anchor,
  required bool alignEnd,
  required List<ChatMessageAction> actions,
  bool showReactions = true,
  String? currentReaction,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  final stateKey = GlobalKey<_ChatMessageMenuState>();
  final completer = Completer<ChatMessageMenuResult?>();
  late final ChatMessageMenuHandle handle;
  final themes = InheritedTheme.capture(from: context, to: overlay.context);
  final entry = OverlayEntry(
    builder: (ctx) => themes.wrap(
      _ChatMessageMenu(
        key: stateKey,
        anchor: anchor,
        alignEnd: alignEnd,
        actions: actions,
        showReactions: showReactions,
        currentReaction: currentReaction,
        onResult: (result) => handle._close(result),
      ),
    ),
  );
  handle = ChatMessageMenuHandle._(entry, stateKey, completer);
  overlay.insert(entry);
  return handle;
}

class _ChatMessageMenu extends StatefulWidget {
  const _ChatMessageMenu({
    super.key,
    required this.anchor,
    required this.alignEnd,
    required this.actions,
    required this.showReactions,
    required this.currentReaction,
    required this.onResult,
  });

  final Rect anchor;
  final bool alignEnd;
  final List<ChatMessageAction> actions;
  final bool showReactions;
  final String? currentReaction;
  final ValueChanged<ChatMessageMenuResult?> onResult;

  @override
  State<_ChatMessageMenu> createState() => _ChatMessageMenuState();
}

class _ChatMessageMenuState extends State<_ChatMessageMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 140),
    reverseDuration: const Duration(milliseconds: 100),
  )..forward();

  Future<void> playClose() async {
    if (!mounted) return;
    try {
      await _animation.reverse().orCancel;
    } on TickerCanceled {
      // Removed while closing.
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final curved = CurvedAnimation(parent: _animation, curve: Curves.easeOut);
    final alignment =
        widget.alignEnd ? Alignment.centerRight : Alignment.centerLeft;

    Widget animated(Widget child) => FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.85, end: 1).animate(curved),
            alignment: alignment,
            child: child,
          ),
        );

    return ExcludeFocus(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => widget.onResult(null),
                onSecondaryTap: () => widget.onResult(null),
                child: FadeTransition(
                  opacity: curved,
                  child: const ColoredBox(color: Color(0x33000000)),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomMultiChildLayout(
                delegate: _MenuLayoutDelegate(
                  anchor: widget.anchor,
                  alignEnd: widget.alignEnd,
                  safeArea: media.padding + media.viewInsets,
                  hasReactions: widget.showReactions,
                  hasActions: widget.actions.isNotEmpty,
                ),
                children: [
                  if (widget.showReactions)
                    LayoutId(
                      id: _MenuSlot.reactions,
                      child: animated(
                        _ReactionBar(
                          currentReaction: widget.currentReaction,
                          onEmoji: (emoji) => widget.onResult(
                            ChatMessageMenuResult.reaction(emoji),
                          ),
                          onMore: () => widget.onResult(
                            const ChatMessageMenuResult.moreEmojis(),
                          ),
                        ),
                      ),
                    ),
                  if (widget.actions.isNotEmpty)
                    LayoutId(
                      id: _MenuSlot.actions,
                      child: animated(
                        _ActionsCard(
                          actions: widget.actions,
                          onAction: (action) => widget.onResult(
                            ChatMessageMenuResult.action(action),
                          ),
                        ),
                      ),
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

enum _MenuSlot { reactions, actions }

/// Places the reactions bar above the bubble and the actions below it,
/// keeping both on screen whatever the bubble position or height.
class _MenuLayoutDelegate extends MultiChildLayoutDelegate {
  _MenuLayoutDelegate({
    required this.anchor,
    required this.alignEnd,
    required this.safeArea,
    required this.hasReactions,
    required this.hasActions,
  });

  static const double _gap = 8;
  static const double _margin = 8;

  final Rect anchor;
  final bool alignEnd;
  final EdgeInsets safeArea;
  final bool hasReactions;
  final bool hasActions;

  @override
  void performLayout(Size size) {
    final loose = BoxConstraints.loose(
      Size(math.max(0, size.width - 2 * _margin), size.height),
    );
    final reactionsSize = hasReactions
        ? layoutChild(_MenuSlot.reactions, loose)
        : Size.zero;
    final actionsSize =
        hasActions ? layoutChild(_MenuSlot.actions, loose) : Size.zero;

    final top = safeArea.top + _margin;
    final bottom = size.height - safeArea.bottom - _margin;

    var actionsTop = anchor.bottom + _gap;
    if (actionsTop + actionsSize.height > bottom) {
      actionsTop = bottom - actionsSize.height;
    }
    actionsTop = math.max(top, actionsTop);

    var reactionsTop = anchor.top - _gap - reactionsSize.height;
    if (hasActions && reactionsTop + reactionsSize.height + _gap > actionsTop) {
      reactionsTop = actionsTop - _gap - reactionsSize.height;
    }
    reactionsTop = math.max(top, reactionsTop);
    if (hasReactions &&
        hasActions &&
        reactionsTop + reactionsSize.height + _gap > actionsTop) {
      actionsTop = reactionsTop + reactionsSize.height + _gap;
    }

    double left(Size child) {
      final raw = alignEnd ? anchor.right - child.width : anchor.left;
      final maxLeft = math.max(_margin, size.width - _margin - child.width);
      return raw.clamp(_margin, maxLeft);
    }

    if (hasReactions) {
      positionChild(
        _MenuSlot.reactions,
        Offset(left(reactionsSize), reactionsTop),
      );
    }
    if (hasActions) {
      positionChild(_MenuSlot.actions, Offset(left(actionsSize), actionsTop));
    }
  }

  @override
  bool shouldRelayout(covariant _MenuLayoutDelegate oldDelegate) {
    return oldDelegate.anchor != anchor ||
        oldDelegate.alignEnd != alignEnd ||
        oldDelegate.safeArea != safeArea ||
        oldDelegate.hasReactions != hasReactions ||
        oldDelegate.hasActions != hasActions;
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.currentReaction,
    required this.onEmoji,
    required this.onMore,
  });

  final String? currentReaction;
  final ValueChanged<String> onEmoji;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final current = currentReaction;
    final emojis = <String>[
      ...chatQuickReactionEmojis,
      if (current != null && !chatQuickReactionEmojis.contains(current))
        current,
    ];
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: scheme.shadow.withValues(alpha: 0.4),
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final emoji in emojis)
                Tooltip(
                  message: l10n.chatReactWithEmoji(emoji),
                  child: InkResponse(
                    canRequestFocus: false,
                    radius: 22,
                    onTap: () => onEmoji(emoji),
                    child: Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: emoji == current
                            ? scheme.primary.withValues(alpha: 0.18)
                            : null,
                      ),
                      child: Text(
                        emoji,
                        style: const TextStyle(fontSize: 24, height: 1.1),
                      ),
                    ),
                  ),
                ),
              Tooltip(
                message: l10n.chatMoreEmojis,
                child: InkResponse(
                  canRequestFocus: false,
                  radius: 22,
                  onTap: onMore,
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.onSurface.withValues(alpha: 0.08),
                      ),
                      child: Icon(
                        PhosphorIconsRegular.plus,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
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

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({required this.actions, required this.onAction});

  final List<ChatMessageAction> actions;
  final ValueChanged<ChatMessageAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 6,
      shadowColor: scheme.shadow.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 220,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final action in actions)
              InkWell(
                canRequestFocus: false,
                onTap: () => onAction(action),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          switch (action) {
                            ChatMessageAction.reply => l10n.chatReply,
                            ChatMessageAction.copy => l10n.chatCopy,
                            ChatMessageAction.edit => l10n.commonEdit,
                            ChatMessageAction.delete => l10n.commonDelete,
                            ChatMessageAction.retry => l10n.commonRetry,
                          },
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: action == ChatMessageAction.delete
                                ? scheme.error
                                : scheme.onSurface,
                          ),
                        ),
                      ),
                      Icon(
                        switch (action) {
                          ChatMessageAction.reply =>
                            PhosphorIconsRegular.arrowBendUpLeft,
                          ChatMessageAction.copy => PhosphorIconsRegular.copy,
                          ChatMessageAction.edit =>
                            PhosphorIconsRegular.pencilSimple,
                          ChatMessageAction.delete => PhosphorIconsRegular.trash,
                          ChatMessageAction.retry =>
                            PhosphorIconsRegular.arrowClockwise,
                        },
                        size: 20,
                        color: action == ChatMessageAction.delete
                            ? scheme.error
                            : scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
