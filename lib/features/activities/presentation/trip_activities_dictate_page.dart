import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/app_icons.dart';
import 'package:planerz/app/theme/app_tokens.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/activity_text_ai_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/activities/presentation/trip_activity_category_presentation.dart';
import 'package:planerz/features/activities/presentation/trip_activity_dictation_button.dart';
import 'package:planerz/features/activities/presentation/trip_activity_duration.dart';
import 'package:planerz/features/activities/presentation/trip_activity_planned_picker.dart';
import 'package:planerz/features/ai_quotas/data/ai_quota_models.dart';
import 'package:planerz/features/ai_quotas/presentation/ai_error_message.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// Turns an account of what was done, typed or dictated, into activities
/// marked done: the AI proposes them, the member reviews and edits them, then
/// adds the kept ones to the planning.
class TripActivitiesDictatePage extends ConsumerStatefulWidget {
  const TripActivitiesDictatePage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripActivitiesDictatePage> createState() =>
      _TripActivitiesDictatePageState();
}

class _TripActivitiesDictatePageState
    extends ConsumerState<TripActivitiesDictatePage> {
  final TextEditingController _textController = TextEditingController();
  List<TripActivityTextProposal>? _proposals;
  final Set<int> _keptIndexes = {};
  bool _busy = false;
  bool _dictating = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Future<void> _analyze() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final languageCode = Localizations.localeOf(context).languageCode;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    try {
      final proposals =
          await ref.read(activityTextAiRepositoryProvider).extractProposals(
                tripId: widget.tripId,
                text: text,
                languageCode: languageCode,
              );
      if (!mounted) return;
      setState(() {
        _proposals = [...proposals];
        _keptIndexes
          ..clear()
          ..addAll(List.generate(proposals.length, (i) => i));
      });
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            aiErrorMessage(l10n, error, AiFeature.textActivityCreate),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _add() async {
    final proposals = _proposals;
    if (proposals == null || _keptIndexes.isEmpty || _busy) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final kept = [
      for (final (index, proposal) in proposals.indexed)
        if (_keptIndexes.contains(index)) proposal,
    ];
    setState(() => _busy = true);
    try {
      await ref.read(activitiesRepositoryProvider).addDoneActivities(
            tripId: widget.tripId,
            activities: kept,
          );
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.activitiesAiTextAdded(kept.length))),
      );
      if (mounted) context.pop();
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails('$error'))),
      );
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit(int index, {required bool canPlan}) async {
    final proposals = _proposals;
    if (proposals == null) return;
    final edited = await showModalBottomSheet<TripActivityTextProposal>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProposalEditorSheet(
        proposal: proposals[index],
        canPlan: canPlan,
      ),
    );
    if (edited == null || !mounted) return;
    setState(() => proposals[index] = edited);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final myUid = FirebaseAuth.instance.currentUser?.uid.trim();
    final canPlan = ref.watch(tripStreamProvider(widget.tripId)).maybeWhen(
          data: (trip) =>
              trip != null && canPlanActivityForTrip(trip: trip, userId: myUid),
          orElse: () => false,
        );
    final proposals = _proposals;

    final Widget body;
    final Widget? action;
    if (proposals == null) {
      body = _buildInput(l10n);
      action = null;
    } else if (proposals.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.activitiesAiTextNoResult),
        ),
      );
      action = null;
    } else {
      body = _buildProposals(l10n, proposals, canPlan: canPlan);
      action = FilledButton(
        onPressed: _keptIndexes.isEmpty || _busy ? null : _add,
        child: Text(l10n.activitiesAiTextAdd(_keptIndexes.length)),
      );
    }

    // Back from the proposals returns to the text, kept for a new analysis.
    return PopScope(
      canPop: proposals == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) setState(() => _proposals = null);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.activitiesAiTextMenu)),
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

  Widget _buildInput(AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        TextField(
          controller: _textController,
          enabled: !_busy,
          // Dictation writes the text meanwhile.
          readOnly: _dictating,
          minLines: 6,
          maxLines: 14,
          maxLength: tripActivityTextMaxLength,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: l10n.activitiesAiTextLabel,
            border: const OutlineInputBorder(),
            alignLabelWithHint: true,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TripActivityDictationButton(
              controller: _textController,
              maxLength: tripActivityTextMaxLength,
              enabled: !_busy,
              onListeningChanged: (listening) =>
                  setState(() => _dictating = listening),
            ),
            const SizedBox(width: 8),
            ListenableBuilder(
              listenable: _textController,
              builder: (context, _) => FilledButton.tonalIcon(
                onPressed:
                    _busy || _dictating || _textController.text.trim().isEmpty
                        ? null
                        : _analyze,
                icon: _busy
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(PhosphorIconsRegular.sparkle),
                label: Text(l10n.activitiesAiTextAnalyze),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProposals(
    AppLocalizations l10n,
    List<TripActivityTextProposal> proposals, {
    required bool canPlan,
  }) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        for (final (index, proposal) in proposals.indexed)
          _ProposalTile(
            proposal: proposal,
            showSchedule: canPlan,
            kept: _keptIndexes.contains(index),
            onKeptChanged: _busy
                ? null
                : (kept) => setState(() {
                      if (kept) {
                        _keptIndexes.add(index);
                      } else {
                        _keptIndexes.remove(index);
                      }
                    }),
            onEdit: _busy ? null : () => _edit(index, canPlan: canPlan),
          ),
      ],
    );
  }
}

