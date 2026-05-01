import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/features/administration/data/administration_repository.dart';
import 'package:planerz/features/administration/presentation/admin_announcements_manage_page.dart';
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

const _kCategoryLabels = {
  'sport': 'Sport',
  'hiking': 'Randonnée',
  'shopping': 'Shopping',
  'visit': 'Visite',
  'restaurant': 'Restaurant',
  'cafe': 'Café',
  'museum': 'Musée',
  'show': 'Spectacle',
  'nightlife': 'Soirée',
  'karaoke': 'Karaoké',
  'games': 'Jeux',
  'beach': 'Plage',
  'park': 'Parc',
  'transport': 'Transport',
  'accommodation': 'Hébergement',
  'wellness': 'Bien-être',
  'cooking': 'Cuisine',
  'workshop': 'Atelier',
  'market': 'Marché',
  'meeting': 'Réunion',
};

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.stats});

  final AppUsageStats stats;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd/MM/yyyy à HH:mm');

    final sortedCategories = stats.activitiesByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.campaign_outlined),
            title: const Text('Annonces globales'),
            subtitle: const Text('Créer, modifier et supprimer les annonces.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(AdminAnnouncementsManagePage.routePath),
          ),
        ),
        const SizedBox(height: 12),
        _StatsExpander(
          title: 'Voyages',
          total: '${stats.tripsTotal}',
          children: [
            _StatBreakdown(
              rows: [
                _BreakdownStat(label: 'Passés', value: '${stats.tripsPast}'),
                _BreakdownStat(label: 'En cours', value: '${stats.tripsOngoing}'),
                _BreakdownStat(label: 'À venir', value: '${stats.tripsUpcoming}'),
                if (stats.tripsUncategorized > 0)
                  _BreakdownStat(
                    label: 'Sans dates',
                    value: '${stats.tripsUncategorized}',
                  ),
              ],
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
            _StatRow(
              label: 'Dernier voyage créé',
              value: stats.tripsLatestCreatedAt != null
                  ? dateFormat.format(stats.tripsLatestCreatedAt!.toLocal())
                  : '–',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatsExpander(
          title: 'Utilisateurs',
          total: '${stats.usersTotal}',
          children: [
            _StatRow(
              label: 'Dernière connexion',
              value: stats.usersLatestSignIn != null
                  ? dateFormat.format(stats.usersLatestSignIn!.toLocal())
                  : '–',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _StatsExpander(
          title: 'Activités',
          total: '${stats.activitiesTotal}',
          children: [
            _StatBreakdown(
              rows: [
                _BreakdownStat(
                  label: 'Planifiées',
                  value: '${stats.activitiesPlanned}',
                ),
              ],
            ),
            if (sortedCategories.isNotEmpty) ...[
              const SizedBox(height: 12),
              _SubSectionTitle(title: 'Par catégorie'),
              _StatBreakdown(
                rows: [
                  for (final entry in sortedCategories)
                    _BreakdownStat(
                      label: _kCategoryLabels[entry.key] ?? entry.key,
                      value: '${entry.value}',
                    ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _SubSectionTitle extends StatelessWidget {
  const _SubSectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }
}

class _StatsExpander extends StatelessWidget {
  const _StatsExpander({
    required this.title,
    required this.total,
    required this.children,
  });

  final String title;
  final String total;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.bold,
        );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: titleStyle),
            Text(total, style: titleStyle),
          ],
        ),
        children: children,
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
      padding: const EdgeInsets.only(top: 8, bottom: 8, right: 12),
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

class _BreakdownStat {
  const _BreakdownStat({required this.label, required this.value});

  final String label;
  final String value;
}

class _StatBreakdown extends StatelessWidget {
  const _StatBreakdown({required this.rows});

  final List<_BreakdownStat> rows;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          for (int index = 0; index < rows.length; index++) ...[
            _BreakdownRow(
              label: rows[index].label,
              value: rows[index].value,
            ),
            if (index < rows.length - 1)
              Divider(
                height: 1,
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
          ],
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 0),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
