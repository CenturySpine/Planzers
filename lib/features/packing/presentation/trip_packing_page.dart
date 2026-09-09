import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/packing/data/packing_item.dart';
import 'package:planerz/features/packing/data/packing_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/l10n/app_localizations.dart';

/// "À emporter" — a personal, per-traveler checklist of things to pack /
/// bring. Items are free text (no suggestions). The trip owner flags each of
/// their own items as "personal" or "group" and can push the group ones to
/// every traveler; pushed items show a lock and can only be checked, never
/// edited, by the traveler.
class TripPackingPage extends ConsumerStatefulWidget {
  const TripPackingPage({super.key, required this.tripId});

  final String tripId;

  @override
  ConsumerState<TripPackingPage> createState() => _TripPackingPageState();
}

class _TripPackingPageState extends ConsumerState<TripPackingPage> {
  final TextEditingController _addController = TextEditingController();
  final FocusNode _addFocusNode = FocusNode();
  bool _pushing = false;

  @override
  void dispose() {
    _addController.dispose();
    _addFocusNode.dispose();
    super.dispose();
  }

  PackingRepository get _repo => ref.read(packingRepositoryProvider);

  Future<void> _addItem(String participantId) async {
    final label = _addController.text.trim();
    if (label.isEmpty) return;
    _addController.clear();
    try {
      await _repo.addItem(
        tripId: widget.tripId,
        participantId: participantId,
        label: label,
      );
      if (mounted) _addFocusNode.requestFocus();
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _rename(String participantId, PackingItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: item.label);
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Theme(
        data: NeonPalette.overlayOn(Theme.of(dialogContext)),
        child: AlertDialog(
          title: Text(l10n.tripPackingRenameTitle),
          content: TextField(
            controller: controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: l10n.tripPackingItemHint),
            onSubmitted: (value) =>
                Navigator.of(dialogContext).pop(value.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (next == null || next.isEmpty || next == item.label || !mounted) return;
    try {
      await _repo.updateLabel(
        tripId: widget.tripId,
        participantId: participantId,
        itemId: item.id,
        label: next,
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _toggleShared(String participantId, PackingItem item) async {
    try {
      await _repo.setShared(
        tripId: widget.tripId,
        participantId: participantId,
        itemId: item.id,
        shared: !item.shared,
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _confirmDelete(String participantId, PackingItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: NeonPalette.overlayOn(Theme.of(dialogContext)),
        child: AlertDialog(
          title: Text(l10n.tripPackingDeleteTitle),
          content: Text(l10n.tripPackingDeleteBody(item.label)),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await _repo.deleteItem(
        tripId: widget.tripId,
        participantId: participantId,
        itemId: item.id,
      );
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _confirmPush(int sharedItemCount) async {
    final l10n = AppLocalizations.of(context)!;
    if (sharedItemCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripPackingPushEmpty)),
      );
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => Theme(
        data: NeonPalette.overlayOn(Theme.of(dialogContext)),
        child: AlertDialog(
          title: Text(l10n.tripPackingPushTitle),
          content: Text(l10n.tripPackingPushBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.tripPackingPushConfirm),
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _pushing = true);
    try {
      final result =
          await _repo.pushListToParticipants(tripId: widget.tripId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.tripPackingPushSuccess(result.participantCount),
          ),
        ),
      );
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _pushing = false);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppLocalizations.of(context)!.commonErrorWithDetails(error.toString()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tripId = widget.tripId;
    final participantId = ref.watch(myPackingParticipantIdProvider(tripId));
    final itemsAsync = ref.watch(myPackingItemsStreamProvider(tripId));
    final trip = ref.watch(tripStreamProvider(tripId)).asData?.value;
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    // Only the trip owner sorts their items into personal / group and pushes
    // the group ones to the other travelers.
    final canPush = trip != null &&
        isTripRoleAllowed(
          currentRole: resolveTripPermissionRole(trip: trip, userId: myUid),
          minRole: TripPermissionRole.owner,
        );

    final items = itemsAsync.asData?.value ?? const <PackingItem>[];
    final sharedItemCount = items
        .where((item) => item.shared && !item.isFromOrganiser)
        .length;

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: Scaffold(
        backgroundColor: NeonPalette.scaffoldBackground,
        appBar: AppBar(
          title: Text(l10n.tripPackingPageTitle),
          actions: [
            if (canPush && participantId != null)
              _pushing
                  ? const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 18),
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.ios_share),
                      tooltip: l10n.tripPackingPushAction,
                      onPressed: () => _confirmPush(sharedItemCount),
                    ),
          ],
        ),
        body: participantId == null
            ? _NotATravelerMessage(message: l10n.tripPackingNotTraveler)
            : Column(
                children: [
                  Expanded(
                    child: itemsAsync.when(
                      data: (list) {
                        if (list.isEmpty) {
                          return _PackingEmptyState(
                            message: l10n.tripPackingEmptyState,
                          );
                        }
                        return ListView.separated(
                          padding:
                              const EdgeInsets.fromLTRB(16, 16, 16, 16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = list[index];
                            return _PackingRow(
                              item: item,
                              onToggle: (checked) => _repo.setChecked(
                                tripId: tripId,
                                participantId: participantId,
                                itemId: item.id,
                                checked: checked,
                              ),
                              onRename: item.isFromOrganiser
                                  ? null
                                  : () => _rename(participantId, item),
                              onDelete: item.isFromOrganiser
                                  ? null
                                  : () =>
                                      _confirmDelete(participantId, item),
                              onToggleShared:
                                  canPush && !item.isFromOrganiser
                                      ? () =>
                                          _toggleShared(participantId, item)
                                      : null,
                              organiserBadgeTooltip:
                                  l10n.tripPackingOrganiserItemTooltip,
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (error, _) => _PackingEmptyState(
                        message:
                            l10n.commonErrorWithDetails(error.toString()),
                      ),
                    ),
                  ),
                  _PackingAddField(
                    controller: _addController,
                    focusNode: _addFocusNode,
                    hint: l10n.tripPackingItemHint,
                    addTooltip: l10n.tripPackingAddItem,
                    onSubmit: () => _addItem(participantId),
                  ),
                ],
              ),
      ),
    );
  }
}

class _PackingRow extends StatelessWidget {
  const _PackingRow({
    required this.item,
    required this.onToggle,
    required this.onRename,
    required this.onDelete,
    required this.onToggleShared,
    required this.organiserBadgeTooltip,
  });

  final PackingItem item;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  /// Non-null only for the trip owner's own items: flips the item between
  /// "personal" and "group".
  final VoidCallback? onToggleShared;

  final String organiserBadgeTooltip;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final checked = item.checked;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: NeonPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NeonPalette.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              onChanged: (value) => onToggle(value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            Expanded(
              child: GestureDetector(
                onTap: onRename,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      height: 1.2,
                      color: checked
                          ? NeonPalette.onSurfaceVariant
                          : NeonPalette.deep,
                      decoration: checked
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                    ),
                  ),
                ),
              ),
            ),
            if (onToggleShared != null)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: _PackingShareToggle(
                  shared: item.shared,
                  onPressed: onToggleShared!,
                ),
              ),
            if (item.isFromOrganiser)
              Padding(
                padding: const EdgeInsets.only(right: 10, left: 4),
                child: Tooltip(
                  message: organiserBadgeTooltip,
                  child: const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: NeonPalette.outline,
                  ),
                ),
              )
            else
              PopupMenuButton<String>(
                icon: const Icon(
                  Icons.more_vert,
                  size: 18,
                  color: NeonPalette.outline,
                ),
                onSelected: (value) {
                  if (value == 'rename') onRename?.call();
                  if (value == 'delete') onDelete?.call();
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(l10n.tripPackingRenameItem),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(l10n.commonDelete),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Personal / group switch shown to the trip owner on each of their items.
/// Styled as an explicit button (outlined when personal, filled when group)
/// so the state reads at a glance and the tap target is obvious.
class _PackingShareToggle extends StatelessWidget {
  const _PackingShareToggle({
    required this.shared,
    required this.onPressed,
  });

  final bool shared;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final radius = BorderRadius.circular(10);

    return Tooltip(
      message: shared
          ? l10n.tripPackingItemGroupTooltip
          : l10n.tripPackingItemPersonalTooltip,
      child: Semantics(
        button: true,
        toggled: shared,
        child: Material(
          color: shared ? NeonPalette.primary : NeonPalette.surface,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: shared
                ? BorderSide.none
                : const BorderSide(color: NeonPalette.divider),
          ),
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: SizedBox(
              width: 36,
              height: 36,
              child: Icon(
                shared ? Icons.groups_rounded : Icons.person_outline_rounded,
                size: 20,
                color: shared ? Colors.white : NeonPalette.primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PackingAddField extends StatelessWidget {
  const _PackingAddField({
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.addTooltip,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final String addTooltip;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 12, 12),
        decoration: const BoxDecoration(
          color: NeonPalette.surface,
          border: Border(top: BorderSide(color: NeonPalette.divider)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  hintText: hint,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: addTooltip,
              onPressed: onSubmit,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackingEmptyState extends StatelessWidget {
  const _PackingEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: NeonPalette.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _NotATravelerMessage extends StatelessWidget {
  const _NotATravelerMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _PackingEmptyState(message: message);
  }
}
