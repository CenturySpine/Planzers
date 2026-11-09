import 'dart:async';

import 'package:cross_cache/cross_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/messaging/chat_controller/trip_chat_controller.dart';
import 'package:planerz/features/messaging/data/trip_message.dart';
import 'package:planerz/features/messaging/presentation/chat_image_send_page.dart';
import 'package:planerz/features/messaging/presentation/chat_image_viewer.dart';
import 'package:planerz/features/messaging/presentation/chat_message_list.dart';
import 'package:planerz/features/messaging/presentation/chat_message_menu.dart';
import 'package:planerz/features/messaging/presentation/chat_reactions_sheet.dart';
import 'package:planerz/features/messaging/presentation/reply_widgets.dart';
import 'package:planerz/features/messaging/presentation/trip_chat_composer.dart';
import 'package:planerz/features/messaging/presentation/whatsapp_emoji_picker.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// A full conversation: message list, input bar and every action on a
/// message (react, reply, copy, edit, delete, retry).
///
/// Knows nothing about where messages come from: everything goes through
/// [controller].
class ChatThreadView extends StatefulWidget {
  const ChatThreadView({
    super.key,
    required this.controller,
    required this.currentUserId,
    required this.memberLabels,
    required this.memberPhotoUrls,
    required this.fallbackAuthorLabel,
    this.unreadSince,
    this.pickImage,
    this.crossCache,
  });

  final TripChatController controller;
  final String? currentUserId;
  final Map<String, String> memberLabels;
  final Map<String, String> memberPhotoUrls;
  final String fallbackAuthorLabel;
  final DateTime? unreadSince;

  /// Lets the user choose a photo to send. The photo button is hidden when
  /// null.
  final Future<ChatOutgoingImage?> Function(BuildContext context)? pickImage;

  /// Image cache to use; the view creates its own when null.
  final CrossCache? crossCache;

  @override
  State<ChatThreadView> createState() => _ChatThreadViewState();
}

class _ChatThreadViewState extends State<ChatThreadView> {
  final _listKey = GlobalKey<ChatMessageListState>();
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  CrossCache? _ownCrossCache;

  String? _replyToId;
  String? _editingId;
  String _draftBeforeEdit = '';
  ChatMessageMenuHandle? _menu;

  TripChatController get _controller => widget.controller;

  CrossCache get _crossCache =>
      widget.crossCache ?? (_ownCrossCache ??= CrossCache());

