import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/app_version_provider.dart';
import 'package:planerz/app/update/github_release.dart';
import 'package:planerz/app/update/latest_release_provider.dart';
import 'package:planerz/app/update/version_comparison.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:url_launcher/url_launcher.dart';

/// Wraps the app shell and blocks navigation when a newer version is available
/// on GitHub. Disabled in debug builds, preview environment, and non-Android
/// platforms.
class UpdateGate extends ConsumerWidget {
  const UpdateGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPreview = ref.watch(firebaseTargetProvider).isPreview;
    if (kDebugMode || isPreview || kIsWeb || !Platform.isAndroid) return child;

    final releaseAsync = ref.watch(latestReleaseProvider);
    final currentAsync = ref.watch(appVersionProvider);

    final release = releaseAsync.asData?.value;
    final current = currentAsync.asData?.value;

    if (release != null &&
        current != null &&
        isUpdateRequired(current, release.tag)) {
      return PopScope(
        canPop: false,
        child: _UpdateRequiredScreen(current: current, release: release),
      );
    }

    return child;
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen({
    required this.current,
    required this.release,
  });

  final String current;
  final GitHubRelease release;

  Future<void> _download(BuildContext context) async {
    final uri = Uri.parse(release.apkDownloadUrl);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(height: 1.5),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _VersionRow(
                  label: l10n.updateRequiredCurrentVersion,
                  version: current,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 6),
                _VersionRow(
                  label: l10n.updateRequiredNewVersion,
                  version: release.tag,
                  color: theme.colorScheme.primary,
                  bold: true,
                ),
                const SizedBox(height: 36),
                FilledButton.icon(
                  onPressed: () => _download(context),
                  icon: const Icon(Icons.download_outlined),
                  label: Text(l10n.updateRequiredDownloadButton(release.tag)),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
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
