import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/features/account/data/account_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/cupidon/data/cupidon_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

class CupidonSpacePage extends ConsumerStatefulWidget {
  const CupidonSpacePage({super.key});

  @override
  ConsumerState<CupidonSpacePage> createState() => _CupidonSpacePageState();
}

class _CupidonSpacePageState extends ConsumerState<CupidonSpacePage> {
  bool _updatingDefault = false;
  final Set<String> _deletingMatchIds = <String>{};

  Future<void> _clearCupidonUnread() async {
    try {
      await ref
          .read(notificationCenterRepositoryProvider)
          .reconcileMyCupidonCountersFromServer();
    } catch (_) {
      // Keep page usable even if counter cleanup fails transiently.
    }
    ref.invalidate(cupidonGlobalUnreadCountProvider);
    ref.invalidate(globalUnreadCountProvider);
  }

  @override
  void initState() {
    super.initState();
    unawaited(_clearCupidonUnread());
  }

  Future<void> _updateDefaultCupidonEnabled(bool enabled) async {
    final l10n = AppLocalizations.of(context)!;
    if (_updatingDefault) return;
    setState(() => _updatingDefault = true);
    try {
      await ref
          .read(accountRepositoryProvider)
          .updateCupidonEnabledByDefaultPreference(enabled);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? l10n.cupidonDefaultEnabled
                  : l10n.cupidonDefaultDisabled,
            ),
            duration: const Duration(milliseconds: 1100),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPreferenceUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _updatingDefault = false);
    }
  }

  Future<void> _confirmAndDeleteMatch(CupidonMatchEntry match) async {
    final l10n = AppLocalizations.of(context)!;
    final cleanId = match.matchId.trim();
    if (cleanId.isEmpty || _deletingMatchIds.contains(cleanId)) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cupidonDeleteMatchTitle),
        content: Text(
          l10n.cupidonDeleteMatchBody(match.otherMemberLabel, match.tripTitle),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _deletingMatchIds.add(cleanId));
    try {
      await ref.read(cupidonRepositoryProvider).deleteMyMatch(cleanId);
      await _clearCupidonUnread();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripsDeleteError(e.toString()))),
      );
    } finally {
      if (mounted) setState(() => _deletingMatchIds.remove(cleanId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final defaultCupidonAsync = ref.watch(cupidonEnabledByDefaultProvider);
    final matchesAsync = ref.watch(myCupidonMatchesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.accountCupidonSpace)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: defaultCupidonAsync.when(
                data: (enabled) => SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged:
                      _updatingDefault ? null : _updateDefaultCupidonEnabled,
                  title: Text(l10n.cupidonEnableByDefaultTitle),
                  subtitle: Text(
                    l10n.cupidonEnableByDefaultSubtitle,
                  ),
                ),
                loading: () => const SizedBox(
                  height: 70,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) =>
                    Text(l10n.cupidonPreferenceLoadError(e.toString())),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.cupidonMyMatches,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          matchesAsync.when(
            data: (matches) {
              if (matches.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(l10n.cupidonNoMatches),
                  ),
                );
              }
              return Column(
                children: matches.map((match) {
                  final isDeleting = _deletingMatchIds.contains(match.matchId);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: _ProfileBadge(
                          label: match.otherMemberLabel,
                          photoUrl: match.otherMemberPhotoUrl,
                        ),
                        title: Text(match.otherMemberLabel),
                        subtitle: Text(
                          '${match.tripTitle} · ${_formatMatchDate(match.createdAt)}',
                        ),
                        trailing: IconButton(
                          tooltip: l10n.cupidonDeleteMatchTooltip,
                          onPressed: isDeleting
                              ? null
                              : () => _confirmAndDeleteMatch(match),
                          icon: isDeleting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.delete, color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.cupidonMatchesLoadError(e.toString())),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatMatchDate(DateTime value) {
    final d = value.toLocal();
    final day = d.day.toString().padLeft(2, '0');
    final month = d.month.toString().padLeft(2, '0');
    final year = d.year.toString();
    return '$day/$month/$year';
  }
}

class _ProfileBadge extends StatelessWidget {
  const _ProfileBadge({
    required this.label,
    required this.photoUrl,
  });

  final String label;
  final String photoUrl;

  @override
  Widget build(BuildContext context) {
    final cleanPhotoUrl = photoUrl.trim();
    final initial = avatarInitialFromDisplayLabel(label);
    return CircleAvatar(
      foregroundImage:
          cleanPhotoUrl.isEmpty ? null : NetworkImage(cleanPhotoUrl),
      child: Text(initial),
    );
  }
}
