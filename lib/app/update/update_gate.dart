import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/app_version_provider.dart';
import 'package:planerz/app/update/android_apk_update_installer.dart';
import 'package:planerz/app/update/latest_release_provider.dart';
import 'package:planerz/app/update/remote_release.dart';
import 'package:planerz/app/update/version_comparison.dart';
import 'package:planerz/core/firebase/app_public_hosts.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Wraps the app shell and blocks navigation when a newer version is available
/// remotely (GitHub in prod, Storage manifest in preview). Disabled on web and
/// non-Android platforms.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (kIsWeb || !Platform.isAndroid) return child;

    final releaseAsync = ref.watch(latestReleaseProvider);
    final currentAsync = ref.watch(appVersionProvider);

    final release = releaseAsync.asData?.value;
    final current = currentAsync.asData?.value;

    if (release != null &&
        current != null &&
        isUpdateRequired(current, release.tag)) {
      final webAppBaseUri =
          publicAppBaseUriForTarget(ref.watch(firebaseTargetProvider));
      return PopScope(
        canPop: false,
        child: _UpdateRequiredScreen(
          key: ValueKey<String>('update_gate_${release.tag}'),
          current: current,
          release: release,
          webAppBaseUri: webAppBaseUri,
        ),
      );
    }

    return child;
  }
}

enum _UpdateUiPhase {
  downloading,
  openingInstaller,
  installerLaunched,
  errorDownload,
  errorInstaller,
}

class _UpdateRequiredScreen extends StatefulWidget {
  const _UpdateRequiredScreen({
    required this.current,
    required this.release,
    required this.webAppBaseUri,
    super.key,
  });

  final String current;
  final RemoteRelease release;
  final Uri webAppBaseUri;

  @override
  State<_UpdateRequiredScreen> createState() => _UpdateRequiredScreenState();
}

class _UpdateRequiredScreenState extends State<_UpdateRequiredScreen> {
  _UpdateUiPhase _phase = _UpdateUiPhase.downloading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runAutoUpdateFlow());
    });
  }

  Future<void> _runAutoUpdateFlow() async {
    if (!mounted) return;
    setState(() => _phase = _UpdateUiPhase.downloading);

    final apkFile = await downloadUpdateApkToCache(
      apkDownloadUrl: widget.release.apkDownloadUrl,
      releaseTag: widget.release.tag,
    );

    if (!mounted) return;

    if (apkFile == null) {
      setState(() => _phase = _UpdateUiPhase.errorDownload);
      return;
    }

    setState(() => _phase = _UpdateUiPhase.openingInstaller);

    final installOutcome = await promptAndroidApkInstall(apkFile);

    if (!mounted) return;

    switch (installOutcome) {
      case AndroidApkInstallPromptOutcome.installerPromptShown:
        setState(() => _phase = _UpdateUiPhase.installerLaunched);
      case AndroidApkInstallPromptOutcome.installerIntentFailed:
        setState(() => _phase = _UpdateUiPhase.errorInstaller);
    }
  }

  Future<void> _openDownloadUrlExternally() async {
    final uri = Uri.parse(widget.release.apkDownloadUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
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

    final showProgress = _phase == _UpdateUiPhase.downloading ||
        _phase == _UpdateUiPhase.openingInstaller;
    final showErrorActions = _phase == _UpdateUiPhase.errorDownload ||
        _phase == _UpdateUiPhase.errorInstaller;

    String? progressLabel;
    if (_phase == _UpdateUiPhase.downloading) {
      progressLabel = l10n.updateRequiredDownloading;
    } else if (_phase == _UpdateUiPhase.openingInstaller) {
      progressLabel = l10n.updateRequiredOpeningInstaller;
    }

    String? errorLabel;
    if (_phase == _UpdateUiPhase.errorDownload) {
      errorLabel = l10n.updateRequiredDownloadFailed;
    } else if (_phase == _UpdateUiPhase.errorInstaller) {
      errorLabel = l10n.updateRequiredInstallerFailed;
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.system_update_outlined,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  l10n.updateRequiredTitle,
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.updateRequiredBody,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _VersionRow(
                  label: l10n.updateRequiredCurrentVersion,
                  version: widget.current,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                _VersionRow(
                  label: l10n.updateRequiredNewVersion,
                  version: widget.release.tag,
                  color: theme.colorScheme.primary,
                  bold: true,
                ),
                const SizedBox(height: 20),
                _UpdateAutomaticWarningBanner(
                  introMessage: l10n.updateRequiredAutomaticUpdateWarningIntro,
                  webAppUri: widget.webAppBaseUri,
                ),
                const SizedBox(height: 24),
                if (showProgress) ...[
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    progressLabel ?? '',
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ],
                if (errorLabel != null) ...[
                  Text(
                    errorLabel,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                ],
                if (showErrorActions) ...[
                  FilledButton.icon(
                    onPressed: () {
                      unawaited(_runAutoUpdateFlow());
                    },
                    icon: const Icon(Icons.refresh_outlined),
                    label: Text(l10n.updateRequiredRetryButton),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () {
                      unawaited(_openDownloadUrlExternally());
                    },
                    icon: const Icon(Icons.open_in_browser_outlined),
                    label: Text(l10n.updateRequiredOpenLinkButton),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UpdateAutomaticWarningBanner extends StatelessWidget {
  const _UpdateAutomaticWarningBanner({
    required this.introMessage,
    required this.webAppUri,
  });

  final String introMessage;
  final Uri webAppUri;

  static const Color _backgroundColor = Color(0xFFFFF9E6);
  static const Color _borderColor = Color(0xFFE6C200);
  static const Color _iconColor = Color(0xFFB8860B);

  Future<void> _openWebVersion(BuildContext context) async {
    final launched = await launchUrl(
      webAppUri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface,
          height: 1.45,
          fontWeight: FontWeight.w500,
        );
    final linkStyle = bodyStyle?.copyWith(
          color: theme.colorScheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        );

    final urlLabel = webAppUri.toString();

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
            Icon(Icons.warning_amber_rounded, color: _iconColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(introMessage, style: bodyStyle),
                  const SizedBox(height: 8),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        unawaited(_openWebVersion(context));
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(urlLabel, style: linkStyle),
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

class _VersionRow extends StatelessWidget {
  const _VersionRow({
    required this.label,
    required this.version,
    required this.color,
    this.bold = false,
  });

  final String label;
  final String version;
  final Color color;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
        );
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('$label : ', style: style),
        Text(version, style: style),
      ],
    );
  }
}