class _ProposalTile extends StatelessWidget {
  const _ProposalTile({
    required this.proposal,
    required this.showSchedule,
    required this.kept,
    required this.onKeptChanged,
    required this.onEdit,
  });

  final TripActivityTextProposal proposal;

  /// Date and duration are only kept for members allowed to plan.
  final bool showSchedule;
  final bool kept;
  final ValueChanged<bool>? onKeptChanged;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = proposal.category.filterGroup;
    final plannedAt = proposal.plannedAt;
    final when = plannedAt == null
        ? l10n.activitiesAiTextNoDate
        : '${DateFormat.MMMEd(Localizations.localeOf(context).toString()).add_Hm().format(plannedAt)}'
            ' · ${formatTripActivityDuration(proposal.effectiveDuration, l10n)}';
    final lines = [
      if (showSchedule) when,
      if (proposal.address.isNotEmpty) proposal.address,
    ];
    return ListTile(
      onTap: onEdit,
      leading: Checkbox(
        value: kept,
        onChanged: onKeptChanged == null
            ? null
            : (value) => onKeptChanged!(value ?? false),
      ),
      title: Row(
        children: [
          Icon(proposal.category.categoryIcon,
              size: 18, color: group.filterColor),
          const SizedBox(width: 8),
          Expanded(child: Text(proposal.label)),
        ],
      ),
      subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
      isThreeLine: lines.length > 1,
      trailing: IconButton(
        tooltip: l10n.commonEdit,
        onPressed: onEdit,
        icon: const Icon(PhosphorIconsRegular.pencilSimple),
      ),
    );
  }
}

/// Edits one proposal before it is added; pops the edited proposal.
class _ProposalEditorSheet extends StatefulWidget {
  const _ProposalEditorSheet({required this.proposal, required this.canPlan});

  final TripActivityTextProposal proposal;
  final bool canPlan;

  @override
  State<_ProposalEditorSheet> createState() => _ProposalEditorSheetState();
}

class _ProposalEditorSheetState extends State<_ProposalEditorSheet> {
  static final _categories = TripActivityCategory.values
      .where((c) => c != TripActivityCategory.restaurant)
      .toList(growable: false);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelController;
  late final TextEditingController _addressController;
  late final TextEditingController _commentsController;
  late TripActivityCategory _category;
  DateTime? _plannedAt;
  int? _durationMinutes;

  @override
  void initState() {
    super.initState();
    final proposal = widget.proposal;
    _labelController = TextEditingController(text: proposal.label);
    _addressController = TextEditingController(text: proposal.address);
    _commentsController = TextEditingController(text: proposal.freeComments);
    _category = proposal.category;
    _plannedAt = proposal.plannedAt;
    _durationMinutes = proposal.durationMinutes;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _commentsController.dispose();
    super.dispose();
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      TripActivityTextProposal(
        label: _labelController.text.trim(),
        category: _category,
        plannedAt: _plannedAt,
        durationMinutes: _durationMinutes,
        address: _addressController.text.trim(),
        freeComments: _commentsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            Text(
              l10n.activitiesAiTextEditTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _labelController,
              decoration: InputDecoration(
                labelText: l10n.activitiesLabel,
                border: const OutlineInputBorder(),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? l10n.activitiesLabelRequired
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.activitiesCategory,
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in _categories)
                  FilterChip(
                    avatar: Icon(category.categoryIcon, size: 18),
                    label: Text(category.label(l10n)),
                    selected: _category == category,
                    onSelected: (_) => setState(() => _category = category),
                  ),
              ],
            ),
            if (widget.canPlan) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await pickTripActivityDateTime(
                            context,
                            current: _plannedAt,
                          );
                          if (picked == null || !mounted) return;
                          setState(() => _plannedAt = picked);
                        },
                        icon: const Icon(PhosphorIconsRegular.calendar),
                        label: Text(
                          _plannedAt == null
                              ? l10n.activitiesPlannedUnset
                              : l10n.activitiesPlannedOn(
                                  DateFormat.yMMMMd(locale)
                                      .add_Hm()
                                      .format(_plannedAt!),
                                ),
                        ),
                      ),
                      TripActivityDurationButton(
                        category: _category,
                        durationMinutes: _durationMinutes,
                        onChanged: (minutes) =>
                            setState(() => _durationMinutes = minutes),
                      ),
                      if (_plannedAt != null)
                        TextButton(
                          onPressed: () => setState(() => _plannedAt = null),
                          child: Text(l10n.activitiesRemovePlannedDate),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _addressController,
              minLines: 1,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.activitiesAddress,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _commentsController,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: l10n.activitiesComments,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _confirm,
                  child: Text(l10n.commonConfirm),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Planning "+" menu row opening [TripActivitiesDictatePage].
class TripActivitiesDictateMenuTile extends StatelessWidget {
  const TripActivitiesDictateMenuTile({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        ),
        child: Icon(
          PhosphorIconsRegular.microphone,
          size: 20,
          color: colors.onSecondaryContainer,
        ),
      ),
      title: Text(AppLocalizations.of(context)!.activitiesAiTextMenu),
      trailing: const Icon(PhosphorIconsRegular.plus),
      onTap: onTap,
    );
  }
}
