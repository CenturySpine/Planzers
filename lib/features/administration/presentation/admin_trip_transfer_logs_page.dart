import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/features/administration/data/trip_transfer_logs_repository.dart';

/// Journals of the trip exports / imports, to copy when one goes wrong.
class AdminTripTransferLogsPage extends ConsumerWidget {
  const AdminTripTransferLogsPage({super.key});

  static const String routePath = '/administration/trip-transfers';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(tripTransferLogsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Export / import de voyages')),
      body: logsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Échec du chargement : $error'),
          ),
        ),
        data: (logs) {
          if (logs.isEmpty) {
            return const Center(child: Text('Aucun journal'));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: logs.length,
            itemBuilder: (context, index) => _LogTile(log: logs[index]),
          );
        },
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.log});

  final TripTransferLog log;

  static final DateFormat _dateFormat = DateFormat('dd/MM/yyyy à HH:mm:ss');

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (icon, color, statusLabel) = switch (log.status) {
      'success' => (PhosphorIconsRegular.checkCircle, colors.primary, 'Réussi'),
      'error' => (PhosphorIconsRegular.warningCircle, colors.error, 'Échec'),
      _ => (PhosphorIconsRegular.clock, colors.onSurfaceVariant, 'En cours ou interrompu'),
    };
    final title = log.tripTitle.isEmpty ? '(sans titre)' : log.tripTitle;
    final details = [
      if (log.startedAt != null) _dateFormat.format(log.startedAt!),
      statusLabel,
      if (log.durationMs != null) '${(log.durationMs! / 1000).toStringAsFixed(1)} s',
      if (log.fileSizeBytes != null) _sizeLabel(log.fileSizeBytes!),
    ];
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text('${log.isImport ? 'Import' : 'Export'} · $title'),
      subtitle: Text(details.join(' · ')),
      trailing: IconButton(
        tooltip: 'Copier le journal',
        icon: const Icon(PhosphorIconsRegular.copy),
        onPressed: () => _copy(context),
      ),
      onTap: () => _showDetails(context),
    );
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: log.toPrettyJson()));
    messenger.showSnackBar(const SnackBar(content: Text('Journal copié')));
  }

  Future<void> _showDetails(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(log.isImport ? 'Journal d\'import' : 'Journal d\'export'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              log.toPrettyJson(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fermer'),
          ),
          FilledButton(
            onPressed: () => _copy(context),
            child: const Text('Copier'),
          ),
        ],
      ),
    );
  }
}
