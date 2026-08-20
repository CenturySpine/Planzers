import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/oauth/data/external_connection_repository.dart';
import 'package:planerz/features/trips/data/traveler_modules_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

const String kRidgegearProviderId = 'ridgegear';

/// Opens the Ridgegear project picker for [tripId] — the Planerz-owned UI
/// on top of Ridgegear's `/v1/projects` API (see the plan: the *consumer*
/// builds this screen, the provider only exposes protected data).
Future<void> showRidgegearProjectPicker(
  BuildContext context, {
  required String tripId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: NeonPalette.surface,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => _RidgegearProjectPickerSheet(tripId: tripId),
  );
}

class _RidgegearProject {
  const _RidgegearProject({
    required this.id,
    required this.name,
    required this.date,
    required this.endDate,
  });

  final String id;
  final String name;
  final String date;
  final String endDate;

  factory _RidgegearProject.fromMap(Map<String, dynamic> map) {
    return _RidgegearProject(
      id: (map['id'] as String?)?.trim() ?? '',
      name: (map['name'] as String?)?.trim() ?? '',
      date: (map['date'] as String?)?.trim() ?? '',
      endDate: (map['endDate'] as String?)?.trim() ?? '',
    );
  }
}

class _RidgegearProjectPickerSheet extends ConsumerStatefulWidget {
  const _RidgegearProjectPickerSheet({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_RidgegearProjectPickerSheet> createState() =>
      _RidgegearProjectPickerSheetState();
}

class _RidgegearProjectPickerSheetState
    extends ConsumerState<_RidgegearProjectPickerSheet> {
  late Future<List<_RidgegearProject>> _projectsFuture;
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    _projectsFuture = _loadProjects();
  }

  Future<List<_RidgegearProject>> _loadProjects() async {
    final data = await ref
        .read(externalConnectionRepositoryProvider)
        .callProviderApi(providerId: kRidgegearProviderId, path: '/v1/projects');
    final projects = (data['projects'] as List?) ?? const [];
    return projects
        .map((p) => _RidgegearProject.fromMap(p as Map<String, dynamic>))
        .toList();
  }

  Future<void> _select(_RidgegearProject project) async {
    if (_selecting) return;
    setState(() => _selecting = true);
    try {
      await ref.read(travelerModulesRepositoryProvider).setRidgegearProject(
            tripId: widget.tripId,
            projectId: project.id,
            projectName: project.name,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _selecting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.commonErrorWithDetails(e.toString())),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.ridgegearProjectPickerTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: NeonPalette.deep,
              ),
            ),
            const SizedBox(height: 16),
            FutureBuilder<List<_RidgegearProject>>(
              future: _projectsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l10n.commonErrorWithDetails(snapshot.error.toString()),
                      style: const TextStyle(color: NeonPalette.accent),
                    ),
                  );
                }
                final projects = snapshot.data ?? const [];
                if (projects.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      l10n.ridgegearProjectPickerEmpty,
                      style: const TextStyle(color: NeonPalette.onSurfaceVariant),
                    ),
                  );
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final project in projects) ...[
                      Material(
                        color: NeonPalette.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: const BorderSide(color: NeonPalette.divider),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _selecting ? null : () => _select(project),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.backpack_outlined,
                                  color: NeonPalette.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    project.name.isEmpty
                                        ? project.id
                                        : project.name,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: NeonPalette.deep,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
