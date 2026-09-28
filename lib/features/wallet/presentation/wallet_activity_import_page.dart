import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/activities/presentation/trip_activity_duration.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_config.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';
import 'package:planerz/features/wallet/data/wallet_activity_import_repository.dart';
import 'package:planerz/features/wallet/data/wallet_document.dart';
import 'package:planerz/features/wallet/data/wallet_repository.dart';
import 'package:planerz/features/wallet/presentation/wallet_document_ui.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Generates planning activities from the traveler's documents: pick the
/// documents, let the AI read them, then keep the proposals to add.
/// Restricted to trip admins (checked again by the Cloud Functions).
class WalletActivityImportPage extends ConsumerStatefulWidget {
  const WalletActivityImportPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<WalletActivityImportPage> createState() =>
      _WalletActivityImportPageState();
}

class _WalletActivityImportPageState
    extends ConsumerState<WalletActivityImportPage> {
  final Set<String> _selectedDocumentIds = {};
  final TextEditingController _instructionsController = TextEditingController();
  List<WalletActivityProposal>? _proposals;
  final Set<int> _keptIndexes = {};
  bool _busy = false;

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    setState(() => _busy = true);
    try {
      final proposals = await ref
          .read(walletActivityImportRepositoryProvider)
          .extractProposals(
            tripId: widget.tripId,
            documentIds: _selectedDocumentIds.toList(),
            languageCode: languageCode,
            instructions: _instructionsController.text,
          );
      if (!mounted) return;
      setState(() {
        _proposals = proposals;
        _keptIndexes
          ..clear()
          ..addAll(List.generate(proposals.length, (i) => i));
      });
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorMessage(l10n, error))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final proposals = _proposals;
    if (proposals == null || _keptIndexes.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final kept = [
      for (final (index, proposal) in proposals.indexed)
        if (_keptIndexes.contains(index)) proposal,
    ];
    setState(() => _busy = true);
    try {
      await ref.read(walletActivityImportRepositoryProvider).importProposals(
            tripId: widget.tripId,
            proposals: kept,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.walletActivityImportDone(kept.length))),
      );
      navigator.pop();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(_errorMessage(l10n, error))),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  String _errorMessage(AppLocalizations l10n, Object error) {
    if (error is FirebaseFunctionsException &&
        error.code == 'resource-exhausted') {
      final config = aiQuotaConfigs[AiFeature.documentActivityImport]!;
      return switch (error.message) {
        'quota-trip' => l10n.aiQuotaTripExceeded(config.perTripPerDay),
        'quota-trip-lifetime' =>
          l10n.aiQuotaTripLifetimeExceeded(config.perTripLifetime),
        'circuit-breaker' => l10n.aiQuotaCircuitBreakerTripped,
        _ => l10n.aiQuotaUserExceeded(config.perUserPerDay),
      };
    }
    if (error is FirebaseFunctionsException) {
      return l10n.commonErrorWithDetails(error.message ?? error.code);
    }
    return l10n.commonErrorWithDetails(error.toString());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final proposals = _proposals;
    final Widget body;
    final Widget? action;
    if (_busy && proposals == null) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(l10n.walletActivityImportAnalyzing),
          ],
        ),
      );
      action = null;
    } else if (proposals == null) {
      body = _buildDocumentSelection(context);
      action = FilledButton(
        onPressed: _selectedDocumentIds.isEmpty ? null : _analyze,
        child: Text(l10n.walletActivityImportAnalyze),
      );
    } else if (proposals.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.walletActivityImportNoResult),
        ),
      );
      action = null;
    } else {
      body = _buildProposals(context, proposals);
      action = FilledButton(
        onPressed: _keptIndexes.isEmpty || _busy ? null : _import,
        child: Text(l10n.walletActivityImportAdd(_keptIndexes.length)),
      );
    }

    return Theme(
      data: AppTokens.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: AppTokens.scaffoldBackground,
        appBar: AppBar(title: Text(l10n.walletGenerateActivities)),
        body: body,
        bottomNavigationBar: action == null
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: action,
                ),
              ),
      ),
    );
  }

  Widget _buildDocumentSelection(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final documentsAsync =
        ref.watch(myWalletDocumentsStreamProvider(widget.tripId));
    return documentsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.commonErrorWithDetails(error.toString())),
        ),
      ),
      data: (documents) {
        if (documents.isEmpty) {
          return Center(child: Text(l10n.walletEmpty));
        }
        final full =
            _selectedDocumentIds.length >= walletActivityImportMaxDocuments;
        return ListView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                l10n.walletActivityImportDocumentsTitle,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final document in documents)
              _DocumentTile(
                document: document,
                selected: _selectedDocumentIds.contains(document.id),
                enabled: !full || _selectedDocumentIds.contains(document.id),
                onChanged: (selected) => setState(() {
                  if (selected) {
                    _selectedDocumentIds.add(document.id);
                  } else {
                    _selectedDocumentIds.remove(document.id);
                  }
                }),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextField(
                controller: _instructionsController,
                minLines: 3,
                maxLines: 8,
                maxLength: walletActivityImportMaxInstructionsLength,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: l10n.walletActivityImportInstructions,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildProposals(
    BuildContext context,
    List<WalletActivityProposal> proposals,
  ) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (final (index, proposal) in proposals.indexed)
          _ProposalTile(
            proposal: proposal,
            kept: _keptIndexes.contains(index),
            onChanged: _busy
                ? null
                : (kept) => setState(() {
                      if (kept) {
                        _keptIndexes.add(index);
                      } else {
                        _keptIndexes.remove(index);
                      }
                    }),
          ),
      ],
    );
  }
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({
    required this.document,
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final WalletDocument document;
  final bool selected;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: selected,
      onChanged: enabled ? (value) => onChanged(value ?? false) : null,
      secondary: CircleAvatar(
        backgroundColor: ActivityFilterGroup.trajets.filterLightBgColor,
        child: Icon(
          document.category.icon,
          color: ActivityFilterGroup.trajets.filterInkColor,
        ),
      ),
      title: Text(document.name),
      subtitle: Text(walletDocumentSubtitle(context, document)),
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.proposal,
    required this.kept,
    required this.onChanged,
  });

  final WalletActivityProposal proposal;
  final bool kept;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = proposal.category.filterGroup;
    final plannedAt = proposal.plannedAt;
    final when = plannedAt == null
        ? l10n.walletActivityImportNoDate
        : '${DateFormat.yMMMEd(Localizations.localeOf(context).toString()).add_Hm().format(plannedAt)}'
            ' · ${formatTripActivityDuration(proposal.effectiveDuration, l10n)}';
    return CheckboxListTile(
      value: kept,
      onChanged: onChanged == null ? null : (value) => onChanged!(value ?? false),
      isThreeLine: proposal.address.isNotEmpty,
      secondary: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: group.filterLightBgColor,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Icon(
          proposal.category.categoryIcon,
          size: 20,
          color: group.filterColor,
        ),
      ),
      title: Text(proposal.label),
      subtitle: Text(
        proposal.address.isEmpty ? when : '$when\n${proposal.address}',
      ),
    );
  }
}
