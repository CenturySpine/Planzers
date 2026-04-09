import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planzers/features/account/presentation/account_menu_button.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:url_launcher/url_launcher.dart';

class TripDetailsPage extends ConsumerStatefulWidget {
  const TripDetailsPage({
    super.key,
    required this.trip,
  });

  final Trip trip;

  @override
  ConsumerState<TripDetailsPage> createState() => _TripDetailsPageState();
}

class _TripDetailsPageState extends ConsumerState<TripDetailsPage> {
  final _formKey = GlobalKey<FormState>();
  late Trip _trip;
  late final TextEditingController _titleController;
  late final TextEditingController _destinationController;
  late final TextEditingController _addressController;
  late final TextEditingController _linkController;
  bool _isEditing = false;
  bool _isSaving = false;
  bool _isSharingInvite = false;
  final Set<String> _removingMemberIds = <String>{};

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _titleController = TextEditingController(text: _trip.title);
    _destinationController = TextEditingController(text: _trip.destination);
    _addressController = TextEditingController(text: _trip.address);
    _linkController = TextEditingController(text: _trip.linkUrl);
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
    setState(() {
      _isEditing = true;
      _titleController.text = _trip.title;
      _destinationController.text = _trip.destination;
      _addressController.text = _trip.address;
      _linkController.text = _trip.linkUrl;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _titleController.text = _trip.title;
      _destinationController.text = _trip.destination;
      _addressController.text = _trip.address;
      _linkController.text = _trip.linkUrl;
    });
  }

  Future<void> _openAddressLocation(String address) async {
    final query = address.trim();
    if (query.isEmpty) return;

    final mapsUri = Uri.https(
      'www.google.com',
      '/maps/search/',
      <String, String>{
        'api': '1',
        'query': query,
      },
    );

    final didLaunch = await launchUrl(
      mapsUri,
      mode: LaunchMode.platformDefault,
    );

    if (!didLaunch && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir la localisation')),
      );
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

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
          );

      if (!mounted) return;
      setState(() {
        _trip = Trip(
          id: _trip.id,
          title: title,
          destination: destination,
          address: address,
          linkUrl: linkUrl,
          ownerId: _trip.ownerId,
          memberIds: _trip.memberIds,
          createdAt: _trip.createdAt,
        );
        _isEditing = false;
      });

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
    if (_isSharingInvite) return;
    setState(() => _isSharingInvite = true);
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
        setState(() => _isSharingInvite = false);
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
    final titleForAppBar = _trip.title.isEmpty ? 'Voyage' : _trip.title;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final canEdit = (myUid != null && myUid == _trip.ownerId);
    final tripDocStream = FirebaseFirestore.instance
        .collection('trips')
        .doc(_trip.id)
        .snapshots();

    return Scaffold(
      appBar: AppBar(
        title: Text(titleForAppBar),
        actions: [
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
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
            ),
          ] else if (canEdit) ...[
            IconButton(
              tooltip: 'Partager invitation',
              onPressed: _isSharingInvite ? null : _shareInviteLink,
              icon: _isSharingInvite
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.group_add_outlined),
            ),
            IconButton(
              tooltip: 'Modifier',
              onPressed: _startEditing,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
          const AccountMenuButton(),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
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

          final linkUrlForUi =
              _isEditing ? _linkController.text.trim() : liveLinkUrl.trim();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
                const SizedBox(height: 16),
              ],
              if (linkUrlForUi.isNotEmpty) ...[
                _LinkPreviewCardFromFirestore(
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
                            : () => _openAddressLocation(_trip.address),
                        actionTooltip: 'Ouvrir la localisation',
                      ),
                      const SizedBox(height: 12),
                      _MembersInfoRow(
                        memberIds: liveMemberIds,
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
            ],
          );
        },
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

        final ownerLabel = displayName.isNotEmpty
            ? displayName
            : email.isNotEmpty
                ? email
                : 'Nom indisponible';

        return _InfoRow(label: 'Proprietaire', value: ownerLabel);
      },
    );
  }
}

class _MembersInfoRow extends StatelessWidget {
  const _MembersInfoRow({
    required this.memberIds,
    required this.currentUserId,
    required this.canManageMembers,
    required this.onRemoveMember,
    required this.isRemovingMember,
  });

  final List<String> memberIds;
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
          final data = docsById[memberId];
          final account =
              (data?['account'] as Map<String, dynamic>?) ?? const {};
          final accountName = (account['name'] as String?)?.trim() ?? '';
          final accountEmail = (account['email'] as String?)?.trim() ?? '';
          final email = (data?['email'] as String?)?.trim() ?? '';
          final displayName = (data?['displayName'] as String?)?.trim() ?? '';

          final label = accountName.isNotEmpty
              ? accountName
              : accountEmail.isNotEmpty
                  ? accountEmail
                  : displayName.isNotEmpty
                      ? displayName
                      : email.isNotEmpty
                          ? email
                          : 'Utilisateur';
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

class _LinkPreviewCardFromFirestore extends StatelessWidget {
  const _LinkPreviewCardFromFirestore({
    required this.url,
    required this.preview,
  });

  final String url;
  final Map<String, dynamic> preview;

  Future<void> _openLink(BuildContext context) async {
    final parsed = Uri.tryParse(url.trim());
    if (parsed == null || !parsed.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lien invalide')),
      );
      return;
    }

    final didLaunch = await launchUrl(
      parsed,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );

    if (!didLaunch && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir le lien')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = (preview['status'] as String?) ?? '';
    final title = (preview['title'] as String?) ?? '';
    final description = (preview['description'] as String?) ?? '';
    final siteName = (preview['siteName'] as String?) ?? '';
    final imageUrl = (preview['imageUrl'] as String?) ?? '';

    final hasPreview = title.trim().isNotEmpty ||
        description.trim().isNotEmpty ||
        imageUrl.trim().isNotEmpty ||
        siteName.trim().isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Lien', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _openLink(context),
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      url,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (status == 'loading') ...[
              const SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            ] else if (!hasPreview) ...[
              Text(
                'Apercu indisponible pour ce lien.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ] else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (imageUrl.trim().isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        imageUrl,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        webHtmlElementStrategy: kIsWeb
                            ? WebHtmlElementStrategy.prefer
                            : WebHtmlElementStrategy.never,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: Colors.black12,
                          alignment: Alignment.center,
                          child: const Icon(Icons.broken_image_outlined),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (siteName.trim().isNotEmpty) ...[
                          Text(
                            siteName,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (title.trim().isNotEmpty) ...[
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ],
                        if (description.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            description,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
