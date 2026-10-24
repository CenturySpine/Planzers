import 'package:cloud_functions/cloud_functions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_transfer_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Exports [trip] to a JSON file the user saves (trip owner only).
Future<void> exportTripToFile(
  BuildContext context,
  WidgetRef ref,
  Trip trip,
) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  try {
    final bytes = await _withBlockingProgress(
      context,
      () => ref.read(tripTransferRepositoryProvider).exportTrip(tripId: trip.id),
    );
    final fileName = await tripExportFileName(
      tripTitle: trip.title,
      exportedAt: DateTime.now(),
    );
    final saved = await FilePicker.saveFile(
      fileName: fileName,
      bytes: bytes,
      mimeType: 'application/json',
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    // The web download gives no result; elsewhere null means cancelled.
    if (saved == null && !kIsWeb) return;
    messenger.showSnackBar(SnackBar(content: Text(l10n.tripsExported)));
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.tripsExportError(_errorDetails(e)))),
    );
  }
}

/// Imports a trip file picked by the user as a new trip they own, then opens
/// it.
Future<void> importTripFromFile(BuildContext context, WidgetRef ref) async {
  final l10n = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final router = GoRouter.of(context);
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (picked == null || !context.mounted) return;
  try {
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    final tripId = await _withBlockingProgress(
      context,
      () => ref.read(tripTransferRepositoryProvider).importTrip(bytes: bytes),
    );
    router.go('/trips/$tripId/overview');
    messenger.showSnackBar(SnackBar(content: Text(l10n.tripsImported)));
  } on TripTransferVersionMismatchException catch (e) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.tripsImportVersionMismatch(e.fileVersion, e.appVersion),
        ),
      ),
    );
  } on TripTransferInvalidFileException {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.tripsImportInvalidFile)),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.tripsImportError(_errorDetails(e)))),
    );
  }
}

/// Runs [task] behind a modal progress indicator: with photos, a transfer
/// can take a while.
Future<T> _withBlockingProgress<T>(
  BuildContext context,
  Future<T> Function() task,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    return await task();
  } finally {
    navigator.pop();
  }
}

String _errorDetails(Object error) {
  if (error is FirebaseFunctionsException &&
      error.message?.trim().isNotEmpty == true) {
    return error.message!.trim();
  }
  return error.toString();
}
