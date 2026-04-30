import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/administration/data/administration_repository.dart';
import 'package:planerz/features/administration/domain/app_usage_stats.dart';

final _administrationRepositoryProvider =
    Provider.autoDispose((_) => AdministrationRepository());

final _appUsageStatsProvider =
    FutureProvider.autoDispose<AppUsageStats>((ref) {
  return ref.read(_administrationRepositoryProvider).getAppUsageStats();
});

class AdministrationPage extends ConsumerWidget {
  const AdministrationPage({super.key});

  static const String routePath = '/administration';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_appUsageStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Administration'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
            onPressed: statsAsync.isLoading
                ? null
                : () => ref.invalidate(_appUsageStatsProvider),
          ),
        ],
      ),
      body: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Impossible de charger les statistiques.',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  error.toString(),
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => ref.invalidate(_appUsageStatsProvider),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Réessayer'),
                ),
              ],
            ),
          ),
        ),
        data: (stats) => _StatsBody(stats: stats),
      ),
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});

  final AppUsageStats stats;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        _SectionTitle(title: 'Voyages'),
        _StatRow(label: 'Total créés', value: '${stats.tripsTotal}'),
        _StatRow(label: 'Passés', value: '${stats.tripsPast}'),
        _StatRow(label: 'En cours', value: '${stats.tripsOngoing}'),
        _StatRow(label: 'À venir', value: '${stats.tripsUpcoming}'),
        if (stats.tripsUncategorized > 0)
          _StatRow(
            label: 'Sans dates',
            value: '${stats.tripsUncategorized}',
          ),
        _StatRow(
          label: 'Max. participants',
          value: stats.tripsMaxParticipants > 0
              ? '${stats.tripsMaxParticipants}'
              : '–',
        ),
        _StatRow(
          label: 'Durée maximale',
          value: stats.tripsMaxDurationDays > 0
              ? '${stats.tripsMaxDurationDays} jours'
              : '–',
        ),
        const SizedBox(height: 24),
        _SectionTitle(title: 'Utilisateurs'),
        _StatRow(label: 'Total', value: '${stats.usersTotal}'),
        _StatRow(
          label: 'Dernière connexion',
          value: stats.usersLatestSignIn != null
              ? dateFormat.format(stats.usersLatestSignIn!.toLocal())
              : '–',
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
