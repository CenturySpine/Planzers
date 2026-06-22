import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/data/invite_code_input.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

const _inviteCodeCharCount = inviteCodeCharCount;

/// Néon-styled invite code entry dialog for [TripsPage].
Future<void> showJoinTripByCodeDialog({
  required BuildContext parentContext,
}) {
  return showDialog<void>(
    context: parentContext,
    barrierColor: NeonPalette.deep.withValues(alpha: 0.42),
    builder: (dialogRouteContext) => _JoinTripByCodeDialog(
      parentContext: parentContext,
      navigatorContext: dialogRouteContext,
    ),
  );
}

String _messageForJoinByCodeError(BuildContext context, Object e) {
  final l10n = AppLocalizations.of(context)!;
  if (e is FirebaseFunctionsException) {
    switch (e.code) {
      case 'not-found':
        return l10n.tripsJoinCodeNotFound;
      case 'permission-denied':
        return l10n.tripsJoinCodeNotValid;
      case 'invalid-argument':
        return l10n.tripsJoinCodeInvalid;
      case 'unauthenticated':
        return l10n.tripsJoinCodeUnauthenticated;
      default:
        break;
    }
    final m = e.message;
    if (m != null && m.trim().isNotEmpty) {
      return m.trim();
    }
  }
  return e.toString();
}

String _sanitizeInviteCode(String raw) => sanitizeInviteCodeInput(raw);

String _formatInviteToken(String code) => formatInviteCodeToken(code);

class _JoinTripByCodeDialog extends ConsumerStatefulWidget {
  const _JoinTripByCodeDialog({
    required this.parentContext,
    required this.navigatorContext,
  });

  final BuildContext parentContext;
  final BuildContext navigatorContext;

  @override
  ConsumerState<_JoinTripByCodeDialog> createState() =>
      _JoinTripByCodeDialogState();
}

class _JoinTripByCodeDialogState extends ConsumerState<_JoinTripByCodeDialog> {
  late final TextEditingController _codeController;
  late final FocusNode _focusNode;
  String? _error;
  bool _isSubmitting = false;

  String get _code => _codeController.text;

  bool get _canSubmit => _code.length == _inviteCodeCharCount && !_isSubmitting;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController();
    _focusNode = FocusNode(onKeyEvent: _handleKeyEvent);
    _codeController.addListener(_onCodeChanged);
    _focusNode.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _codeController
      ..removeListener(_onCodeChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (_canSubmit) {
        unawaited(_submitEnterCode());
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  void _onCodeChanged() {
    final sanitized = _sanitizeInviteCode(_codeController.text);
    if (_codeController.text != sanitized) {
      _codeController.value = TextEditingValue(
        text: sanitized,
        selection: TextSelection.collapsed(offset: sanitized.length),
      );
      return;
    }
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  Future<void> _pasteCode() async {
    final data = await Clipboard.getData('text/plain');
    final sanitized = _sanitizeInviteCode(data?.text ?? '');
    _codeController.value = TextEditingValue(
      text: sanitized,
      selection: TextSelection.collapsed(offset: sanitized.length),
    );
    if (!mounted) return;
    _focusNode.requestFocus();
    setState(() => _error = null);
  }

  Future<void> _openInviteJoinPage({
    required String tripId,
    required String token,
  }) async {
    if (!widget.navigatorContext.mounted) return;
    Navigator.of(widget.navigatorContext).pop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.parentContext.mounted) return;
      final route = Uri(
        path: '/join-with-code',
        queryParameters: <String, String>{
          'tripId': tripId,
          'token': token,
        },
      ).toString();
      widget.parentContext.go(route);
    });
  }

