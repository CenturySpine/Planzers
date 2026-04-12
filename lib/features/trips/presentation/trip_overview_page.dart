import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planzers/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planzers/features/trips/presentation/trip_date_format.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';
class TripOverviewPage extends ConsumerStatefulWidget {
  const TripOverviewPage({super.key});

  @override
  ConsumerState<TripOverviewPage> createState() => _TripOverviewPageState();
}

class _TripOverviewPageState extends ConsumerState<TripOverviewPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _destinationController;
  late final TextEditingController _addressController;
  late final TextEditingController _linkController;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _inviteClipboardBusy = false;
  final Set<String> _removingMemberIds = <String>{};
  DateTime? _editStartDate;
  DateTime? _editEndDate;

  Trip get _trip => TripScope.of(context);

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _destinationController = TextEditingController();
    _addressController = TextEditingController();
    _linkController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final trip = TripScope.of(context);
    if (!_isEditing) {
      _titleController.text = trip.title;
      _destinationController.text = trip.destination;
      _addressController.text = trip.address;
      _linkController.text = trip.linkUrl;
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _destinationController.dispose();
    _addressController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  void _startEditing() {
    final trip = TripScope.of(context);
    setState(() {
      _isEditing = true;
      _titleController.text = trip.title;
      _destinationController.text = trip.destination;
      _addressController.text = trip.address;
      _linkController.text = trip.linkUrl;
      _editStartDate = trip.startDate;
      _editEndDate = trip.endDate;
    });
  }

  void _cancelEditing() {
    final trip = TripScope.of(context);
    setState(() {
      _isEditing = false;
      _titleController.text = trip.title;
      _destinationController.text = trip.destination;
      _addressController.text = trip.address;
      _linkController.text = trip.linkUrl;
      _editStartDate = trip.startDate;
      _editEndDate = trip.endDate;
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    if (isEndBeforeStart(_editStartDate, _editEndDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'La date de fin doit être le même jour ou après la date de début',
          ),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final title = _titleController.text.trim();
      final destination = _destinationController.text.trim();
      final address = _addressController.text.trim();
      final linkUrl = _linkController.text.trim();

      await ref.read(tripsRepositoryProvider).updateTrip(
            tripId: _trip.id,
            title: title,
            destination: destination,
            address: address,
            linkUrl: linkUrl,
            startDate: _editStartDate,
            endDate: _editEndDate,
          );

      if (!mounted) return;
      setState(() => _isEditing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyage mis a jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur modification: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _shareInviteLink() async {
    if (_inviteClipboardBusy) return;
    setState(() => _inviteClipboardBusy = true);
    try {
      final link =
          await ref.read(tripsRepositoryProvider).getOrCreateInviteLink(
                tripId: _trip.id,
              );
      await Clipboard.setData(ClipboardData(text: link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Lien d invitation copie dans le presse-papiers')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur partage invitation: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _inviteClipboardBusy = false);
      }
    }
  }

  Future<void> _copyInviteCode() async {
    if (_inviteClipboardBusy) return;
    setState(() => _inviteClipboardBusy = true);
    try {
      final token =
          await ref.read(tripsRepositoryProvider).getOrCreateInviteToken(
                tripId: _trip.id,
              );
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code d invitation copie dans le presse-papiers'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur copie du code: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _inviteClipboardBusy = false);
      }
    }
  }

  Future<void> _removeMember(String memberId, String memberLabel) async {
    final cleanMemberId = memberId.trim();
    if (cleanMemberId.isEmpty || _removingMemberIds.contains(cleanMemberId)) {
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Retirer ce voyageur ?'),
        content: Text(
          'Retirer "$memberLabel" du voyage en cours ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Retirer'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _removingMemberIds.add(cleanMemberId));
    try {
      await ref.read(tripsRepositoryProvider).removeMemberFromTrip(
            tripId: _trip.id,
            memberId: cleanMemberId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voyageur retire du voyage')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression voyageur: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _removingMemberIds.remove(cleanMemberId));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final canEdit = (myUid != null && myUid == _trip.ownerId);
    final tripDocStream = FirebaseFirestore.instance
        .collection('trips')
        .doc(_trip.id)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tripDocStream,
      builder: (context, snapshot) {
        final liveData = snapshot.data?.data();
        final liveLinkUrl =
            (liveData?['linkUrl'] as String?) ?? _trip.linkUrl;
        final livePreview =
            (liveData?['linkPreview'] as Map<String, dynamic>?) ?? const {};
        final liveMemberIds =
            ((liveData?['memberIds'] as List<dynamic>?) ?? _trip.memberIds)
                .map((id) => id.toString())
                .toList();
        final liveMemberPublicLabels = liveData != null &&
                liveData.containsKey('memberPublicLabels')
            ? Trip.memberPublicLabelsFromFirestore(
                liveData['memberPublicLabels'],
              )
            : _trip.memberPublicLabels;

        final linkUrlForUi =
            _isEditing ? _linkController.text.trim() : liveLinkUrl.trim();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (canEdit)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (_isEditing) ...[
                      IconButton(
                        tooltip: 'Annuler',
                        onPressed: _isSaving ? null : _cancelEditing,
                        icon: const Icon(Icons.close),
                      ),
                      IconButton(
                        tooltip: 'Enregistrer',
                        onPressed: _isSaving ? null : _save,
                        icon: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                      ),
                    ] else ...[
                      IconButton(
                        tooltip: 'Partager invitation',
                        onPressed:
                            _inviteClipboardBusy ? null : _shareInviteLink,
                        icon: _inviteClipboardBusy
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.group_add_outlined),
                      ),
                      IconButton(
                        tooltip: 'Copier le code d invitation',
                        onPressed:
                            _inviteClipboardBusy ? null : _copyInviteCode,
                        icon: const Icon(Icons.vpn_key_outlined),
                      ),
                      IconButton(
                        tooltip: 'Modifier le voyage',
                        onPressed: _startEditing,
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ],
                ),
              ),
            if (_isEditing) ...[
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _titleController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Titre',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Titre obligatoire';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _destinationController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Destination',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Destination obligatoire';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date de début'),
                      subtitle: Text(formatOptionalTripDate(_editStartDate)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_editStartDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _editStartDate = null),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    _editStartDate ?? DateTime.now(),
                                firstDate: DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && mounted) {
                                setState(() => _editStartDate = picked);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _editStartDate ?? DateTime.now(),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null && mounted) {
                          setState(() => _editStartDate = picked);
                        }
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Date de fin'),
                      subtitle: Text(formatOptionalTripDate(_editEndDate)),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_editEndDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () =>
                                  setState(() => _editEndDate = null),
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate:
                                    _editEndDate ?? _editStartDate ?? DateTime.now(),
                                firstDate: _editStartDate ?? DateTime(2000),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null && mounted) {
                                setState(() => _editEndDate = picked);
                              }
                            },
                          ),
                        ],
                      ),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate:
                              _editEndDate ?? _editStartDate ?? DateTime.now(),
                          firstDate: _editStartDate ?? DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null && mounted) {
                          setState(() => _editEndDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _addressController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Adresse',
                        hintText: '10 Rue de Rivoli, 75001 Paris',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _linkController,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        labelText: 'Lien (Airbnb, Booking, site, ...)',
                        hintText: 'https://...',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                      validator: (value) {
                        final v = (value ?? '').trim();
                        if (v.isEmpty) return null;
                        final uri = Uri.tryParse(v);
                        if (uri == null || !uri.isAbsolute) {
                          return 'Lien invalide (ex: https://...)';
                        }
                        if (uri.scheme != 'http' && uri.scheme != 'https') {
                          return 'Le lien doit commencer par http(s)://';
                        }
                        return null;
                      },
                      onFieldSubmitted: (_) => _save(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else ...[
              Text(
                _trip.title.isEmpty ? 'Sans titre' : _trip.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                _trip.destination.isEmpty
                    ? 'Destination inconnue'
                    : _trip.destination,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (formatTripDateRange(_trip.startDate, _trip.endDate)
                  .isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.date_range_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        formatTripDateRange(_trip.startDate, _trip.endDate),
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
            if (linkUrlForUi.isNotEmpty) ...[
              LinkPreviewCardFromFirestore(
                url: linkUrlForUi,
                preview: livePreview,
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OwnerInfoRow(ownerId: _trip.ownerId),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Adresse',
                      value: _trip.address,
                      actionIcon: Icons.location_on_outlined,
                      onActionPressed: _trip.address.trim().isEmpty
                          ? null
                          : () => openAddressInGoogleMaps(
                                context,
                                _trip.address,
                              ),
                      actionTooltip: 'Ouvrir la localisation',
                    ),
                    const SizedBox(height: 12),
                    _MembersInfoRow(
                      memberIds: liveMemberIds,
                      memberPublicLabels: liveMemberPublicLabels,
                      currentUserId: myUid,
                      canManageMembers: canEdit,
                      onRemoveMember: _removeMember,
                      isRemovingMember: (memberId) =>
                          _removingMemberIds.contains(memberId),
                    ),
                    const SizedBox(height: 12),
                    _InfoRow(
                      label: 'Cree le',
                      value: _trip.createdAt.toLocal().toString(),
                    ),
                  ],
                ),
              ),
            ),
            if (myUid != null &&
                !canEdit &&
                liveMemberIds
                    .map((id) => id.trim())
                    .where((id) => id.isNotEmpty)
                    .contains(myUid)) ...[
              const SizedBox(height: 16),
              _LeaveTripSection(tripId: _trip.id),
            ],
          ],
        );
      },
    );
  }
}

