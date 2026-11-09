import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/messaging/data/trip_messages_repository.dart';
import 'package:planerz/features/messaging/presentation/whatsapp_emoji_picker.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Trip chat input bar: emoji and photo buttons, growing text field and send
/// button. An optional [banner] sits on top while replying or editing.
class TripChatComposer extends StatefulWidget {
  const TripChatComposer({
    super.key,
    required this.textController,
    required this.focusNode,
    required this.onSend,
    this.onAttachmentTap,
    this.banner,
    this.isEditing = false,
  });

  final TextEditingController textController;
  final FocusNode focusNode;

  /// Called with the trimmed, non-empty text. The composer clears the field.
  final ValueChanged<String> onSend;

  /// Hidden when null (e.g. while editing a message).
  final VoidCallback? onAttachmentTap;
  final Widget? banner;
  final bool isEditing;

  static const double _emojiPickerHeight = 256;

  static const _fieldBorder = OutlineInputBorder(
    borderSide: BorderSide.none,
    borderRadius: BorderRadius.all(Radius.circular(24)),
  );

  @override
  State<TripChatComposer> createState() => _TripChatComposerState();
}

class _TripChatComposerState extends State<TripChatComposer> {
  final _textScrollController = ScrollController();
  late final ValueNotifier<bool> _hasText;
  bool _emojiPickerVisible = false;

  /// The emoji panel is costly to build: only create it once it is needed.
  bool _emojiPickerBuilt = false;

  @override
  void initState() {
    super.initState();
    _hasText = ValueNotifier(widget.textController.text.trim().isNotEmpty);
    widget.textController.addListener(_handleTextChange);
    widget.focusNode.addListener(_handleFocusChange);
    widget.focusNode.onKeyEvent = _handleKeyEvent;
  }

  @override
  void dispose() {
    widget.textController.removeListener(_handleTextChange);
    widget.focusNode.removeListener(_handleFocusChange);
    widget.focusNode.onKeyEvent = null;
    _hasText.dispose();
    _textScrollController.dispose();
    super.dispose();
  }

  /// On phones and tablets (native or mobile browser), Enter inserts a new
  /// line and messages are sent with the send button. On computers, Enter
  /// sends and Shift+Enter inserts a new line.
  static bool get _enterSendsMessage => switch (defaultTargetPlatform) {
        TargetPlatform.android ||
        TargetPlatform.iOS ||
        TargetPlatform.fuchsia =>
          false,
        TargetPlatform.linux ||
        TargetPlatform.macOS ||
        TargetPlatform.windows =>
          true,
      };

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_enterSendsMessage &&
        event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed) {
      _submit();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _handleTextChange() {
    _hasText.value = widget.textController.text.trim().isNotEmpty;
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus && _emojiPickerVisible) {
      setState(() => _emojiPickerVisible = false);
    }
  }

  void _toggleEmojiPicker() {
    setState(() {
      _emojiPickerVisible = !_emojiPickerVisible;
      _emojiPickerBuilt = true;
    });
    if (_emojiPickerVisible) {
      widget.focusNode.unfocus();
    } else {
      widget.focusNode.requestFocus();
    }
  }

  void _submit() {
    final text = widget.textController.text.trim();
    if (text.isEmpty) return;
    widget.textController.clear();
    widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final iconColor = scheme.onSurfaceVariant;
    final onAttachmentTap = widget.onAttachmentTap;
    final textStyle = theme.textTheme.bodyLarge?.copyWith(
      color: scheme.onSurface,
    );

    return Material(
      color: scheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.banner != null) widget.banner!,
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    icon: Icon(
                      _emojiPickerVisible
                          ? PhosphorIconsRegular.keyboard
                          : PhosphorIconsRegular.smiley,
                    ),
                    color: iconColor,
                    tooltip: l10n.chatInsertEmoji,
                    onPressed: _toggleEmojiPicker,
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.textController,
                      scrollController: _textScrollController,
                      focusNode: widget.focusNode,
                      style: textStyle,
                      decoration: InputDecoration(
                        hintText: l10n.chatMessageHint,
                        hintStyle: textStyle?.copyWith(
                          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 11,
                        ),
                        border: TripChatComposer._fieldBorder,
                        enabledBorder: TripChatComposer._fieldBorder,
                        focusedBorder: TripChatComposer._fieldBorder,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        hoverColor: Colors.transparent,
                      ),
                      textInputAction: TextInputAction.newline,
                      textCapitalization: TextCapitalization.sentences,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 6,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(
                          TripMessagesRepository.maxTextLength,
                        ),
                      ],
                    ),
                  ),
                  if (onAttachmentTap != null)
                    IconButton(
                      icon: const Icon(PhosphorIconsRegular.camera),
                      color: iconColor,
                      tooltip: l10n.chatQuotedImage,
                      onPressed: onAttachmentTap,
                    )
                  else
                    const SizedBox(width: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: _hasText,
                    builder: (context, hasText, _) {
                      return IconButton.filled(
                        icon: Icon(
                          widget.isEditing
                              ? PhosphorIconsRegular.check
                              : PhosphorIconsFill.paperPlaneRight,
                          size: 20,
                        ),
                        tooltip:
                            widget.isEditing ? l10n.commonSave : l10n.chatSend,
                        onPressed: hasText ? _submit : null,
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_emojiPickerBuilt)
              Offstage(
                offstage: !_emojiPickerVisible,
                child: PlanerzWhatsAppEmojiPicker(
                  textEditingController: widget.textController,
                  scrollController: _textScrollController,
                  height: TripChatComposer._emojiPickerHeight,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