  Future<void> _submitEnterCode() async {
    final l10n = AppLocalizations.of(context)!;
    final code = _code;
    if (code.length != _inviteCodeCharCount) {
      setState(() => _error = l10n.tripsJoinCodeRequired);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final token = _formatInviteToken(code);
      final ctx = await ref.read(tripsRepositoryProvider).getInviteJoinContext(
            token: token,
          );
      if (!mounted) return;
      await _openInviteJoinPage(tripId: ctx.tripId, token: token);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = _messageForJoinByCodeError(context, e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasError = _error != null;
    final baseTheme = Theme.of(context);

    return Theme(
      data: NeonPalette.overlayOn(baseTheme),
      child: Dialog(
        backgroundColor: NeonPalette.surface,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 384),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: NeonPalette.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: NeonPalette.deep.withValues(alpha: 0.42),
                  blurRadius: 56,
                  spreadRadius: -16,
                  offset: const Offset(0, 28),
                ),
                BoxShadow(
                  color: NeonPalette.deep.withValues(alpha: 0.30),
                  blurRadius: 22,
                  spreadRadius: -12,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 28, 26, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: NeonPalette.primarySoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const SizedBox(
                          width: 44,
                          height: 44,
                          child: Icon(
                            Icons.confirmation_number_rounded,
                            color: NeonPalette.primary,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          l10n.tripsJoinCodeDialogTitle,
                          style: const TextStyle(
                            fontSize: 22,
                            height: 27 / 22,
                            fontWeight: FontWeight.w600,
                            color: NeonPalette.deep,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    l10n.tripsJoinCodeDialogHelp,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 20 / 14,
                      color: NeonPalette.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  _JoinCodeSegmentedInput(
                    code: _code,
                    hasError: hasError,
                    activeIndex: _focusNode.hasFocus && !_isSubmitting
                        ? _code.length.clamp(0, _inviteCodeCharCount - 1)
                        : -1,
                    focusNode: _focusNode,
                    controller: _codeController,
                    onTap: _focusNode.requestFocus,
                  ),
                  if (hasError) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 18,
                          color: NeonPalette.error,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              fontSize: 13,
                              height: 16 / 13,
                              color: NeonPalette.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (!_isSubmitting) ...[
                    const SizedBox(height: 14),
                    Center(
                      child: TextButton.icon(
                        onPressed: _pasteCode,
                        style: TextButton.styleFrom(
                          foregroundColor: NeonPalette.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        icon: const Icon(
                          Icons.content_paste_outlined,
                          size: 18,
                        ),
                        label: Text(
                          l10n.tripsJoinCodePaste,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _isSubmitting
                            ? null
                            : () => Navigator.of(widget.navigatorContext).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: NeonPalette.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          l10n.commonCancel,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _JoinCodeSubmitButton(
                        label: l10n.tripsJoinCodeAction,
                        isLoading: _isSubmitting,
                        enabled: _canSubmit,
                        onPressed: _submitEnterCode,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinCodeSegmentedInput extends StatelessWidget {
  const _JoinCodeSegmentedInput({
    required this.code,
    required this.hasError,
    required this.activeIndex,
    required this.focusNode,
    required this.controller,
    required this.onTap,
  });

  final String code;
  final bool hasError;
  final int activeIndex;
  final FocusNode focusNode;
  final TextEditingController controller;
  final VoidCallback onTap;

  static const _gap = 8.0;
  static const _cellWidth = 46.0;
  static const _cellHeight = 58.0;
  static const _dividerWidth = 12.0;
  static const _rowWidth =
      _cellWidth * _inviteCodeCharCount + _gap * 7 + _dividerWidth;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Align(
        alignment: Alignment.center,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: SizedBox(
            width: _rowWidth,
            height: _cellHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < inviteCodeSegmentSize; i++) ...[
                      if (i > 0) const SizedBox(width: _gap),
                      _JoinCodeCell(
                        char: i < code.length ? code[i] : '',
                        isActive: i == activeIndex,
                        hasError: hasError,
                      ),
                    ],
                    const SizedBox(width: _gap),
                    const _JoinCodeGroupDivider(),
                    const SizedBox(width: _gap),
                    for (var i = inviteCodeSegmentSize;
                        i < _inviteCodeCharCount;
                        i++) ...[
                      if (i > inviteCodeSegmentSize) const SizedBox(width: _gap),
                      _JoinCodeCell(
                        char: i < code.length ? code[i] : '',
                        isActive: i == activeIndex,
                        hasError: hasError,
                      ),
                    ],
                  ],
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0,
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      enableInteractiveSelection: false,
                      textCapitalization: TextCapitalization.characters,
                      keyboardType: TextInputType.text,
                      style: const TextStyle(fontSize: 24, height: 1),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _JoinCodeGroupDivider extends StatelessWidget {
  const _JoinCodeGroupDivider();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 12,
      height: _JoinCodeSegmentedInput._cellHeight,
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(NeonPalette.outline, NeonPalette.deep, 0.25),
            borderRadius: BorderRadius.all(Radius.circular(2)),
          ),
          child: SizedBox(width: 12, height: 2),
        ),
      ),
    );
  }
}

class _JoinCodeCell extends StatelessWidget {
  const _JoinCodeCell({
    required this.char,
    required this.isActive,
    required this.hasError,
  });

  final String char;
  final bool isActive;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _JoinCodeSegmentedInput._cellWidth,
      height: _JoinCodeSegmentedInput._cellHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: NeonPalette.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: NeonPalette.divider,
                width: 1.5,
              ),
            ),
            child: Center(
              child: Text(
                char,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: NeonPalette.deep,
                  height: 1,
                ),
              ),
            ),
          ),
          if (isActive)
            Positioned(
              left: -1.5,
              top: -1.5,
              right: -1.5,
              bottom: -1.5,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: NeonPalette.primary,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: NeonPalette.primary.withValues(alpha: 0.12),
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (hasError)
            Positioned(
              left: -1.5,
              top: -1.5,
              right: -1.5,
              bottom: -1.5,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: NeonPalette.error,
                      width: 2,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _JoinCodeSubmitButton extends StatelessWidget {
  const _JoinCodeSubmitButton({
    required this.label,
    required this.isLoading,
    required this.enabled,
    required this.onPressed,
  });

  final String label;
  final bool isLoading;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Material(
            color: NeonPalette.primary,
            borderRadius: BorderRadius.circular(999),
            child: InkWell(
              onTap: enabled && !isLoading ? onPressed : null,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                constraints: const BoxConstraints(minWidth: 116, minHeight: 42),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                alignment: Alignment.center,
                child: isLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ),
          if (!enabled && !isLoading)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