class _LeaveTripSection extends ConsumerStatefulWidget {
  const _LeaveTripSection({required this.tripId});

  final String tripId;

  @override
  ConsumerState<_LeaveTripSection> createState() => _LeaveTripSectionState();
}

class _LeaveTripSectionState extends ConsumerState<_LeaveTripSection> {
  bool _busy = false;

  static String _messageForError(Object e) {
    if (e is FirebaseFunctionsException) {
      final m = e.message;
      if (m != null && m.trim().isNotEmpty) {
        return m.trim();
      }
    }
    return e.toString();
  }

  Future<void> _confirmAndLeave() async {
    if (_busy) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitter ce voyage ?'),
        content: const Text(
          'Tu seras retiré de la liste des voyageurs. Sur chaque dépense partagée '
          'où tu participes, tu seras enlevé des participants : le partage sera '
          'recalculé pour les autres. Si tu étais seul sur une dépense, celle-ci '
          'sera supprimée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) {
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(tripsRepositoryProvider).leaveTripAsMember(
            tripId: widget.tripId,
          );
      if (!mounted) return;
      context.go('/trips');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_messageForError(e))),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quitter le voyage',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Tu pourras quitter même si les comptes ne sont pas à zéro. '
              'Tu seras alors retiré automatiquement de toutes les dépenses '
              'où tu es inclus (les autres voyageurs verront les parts mises à jour).',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: _busy || myUid == null ? null : _confirmAndLeave,
              child: _busy
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Quitter le voyage'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.actionIcon,
    this.onActionPressed,
    this.actionTooltip,
  });

  final String label;
  final String value;
  final IconData? actionIcon;
  final VoidCallback? onActionPressed;
  final String? actionTooltip;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Expanded(
          child: Text(
            value.isEmpty ? '-' : value,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        if (actionIcon != null)
          IconButton(
            tooltip: actionTooltip,
            onPressed: onActionPressed,
            icon: Icon(actionIcon),
          ),
      ],
    );
  }
}