  @override
  void dispose() {
    _menu?.dismiss();
    _ownCrossCache?.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  String _authorLabel(String authorId) {
    final label = widget.memberLabels[authorId]?.trim() ?? '';
    return label.isEmpty ? widget.fallbackAuthorLabel : label;
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  // ── Composer ───────────────────────────────────────────────────────────

  void _handleSend(String text) {
    final l10n = AppLocalizations.of(context)!;
    final editingId = _editingId;
    if (editingId != null) {
      _stopEditing(restoreDraft: true);
      unawaited(
        _controller.editText(editingId, text).catchError((Object e) {
          _showError(l10n.chatEditImpossible(e.toString()));
        }),
      );
      return;
    }
    _controller.sendText(text, replyToMessageId: _replyToId);
    if (_replyToId != null) setState(() => _replyToId = null);
    _listKey.currentState?.scrollToBottom();
  }

  Future<void> _handleAttachment() async {
    final pickImage = widget.pickImage;
    if (pickImage == null) return;
    final image = await pickImage(context);
    if (image == null || !mounted) return;
    _controller.sendImage(
      bytes: image.bytes,
      fileExt: image.fileExt,
      caption: image.caption,
      imageWidth: image.width,
      imageHeight: image.height,
      replyToMessageId: _replyToId,
    );
    if (_replyToId != null) setState(() => _replyToId = null);
    _listKey.currentState?.scrollToBottom();
  }

  void _startReply(TripMessage message) {
    if (_editingId != null) _stopEditing(restoreDraft: true);
    setState(() => _replyToId = message.id);
    _focusNode.requestFocus();
  }

  void _startEditing(TripMessage message) {
    if (_editingId == null) _draftBeforeEdit = _textController.text;
    setState(() {
      _editingId = message.id;
      _replyToId = null;
    });
    _textController.value = TextEditingValue(
      text: message.text,
      selection: TextSelection.collapsed(offset: message.text.length),
    );
    _focusNode.requestFocus();
  }

  void _stopEditing({required bool restoreDraft}) {
    if (_editingId == null) return;
    setState(() => _editingId = null);
    if (restoreDraft) {
      _textController.value = TextEditingValue(
        text: _draftBeforeEdit,
        selection: TextSelection.collapsed(offset: _draftBeforeEdit.length),
      );
    }
    _draftBeforeEdit = '';
  }

  // ── Message actions ────────────────────────────────────────────────────

  Future<void> _openMenu(TripMessage message, Rect bubbleRect) async {
    _menu?.dismiss();
    final myUid = widget.currentUserId;
    final isMine = myUid != null && message.authorId == myUid;
    final isConfirmed = !message.isFailed && message.hasServerTimestamp;

    final actions = <ChatMessageAction>[
      if (message.isFailed) ...[
        ChatMessageAction.retry,
        ChatMessageAction.delete,
      ] else ...[
        if (isConfirmed) ChatMessageAction.reply,
        if (message.text.isNotEmpty) ChatMessageAction.copy,
        if (isConfirmed && isMine && !message.isImage) ChatMessageAction.edit,
        if (isConfirmed && isMine) ChatMessageAction.delete,
      ],
    ];
    if (actions.isEmpty && !isConfirmed) return;

    final handle = showChatMessageMenu(
      context: context,
      anchor: bubbleRect,
      alignEnd: isMine,
      actions: actions,
      showReactions: isConfirmed,
      currentReaction: myUid == null ? null : message.reactionsByUser[myUid],
    );
    setState(() => _menu = handle);
    _listKey.currentState?.setHighlightedMessage(message.id);

    final result = await handle.result;
    if (!mounted) return;
    if (identical(_menu, handle)) {
      setState(() => _menu = null);
      _listKey.currentState?.setHighlightedMessage(null);
    }
    if (result == null) return;

    final emoji = result.emoji;
    if (emoji != null) {
      _toggleReaction(message.id, emoji);
    } else if (result.wantsMoreEmojis) {
      final picked = await showPlanerzEmojiReactionPicker(context);
      if (picked == null || !mounted) return;
      _toggleReaction(message.id, picked);
    } else {
      switch (result.action!) {
        case ChatMessageAction.reply:
          _startReply(message);
        case ChatMessageAction.copy:
          await _copy(message);
        case ChatMessageAction.edit:
          _startEditing(message);
        case ChatMessageAction.delete:
          if (message.isFailed) {
            _controller.discardFailed(message.id);
          } else {
            await _confirmAndDelete(message);
          }
        case ChatMessageAction.retry:
          _controller.retry(message.id);
      }
    }
  }

  void _toggleReaction(String messageId, String emoji) {
    final l10n = AppLocalizations.of(context)!;
    unawaited(HapticFeedback.selectionClick());
    unawaited(
      _controller.toggleReaction(messageId, emoji).catchError((Object e) {
        _showError(l10n.chatReactionImpossible(e.toString()));
      }),
    );
  }

  Future<void> _copy(TripMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    await Clipboard.setData(ClipboardData(text: message.text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.chatCopied)),
    );
  }

  Future<void> _confirmAndDelete(TripMessage message) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(l10n.chatDeleteMessageConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    if (_replyToId == message.id) setState(() => _replyToId = null);
    if (_editingId == message.id) _stopEditing(restoreDraft: true);
    unawaited(
      _controller.deleteMessage(message.id).catchError((Object e) {
        _showError(l10n.chatDeleteImpossible(e.toString()));
      }),
    );
  }

  Future<void> _showReactions(TripMessage message) async {
    final myUid = widget.currentUserId;
    final removeMine = await showChatReactionsSheet(
      context: context,
      reactionsByUser: message.reactionsByUser,
      memberLabels: widget.memberLabels,
      memberPhotoUrls: widget.memberPhotoUrls,
      fallbackAuthorLabel: widget.fallbackAuthorLabel,
      currentUserId: myUid,
    );
    if (!removeMine || !mounted || myUid == null) return;
    final myEmoji = message.reactionsByUser[myUid];
    if (myEmoji != null) _toggleReaction(message.id, myEmoji);
  }

  void _openImage(TripMessage message) {
    final localBytes = _controller.localImageBytes(message.id);
    unawaited(
      showChatImageViewer(
        context: context,
        imageUrl: localBytes == null ? message.imageUrl : null,
        imageProvider: localBytes != null ? MemoryImage(localBytes) : null,
        crossCache: _crossCache,
        caption: message.text,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────

  Widget? _buildBanner(AppLocalizations l10n) {
    final editingId = _editingId;
    if (editingId != null) {
      final message = _controller.messageById(editingId);
      return ComposerContextBanner(
        icon: PhosphorIconsRegular.pencilSimple,
        title: l10n.chatEditMessageTitle,
        text: message?.text ?? '',
        onCancel: () => _stopEditing(restoreDraft: true),
      );
    }
    final replyToId = _replyToId;
    if (replyToId != null) {
      final message = _controller.messageById(replyToId);
      if (message == null) return null;
      return ComposerContextBanner(
        icon: PhosphorIconsRegular.arrowBendUpLeft,
        title: _authorLabel(message.authorId),
        text: message.previewText,
        isImage: message.isImage,
        onCancel: () => setState(() => _replyToId = null),
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isEditing = _editingId != null;
    return PopScope(
      canPop: _menu == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _menu?.dismiss();
      },
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                const Positioned.fill(child: _ChatBackground()),
                ChatMessageList(
                  key: _listKey,
                  controller: _controller,
                  currentUserId: widget.currentUserId,
                  memberLabels: widget.memberLabels,
                  memberPhotoUrls: widget.memberPhotoUrls,
                  fallbackAuthorLabel: widget.fallbackAuthorLabel,
                  crossCache: _crossCache,
                  unreadSince: widget.unreadSince,
                  onOpenMenu: (message, rect) =>
                      unawaited(_openMenu(message, rect)),
                  onImageTap: _openImage,
                  onReactionsTap: (message) =>
                      unawaited(_showReactions(message)),
                  onSwipeReply: _startReply,
                  onRetry: (message) => _controller.retry(message.id),
                ),
              ],
            ),
          ),
          // Rebuilt with the conversation so the banner follows the message
          // it refers to (edited or deleted meanwhile).
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => TripChatComposer(
              textController: _textController,
              focusNode: _focusNode,
              onSend: _handleSend,
              onAttachmentTap: isEditing || widget.pickImage == null
                  ? null
                  : () => unawaited(_handleAttachment()),
              banner: _buildBanner(l10n),
              isEditing: isEditing,
            ),
          ),
        ],
      ),
    );
  }
}

/// Faint doodle pattern behind the conversation. It stays still while the
/// messages scroll over it.
class _ChatBackground extends StatelessWidget {
  const _ChatBackground();

  /// Asset pixels per logical pixel: one tile is about 430 wide on screen.
  static const double _assetScale = 2.8;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeSemantics(
        child: Image.asset(
          'assets/images/chat_background.png',
          scale: _assetScale,
          fit: BoxFit.none,
          repeat: ImageRepeat.repeat,
          alignment: Alignment.topCenter,
          // The asset only carries the drawing shape: its colour comes from
          // the theme.
          color: Theme.of(context).colorScheme.primary,
          colorBlendMode: BlendMode.srcIn,
          opacity: const AlwaysStoppedAnimation(0.09),
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
