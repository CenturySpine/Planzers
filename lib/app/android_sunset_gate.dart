import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/app_public_hosts.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

typedef IsAndroidCheckFn = bool Function();

/// Wraps the app shell and shows a blocking sunset screen on Android native
/// builds, redirecting users to the web app. Transparent on web and all other
/// platforms.
class AndroidSunsetGate extends ConsumerWidget {
  const AndroidSunsetGate({
    required this.child,
    this.isAndroidCheck = _defaultIsAndroidCheck,
    super.key,
  });

  final Widget child;
  final IsAndroidCheckFn isAndroidCheck;

  static bool _defaultIsAndroidCheck() => Platform.isAndroid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb || !isAndroidCheck()) return child;

    final webAppUri =
        publicAppBaseUriForTarget(ref.watch(firebaseTargetProvider));
    return PopScope(
      canPop: false,
      child: _AndroidSunsetScreen(webAppUri: webAppUri),
    );
  }
}

class _AndroidSunsetScreen extends StatelessWidget {
  const _AndroidSunsetScreen({required this.webAppUri});

  final Uri webAppUri;

  Future<void> _openWeb(BuildContext context) async {
    final launched =
        await launchUrl(webAppUri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/app_icon.png',
                  width: 96,
                  height: 96,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.androidSunsetTitle,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.androidSunsetBody,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _PwaHintBox(hint: l10n.androidSunsetPwaHint),
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () => _openWeb(context),
                  child: Text(
                    webAppUri.host,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: theme.colorScheme.primary,
                    ),
                    textAlign: TextAlign.center,
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

class _PwaHintBox extends StatelessWidget {
  const _PwaHintBox({required this.hint});

  final String hint;

  static const Color _backgroundColor = Color(0xFFEEF4FF);
  static const Color _borderColor = Color(0xFF90B0FF);
  static const Color _iconColor = Color(0xFF4060CC);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor, width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: _iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