class _OwnerInfoRow extends StatelessWidget {
  const _OwnerInfoRow({
    required this.ownerId,
  });

  final String ownerId;

  @override
  Widget build(BuildContext context) {
    if (ownerId.trim().isEmpty) {
      return const _InfoRow(label: 'Proprietaire', value: 'Nom indisponible');
    }

    final ownerDocStream =
        FirebaseFirestore.instance.collection('users').doc(ownerId).snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ownerDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final displayName = (data?['displayName'] as String?)?.trim() ?? '';
        final email = (data?['email'] as String?)?.trim() ?? '';

        final emailLocal =
            email.isNotEmpty ? displayLabelFromEmail(email) : '';
        final ownerLabel = displayName.isNotEmpty
            ? displayName
            : email.isNotEmpty
                ? (emailLocal.isNotEmpty ? emailLocal : email)
                : 'Nom indisponible';

        return _InfoRow(label: 'Proprietaire', value: ownerLabel);
      },
    );
  }
}

class _MembersInfoRow extends StatelessWidget {
  const _MembersInfoRow({
    required this.memberIds,
    required this.memberPublicLabels,
    required this.currentUserId,
    required this.canManageMembers,
    required this.onRemoveMember,
    required this.isRemovingMember,
  });

  final List<String> memberIds;
  final Map<String, String> memberPublicLabels;
  final String? currentUserId;
  final bool canManageMembers;
  final Future<void> Function(String memberId, String memberLabel)
      onRemoveMember;
  final bool Function(String memberId) isRemovingMember;

  @override
  Widget build(BuildContext context) {
    final cleanMemberIds =
        memberIds.map((id) => id.trim()).where((id) => id.isNotEmpty).toList();

    if (cleanMemberIds.isEmpty) {
      return const _InfoRow(label: 'Membres', value: '-');
    }

    final usersQuery = FirebaseFirestore.instance
        .collection('users')
        .where(FieldPath.documentId, whereIn: cleanMemberIds)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: usersQuery,
      builder: (context, snapshot) {
        final docsById = <String, Map<String, dynamic>>{};
        for (final doc in snapshot.data?.docs ?? const []) {
          docsById[doc.id] = doc.data();
        }

        final chips = <Widget>[];
        for (final memberId in cleanMemberIds) {
          final label = resolveTripMemberDisplayLabel(
            memberId: memberId,
            userData: docsById[memberId],
            tripMemberPublicLabels: memberPublicLabels,
            currentUserId: currentUserId,
            emptyFallback: 'Utilisateur',
          );
          final canRemoveThisMember = canManageMembers &&
              currentUserId != null &&
              memberId != currentUserId;
          final isRemoving = isRemovingMember(memberId);

          chips.add(
            Chip(
              label: Text(
                label,
                overflow: TextOverflow.ellipsis,
              ),
              deleteIcon: canRemoveThisMember
                  ? (isRemoving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close, size: 18))
                  : null,
              onDeleted: canRemoveThisMember && !isRemoving
                  ? () {
                      onRemoveMember(memberId, label);
                    }
                  : null,
              deleteIconColor: Theme.of(context).colorScheme.error,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 110,
              child: Text(
                'Membres',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chips,
              ),
            ),
          ],
        );
      },
    );
  }
}
