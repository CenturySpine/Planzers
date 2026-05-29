import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';
import 'package:flutter_chat_ui/flutter_chat_ui.dart';
import 'package:planerz/features/messaging/presentation/whatsapp_emoji_picker.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

/// Trip chat composer: emoji + image buttons, flyer [Composer] send/height behavior.
class TripChatComposer extends StatefulWidget {
  const TripChatComposer({
    super.key,
    this.topWidget,
    this.hintText,
    this.attachmentIcon,
    this.attachmentEnabled = true,
    this.maxLines = 5,
    this.minLines = 1,
    this.textCapitalization = TextCapitalization.sentences,
  });

  final Widget? topWidget;
  final String? hintText;
  final Widget? attachmentIcon;
  final bool attachmentEnabled;
  final int maxLines;
  final int minLines;
  final TextCapitalization textCapitalization;

  static const double _emojiPickerHeight = 256;

  @override
  State<TripChatComposer> createState() => _TripChatComposerState();
}

class _TripChatComposerState extends State<TripChatComposer> {
  final _key = GlobalKey();
  late final TextEditingController _textController;
  late final ScrollController _textScrollController;
  late final FocusNode _focusNode;
  late final ValueNotifier<bool> _hasTextNotifier;
  bool _emojiPickerVisible = false;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _textScrollController = ScrollController();
    _focusNode = FocusNode();
    _hasTextNotifier = ValueNotifier(_textController.text.trim().isNotEmpty);
    _focusNode.onKeyEvent = _handleKeyEvent;
    _focusNode.addListener(_handleFocusChange);
    _textController.addListener(_handleTextControllerChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _handleSubmitted(_textController.text);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  void didUpdateWidget(covariant TripChatComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus && _emojiPickerVisible) {
      setState(() => _emojiPickerVisible = false);
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }
  }

  @override
  void dispose() {
    _hasTextNotifier.dispose();
    _focusNode.removeListener(_handleFocusChange);
    _textController.removeListener(_handleTextControllerChange);
    _textController.dispose();
    _textScrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleEmojiPicker() {
    setState(() {
      _emojiPickerVisible = !_emojiPickerVisible;
      if (_emojiPickerVisible) {
        _focusNode.unfocus();
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    final onAttachmentTap = context.read<OnAttachmentTapCallback?>();
    final theme = context.select(
      (ChatTheme t) => (
        bodyMedium: t.typography.bodyMedium,
        onSurface: t.colors.onSurface,
        surfaceContainerLow: t.colors.surfaceContainerLow,
        surfaceContainerHigh: t.colors.surfaceContainerHigh,
      ),
    );
    final iconMuted = theme.onSurface.withValues(alpha: 0.5);

    final content = Container(
      key: _key,
      color: theme.surfaceContainerLow,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.topWidget != null) widget.topWidget!,
          Padding(
            padding: EdgeInsets.fromLTRB(8, 8, 8, 8 + bottomSafeArea),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  icon: Icon(
                    _emojiPickerVisible
                        ? Icons.keyboard_outlined
                        : Icons.emoji_emotions_outlined,
                  ),
                  color: iconMuted,
                  tooltip: l10n.chatInsertEmoji,
                  onPressed: _toggleEmojiPicker,
                ),
                if (widget.attachmentIcon != null && onAttachmentTap != null)
                  IconButton(
                    icon: widget.attachmentIcon!,
                    color: iconMuted,
                    onPressed:
                        widget.attachmentEnabled ? onAttachmentTap : null,
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: TextField(
                    controller: _textController,
                    scrollController: _textScrollController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      hintText: widget.hintText ?? l10n.chatMessageHint,
                      hintStyle: theme.bodyMedium.copyWith(color: iconMuted),
                      border: const OutlineInputBorder(
                        borderSide: BorderSide.none,
                        borderRadius: BorderRadius.all(Radius.circular(24)),
                      ),
                      filled: true,
                      fillColor: theme.surfaceContainerHigh
                          .withValues(alpha: 0.8),
                      hoverColor: Colors.transparent,
                    ),
                    style: theme.bodyMedium.copyWith(
                      color: theme.onSurface,
                    ),
                    onSubmitted: _handleSubmitted,
                    onChanged: (value) {
                      _hasTextNotifier.value = value.trim().isNotEmpty;
                    },
                    textInputAction: TextInputAction.newline,
                    autocorrect: true,
                    textCapitalization: widget.textCapitalization,
                    keyboardType: TextInputType.multiline,
                    minLines: widget.minLines,
                    maxLines: widget.maxLines,
                  ),
                ),
                const SizedBox(width: 4),
                ValueListenableBuilder<bool>(
                  valueListenable: _hasTextNotifier,
                  builder: (context, hasText, child) {
                    return IconButton(
                      icon: const Icon(Icons.send),
                      color: hasText ? iconMuted : iconMuted.withValues(alpha: 0.35),
                      tooltip: l10n.chatSend,
                      onPressed: hasText
                          ? () => _handleSubmitted(_textController.text)
                          : null,
                    );
                  },
                ),
              ],
            ),
          ),
          Offstage(
            offstage: !_emojiPickerVisible,
            child: PlanerzWhatsAppEmojiPicker(
              textEditingController: _textController,
              scrollController: _textScrollController,
              height: TripChatComposer._emojiPickerHeight,
            ),
          ),
        ],
      ),
    );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRect(
        child: content,
      ),
    );
  }

  void _measure() {
    if (!mounted) return;
    final renderBox = _key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final height = renderBox.size.height;
    final bottomSafeArea = MediaQuery.paddingOf(context).bottom;
    context.read<ComposerHeightNotifier>().setHeight(height - bottomSafeArea);
  }

  void _handleTextControllerChange() {
    _hasTextNotifier.value = _textController.text.trim().isNotEmpty;
  }

  void _handleSubmitted(String text) {
    if (text.trim().isEmpty) return;
    context.read<OnMessageSendCallback?>()?.call(text.trim());
    _textController.clear();
    if (_emojiPickerVisible) {
      setState(() => _emojiPickerVisible = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
  }
}
