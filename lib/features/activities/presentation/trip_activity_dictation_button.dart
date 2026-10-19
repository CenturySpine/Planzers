import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Microphone button that dictates into [controller], after the text already
/// typed. Uses the browser speech recognition on the web and the system one
/// on Android and iOS; hidden where dictation is not supported.
class TripActivityDictationButton extends StatefulWidget {
  const TripActivityDictationButton({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.onListeningChanged,
    this.enabled = true,
  });

  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<bool> onListeningChanged;
  final bool enabled;

  @override
  State<TripActivityDictationButton> createState() =>
      _TripActivityDictationButtonState();
}

class _TripActivityDictationButtonState
    extends State<TripActivityDictationButton> {
  /// Errors meaning the microphone cannot be used (denied or missing); the
  /// others (silence, nothing understood...) just end the dictation.
  static const _microphoneErrors = {
    'error_permission',
    'error_audio_error',
    'not-allowed',
    'service-not-allowed',
    'audio-capture',
  };

  final SpeechToText _speech = SpeechToText();

  /// The web check prompts nothing, so the button stays hidden until the
  /// browser is known to support dictation. On mobile, the microphone
  /// permission is only asked on the first tap.
  bool _available = !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool _listening = false;
  String _prefix = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _initialize().then((available) {
        if (mounted) setState(() => _available = available);
      });
    }
  }

  @override
  void dispose() {
    if (_listening) _speech.cancel();
    if (_speech.statusListener == _onStatus) {
      _speech.statusListener = null;
      _speech.errorListener = null;
    }
    super.dispose();
  }

  Future<bool> _initialize() async {
    final available =
        await _speech.initialize(onStatus: _onStatus, onError: _onError);
    // The plugin is shared and keeps the listeners of its first
    // initialisation: point them at this button.
    _speech.statusListener = _onStatus;
    _speech.errorListener = _onError;
    return available;
  }

  Future<void> _toggle() async {
    if (_listening) {
      await _speech.stop();
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final localeId = Localizations.localeOf(context).languageCode == 'en'
        ? 'en-US'
        : 'fr-FR';
    // On Android and iOS, this is where the microphone permission is asked.
    if (!await _initialize()) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.activitiesAiTextDictationUnavailable)),
      );
      return;
    }
    if (!mounted) return;
    _prefix = widget.controller.text.trim();
    _setListening(true);
    try {
      await _speech.listen(
        onResult: _onResult,
        listenOptions: SpeechListenOptions(
          localeId: localeId,
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
          listenFor: const Duration(minutes: 1),
          pauseFor: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      _setListening(false);
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.activitiesAiTextDictationUnavailable)),
      );
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!mounted) return;
    var text = [_prefix, result.recognizedWords.trim()]
        .where((part) => part.isNotEmpty)
        .join(' ');
    if (text.length > widget.maxLength) {
      text = text.substring(0, widget.maxLength);
    }
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _onStatus(String status) {
    if (!mounted) return;
    _setListening(status == SpeechToText.listeningStatus);
  }

  void _onError(SpeechRecognitionError error) {
    if (!mounted) return;
    _setListening(false);
    if (_microphoneErrors.contains(error.errorMsg)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.activitiesAiTextDictationUnavailable,
          ),
        ),
      );
    }
  }

  void _setListening(bool listening) {
    if (listening == _listening) return;
    setState(() => _listening = listening);
    widget.onListeningChanged(listening);
  }

  @override
  Widget build(BuildContext context) {
    if (!_available) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final onPressed = widget.enabled || _listening ? _toggle : null;
    const icon = Icon(PhosphorIconsRegular.microphone);
    return _listening
        ? IconButton.filled(
            tooltip: l10n.activitiesAiTextDictationStop,
            onPressed: onPressed,
            icon: icon,
          )
        : IconButton(
            tooltip: l10n.activitiesAiTextDictation,
            onPressed: onPressed,
            icon: icon,
          );
  }
}
