import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:planzers/features/activities/data/activities_repository.dart';
import 'package:planzers/features/activities/data/trip_activity.dart';
import 'package:planzers/features/auth/data/user_display_label.dart';
import 'package:planzers/features/auth/data/users_repository.dart';
import 'package:planzers/features/cupidon/data/cupidon_repository.dart';
import 'package:planzers/features/rooms/data/rooms_repository.dart';
import 'package:planzers/features/trips/data/trip.dart';
import 'package:planzers/features/trips/data/trip_placeholder_member.dart';
import 'package:planzers/features/trips/data/trips_repository.dart';
import 'package:planzers/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planzers/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planzers/features/trips/presentation/trip_date_format.dart';
import 'package:planzers/features/trips/presentation/trip_participants_page.dart';
import 'package:planzers/features/trips/presentation/trip_scope.dart';
import 'package:planzers/features/trips/presentation/trip_stay_edit_dialog.dart';

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
  bool _isBannerBusy = false;
  DateTime? _editStartDate;
  DateTime? _editEndDate;
  Stream<Map<String, Map<String, dynamic>>>? _usersDataStreamCache;
  String? _usersDataStreamKey;

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

  void _openParticipantsPage({required bool readOnly}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripParticipantsPage(
          tripId: _trip.id,
          readOnly: readOnly,
        ),
      ),
    );
  }

  Future<void> _openTripStayDialog() async {
    await showTripStayEditDialog(context: context, trip: _trip);
  }

  Future<void> _toggleMyCupidonMode(bool enabled) async {
    try {
      await ref.read(cupidonRepositoryProvider).setMyTripCupidonEnabled(
            tripId: _trip.id,
            enabled: enabled,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'Mode Cupidon activé' : 'Mode Cupidon désactivé',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur mode Cupidon: $e')),
      );
    }
  }

  Future<void> _pickAndUploadBannerImage() async {
    if (_isBannerBusy) return;
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _isBannerBusy = true);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 95,
      );
      if (picked == null) {
        return;
      }
      if (!mounted) return;

      final screenSize = MediaQuery.sizeOf(context);
      final webCropWidth =
          ((screenSize.width - 140).clamp(260.0, 900.0)).round();
      final webCropHeight =
          ((screenSize.height - 320).clamp(220.0, 700.0)).round();

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Recadrer la bannière',
            toolbarColor: colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: colorScheme.primary,
            dimmedLayerColor: Colors.black54,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
          ),
          IOSUiSettings(
            title: 'Recadrer la bannière',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
          if (kIsWeb)
            WebUiSettings(
              context: context,
              presentStyle: WebPresentStyle.dialog,
              size: CropperSize(
                width: webCropWidth,
                height: webCropHeight,
              ),
            ),
        ],
      );
      if (cropped == null) {
        return;
      }
      final imagePath = cropped.path;

      final bytes = await XFile(imagePath).readAsBytes();
      final extMatch = RegExp(r'\.([a-zA-Z0-9]+)$').firstMatch(imagePath);
      final ext = extMatch?.group(1)?.toLowerCase() ?? 'jpg';
      await ref.read(tripsRepositoryProvider).upsertTripBannerImage(
            tripId: _trip.id,
            bytes: bytes,
            fileExt: ext,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo de bannière mise à jour')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur photo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBannerBusy = false);
      }
    }
  }

  Future<void> _removeBannerImage() async {
    if (_isBannerBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer la photo ?'),
        content: const Text('La bannière sera retirée du voyage.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _isBannerBusy = true);
    try {
      await ref
          .read(tripsRepositoryProvider)
          .removeTripBannerImage(tripId: _trip.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Photo supprimée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur suppression photo: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isBannerBusy = false);
      }
    }
  }

  String _initialFromLabel(String label) {
    final clean = label.trim();
    if (clean.isEmpty) return '?';
    return clean.substring(0, 1).toUpperCase();
  }

  Stream<Map<String, Map<String, dynamic>>> _usersDataStreamFor(
    List<String> memberIds,
  ) {
    final realIds = memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .where((id) => !isTripPlaceholderMemberId(id))
        .toList();
    final sorted = [...realIds]..sort();
    final key = sorted.join('\x1e');
    if (_usersDataStreamKey == key && _usersDataStreamCache != null) {
      return _usersDataStreamCache!;
    }
    _usersDataStreamKey = key;
    _usersDataStreamCache =
        ref.read(usersRepositoryProvider).watchUsersDataByIds(realIds);
    return _usersDataStreamCache!;
  }

  String _photoUrlFromUserData(Map<String, dynamic>? userData) {
    if (userData == null) return '';
    final account = (userData['account'] as Map<String, dynamic>?) ?? const {};
    final accountPhoto = (account['photoUrl'] as String?)?.trim() ?? '';
    if (accountPhoto.isNotEmpty) return accountPhoto;
    return (userData['photoUrl'] as String?)?.trim() ?? '';
  }

  DateTime _dateOnly(DateTime value) {
    final local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  String _agendaDayParam(DateTime day) {
    final local = _dateOnly(day);
    final month = local.month.toString().padLeft(2, '0');
    final dayStr = local.day.toString().padLeft(2, '0');
    return '${local.year}-$month-$dayStr';
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(tripRoomsStreamProvider(_trip.id));
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(_trip.id));
    final roomsCount = roomsAsync.asData?.value.length ?? 0;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final canEdit = (myUid != null && myUid == _trip.ownerId);
    final myCupidonEnabledAsync =
        ref.watch(myTripCupidonEnabledProvider(_trip.id));
    final myCupidonEnabled = myCupidonEnabledAsync.asData?.value ?? false;
    final tripDocStream = FirebaseFirestore.instance
        .collection('trips')
        .doc(_trip.id)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: tripDocStream,
      builder: (context, snapshot) {
        final liveData = snapshot.data?.data();
        final liveLinkUrl = (liveData?['linkUrl'] as String?) ?? _trip.linkUrl;
        final livePreview =
            (liveData?['linkPreview'] as Map<String, dynamic>?) ?? const {};
        final liveMemberIds =
            ((liveData?['memberIds'] as List<dynamic>?) ?? _trip.memberIds)
                .map((id) => id.toString())
                .toList();
        final liveMemberPublicLabels = Trip.memberPublicLabelsFromFirestore(
          liveData?['memberPublicLabels'],
        );
        final liveBannerImageUrl =
            (liveData?['bannerImageUrl'] as String?)?.trim() ??
                (_trip.bannerImageUrl ?? '').trim();
        final linkUrlForUi =
            _isEditing ? _linkController.text.trim() : liveLinkUrl.trim();
        final tripDateLabel =
            formatTripDateRange(_trip.startDate, _trip.endDate);
        final isTripMember = myUid != null &&
            liveMemberIds
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .contains(myUid);
        final canViewParticipants = canEdit || isTripMember;
        final participantsCount = liveMemberIds
            .map((id) => id.trim())
            .where((id) => id.isNotEmpty)
            .length;
        final today = _dateOnly(DateTime.now());
        final mergedMemberPublicLabels = {
          ..._trip.memberPublicLabels,
          ...liveMemberPublicLabels,
        };
        final usersStream = _usersDataStreamFor(liveMemberIds);

        return StreamBuilder<Map<String, Map<String, dynamic>>>(
          stream: usersStream,
          builder: (context, userSnap) {
            final usersDataById = userSnap.data ?? const {};
            final memberLabels = tripMemberLabelsFromUserDocsById(
              usersDataById,
              liveMemberIds,
              tripMemberPublicLabels: mergedMemberPublicLabels,
              currentUserId: myUid,
              emptyFallback: 'Voyageur',
            );
            final participantsPreview = liveMemberIds
                .map((id) => id.trim())
                .where((id) => id.isNotEmpty)
                .map((id) {
                  final label = memberLabels[id]?.trim() ?? 'Voyageur';
                  return _ParticipantBadgePreviewEntry(
                    initial: _initialFromLabel(label),
                    photoUrl: _photoUrlFromUserData(usersDataById[id]),
                  );
                })
                .toList();
            final activitiesToday = (activitiesAsync.asData?.value ?? const <TripActivity>[])
                .where((activity) => activity.plannedAt != null)
                .where((activity) => _dateOnly(activity.plannedAt!) == today)
                .toList()
              ..sort((a, b) {
                final byPlanned = a.plannedAt!.compareTo(b.plannedAt!);
                if (byPlanned != 0) return byPlanned;
                return b.createdAt.compareTo(a.createdAt);
              });
            final activitiesTodayLabels = activitiesToday
                .map((activity) => activity.label.trim())
                .where((label) => label.isNotEmpty)
                .toList();

            return ListView(
              padding: EdgeInsets.zero,
              children: [
            Stack(
              children: [
                _TripBanner(
                  imageUrl: liveBannerImageUrl,
                  busy: _isBannerBusy,
                  onPick: canEdit && liveBannerImageUrl.isEmpty
                      ? _pickAndUploadBannerImage
                      : null,
                ),
                if (!_isEditing)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [
                            Color(0xB1000000),
                            Color(0x5C000000),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 24, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _trip.title.isEmpty ? 'Sans titre' : _trip.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.white),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              _trip.destination.isEmpty
                                  ? 'Destination inconnue'
                                  : _trip.destination,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                            if (tripDateLabel.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.date_range_outlined,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tripDateLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(color: Colors.white),
                                    ),
                                  ),
                                  if (canViewParticipants)
                                    PopupMenuButton<String>(
                                      tooltip: 'Actions voyage',
                                      onSelected: (value) {
                                        if (value == 'participants') {
                                          _openParticipantsPage(
                                            readOnly: !canEdit,
                                          );
                                          return;
                                        }
                                        if (value == 'stay' && isTripMember) {
                                          unawaited(_openTripStayDialog());
                                          return;
                                        }
                                        if (value == 'share' && canEdit) {
                                          _shareInviteLink();
                                          return;
                                        }
                                        if (value == 'copyCode' && canEdit) {
                                          _copyInviteCode();
                                          return;
                                        }
                                        if (value == 'edit' && canEdit) {
                                          _startEditing();
                                          return;
                                        }
                                        if (value == 'settings' &&
                                            canViewParticipants) {
                                          context.go('/trips/${_trip.id}/settings');
                                          return;
                                        }
                                        if (value == 'cupidon' &&
                                            isTripMember) {
                                          _toggleMyCupidonMode(
                                              !myCupidonEnabled);
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        PopupMenuItem(
                                          value: 'participants',
                                          child: Row(
                                            children: [
                                              Icon(Icons
                                                  .assignment_ind_outlined),
                                              SizedBox(width: 10),
                                              Text('Participants'),
                                            ],
                                          ),
                                        ),
                                        if (isTripMember)
                                          const PopupMenuItem(
                                            value: 'stay',
                                            child: Row(
                                              children: [
                                                Icon(Icons.date_range_outlined),
                                                SizedBox(width: 10),
                                                Text('Mes dates sur le voyage'),
                                              ],
                                            ),
                                          ),
                                        if (canEdit)
                                          const PopupMenuItem(
                                            value: 'share',
                                            child: Row(
                                              children: [
                                                Icon(Icons.group_add_outlined),
                                                SizedBox(width: 10),
                                                Text('Partager invitation'),
                                              ],
                                            ),
                                          ),
                                        if (canEdit)
                                          const PopupMenuItem(
                                            value: 'copyCode',
                                            child: Row(
                                              children: [
                                                Icon(Icons.vpn_key_outlined),
                                                SizedBox(width: 10),
                                                Text('Copier le code'),
                                              ],
                                            ),
                                          ),
                                        if (canEdit)
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit_outlined),
                                                SizedBox(width: 10),
                                                Text('Modifier le voyage'),
                                              ],
                                            ),
                                          ),
                                        if (canViewParticipants)
                                          const PopupMenuItem(
                                            value: 'settings',
                                            child: Row(
                                              children: [
                                                Icon(Icons.settings_outlined),
                                                SizedBox(width: 10),
                                                Text('Paramètres du voyage'),
                                              ],
                                            ),
                                          ),
                                        if (isTripMember)
                                          PopupMenuItem(
                                            value: 'cupidon',
                                            child: Row(
                                              children: [
                                                Icon(
                                                  myCupidonEnabled
                                                      ? Icons.favorite
                                                      : Icons.favorite_border,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  myCupidonEnabled
                                                      ? 'Désactiver Cupidon'
                                                      : 'Activer Cupidon',
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                      icon: canEdit && _inviteClipboardBusy
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white),
                                            )
                                          : const Icon(Icons.more_vert,
                                              color: Colors.white),
                                    ),
                                ],
                              ),
                            ] else if (canViewParticipants) ...[
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  const Spacer(),
                                  PopupMenuButton<String>(
                                    tooltip: 'Actions voyage',
                                    onSelected: (value) {
                                      if (value == 'participants') {
                                        _openParticipantsPage(
                                          readOnly: !canEdit,
                                        );
                                        return;
                                      }
                                      if (value == 'stay' && isTripMember) {
                                        unawaited(_openTripStayDialog());
                                        return;
                                      }
                                      if (value == 'share' && canEdit) {
                                        _shareInviteLink();
                                        return;
                                      }
                                      if (value == 'copyCode' && canEdit) {
                                        _copyInviteCode();
                                        return;
                                      }
                                      if (value == 'edit' && canEdit) {
                                        _startEditing();
                                        return;
                                      }
                                      if (value == 'settings' &&
                                          canViewParticipants) {
                                        context.go('/trips/${_trip.id}/settings');
                                        return;
                                      }
                                      if (value == 'cupidon' && isTripMember) {
                                        _toggleMyCupidonMode(!myCupidonEnabled);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                        value: 'participants',
                                        child: Row(
                                          children: [
                                            Icon(Icons.assignment_ind_outlined),
                                            SizedBox(width: 10),
                                            Text('Participants'),
                                          ],
                                        ),
                                      ),
                                      if (isTripMember)
                                        const PopupMenuItem(
                                          value: 'stay',
                                          child: Row(
                                            children: [
                                              Icon(Icons.date_range_outlined),
                                              SizedBox(width: 10),
                                              Text('Mes dates sur le voyage'),
                                            ],
                                          ),
                                        ),
                                      if (canEdit)
                                        const PopupMenuItem(
                                          value: 'share',
                                          child: Row(
                                            children: [
                                              Icon(Icons.group_add_outlined),
                                              SizedBox(width: 10),
                                              Text('Partager invitation'),
                                            ],
                                          ),
                                        ),
                                      if (canEdit)
                                        const PopupMenuItem(
                                          value: 'copyCode',
                                          child: Row(
                                            children: [
                                              Icon(Icons.vpn_key_outlined),
                                              SizedBox(width: 10),
                                              Text('Copier le code'),
                                            ],
                                          ),
                                        ),
                                      if (canEdit)
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined),
                                              SizedBox(width: 10),
                                              Text('Modifier le voyage'),
                                            ],
                                          ),
                                        ),
                                      if (canViewParticipants)
                                        const PopupMenuItem(
                                          value: 'settings',
                                          child: Row(
                                            children: [
                                              Icon(Icons.settings_outlined),
                                              SizedBox(width: 10),
                                              Text('Paramètres du voyage'),
                                            ],
                                          ),
                                        ),
                                      if (isTripMember)
                                        PopupMenuItem(
                                          value: 'cupidon',
                                          child: Row(
                                            children: [
                                              Icon(
                                                myCupidonEnabled
                                                    ? Icons.favorite
                                                    : Icons.favorite_border,
                                              ),
                                              const SizedBox(width: 10),
                                              Text(
                                                myCupidonEnabled
                                                    ? 'Désactiver Cupidon'
                                                    : 'Activer Cupidon',
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                    icon: canEdit && _inviteClipboardBusy
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white),
                                          )
                                        : const Icon(Icons.more_vert,
                                            color: Colors.white),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                if (canEdit)
                  Positioned(
                    right: 12,
                    top: 12,
                    child: Material(
                      color: Colors.black45,
                      borderRadius: BorderRadius.circular(999),
                      child: PopupMenuButton<String>(
                        tooltip: 'Actions photo',
                        enabled: !_isBannerBusy,
                        onSelected: (value) {
                          if (value == 'change') {
                            _pickAndUploadBannerImage();
                            return;
                          }
                          if (value == 'remove') {
                            _removeBannerImage();
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'change',
                            child: Text('Changer de photo'),
                          ),
                          if (liveBannerImageUrl.isNotEmpty)
                            const PopupMenuItem(
                              value: 'remove',
                              child: Text('Supprimer'),
                            ),
                        ],
                        icon: _isBannerBusy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.photo_camera_outlined,
                                color: Colors.white),
                      ),
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Column(
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
                          const SizedBox(height: 8),
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('Date de début'),
                            subtitle:
                                Text(formatOptionalTripDate(_editStartDate)),
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
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
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
                            subtitle:
                                Text(formatOptionalTripDate(_editEndDate)),
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
                                  icon:
                                      const Icon(Icons.calendar_today_outlined),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: context,
                                      initialDate: _editEndDate ??
                                          _editStartDate ??
                                          DateTime.now(),
                                      firstDate:
                                          _editStartDate ?? DateTime(2000),
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
                                initialDate: _editEndDate ??
                                    _editStartDate ??
                                    DateTime.now(),
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
                              if (uri.scheme != 'http' &&
                                  uri.scheme != 'https') {
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
                    const SizedBox(height: 16),
                  ],
                  if (canEdit && _isEditing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
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
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Icon(Icons.check),
                            ),
                          ],
                        ],
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (linkUrlForUi.isNotEmpty) ...[
                            LinkPreviewCardFromFirestore(
                              url: linkUrlForUi,
                              preview: livePreview,
                              showCard: false,
                              showTitleLabel: false,
                            ),
                            const SizedBox(height: 12),
                          ],
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
                        ],
                      ),
                    ),
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _TripAccessTile(
                            label: 'Participants',
                            icon: Icons.assignment_ind_outlined,
                            countLabel: '$participantsCount',
                            alertCount: 0,
                            previewParticipants: participantsPreview,
                            onTap: () =>
                                _openParticipantsPage(readOnly: !canEdit),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TripAccessTile(
                            label: 'Activités du jour',
                            icon: Icons.event_note_outlined,
                            countLabel: '${activitiesToday.length}',
                            alertCount: 0,
                            detailLines: activitiesTodayLabels,
                            onTap: () => context.go(
                              '/trips/${_trip.id}/activities?agendaDay=${_agendaDayParam(today)}',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TripAccessTile(
                            label: 'Chambres',
                            icon: Icons.bed_outlined,
                            countLabel: '$roomsCount',
                            alertCount: 0,
                            onTap: () => context.go('/trips/${_trip.id}/rooms'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TripAccessTile(
                            label: 'Voitures',
                            icon: Icons.directions_car_outlined,
                            countLabel: '0',
                            alertCount: 0,
                            onTap: () => context.go('/trips/${_trip.id}/cars'),
                          ),
                        ),
                      ],
                    ),
                  ],
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
              ),
            ),
          ],
            );
          },
        );
      },
    );
  }
}

class _TripBanner extends StatelessWidget {
  const _TripBanner({
    required this.imageUrl,
    required this.busy,
    required this.onPick,
  });

  final String imageUrl;
  final bool busy;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPick,
      child: Container(
        height: 280,
        width: double.infinity,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: imageUrl.isNotEmpty
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                          child: Icon(Icons.broken_image_outlined, size: 42));
                    },
                  ),
                  if (busy)
                    const ColoredBox(
                      color: Colors.black26,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      ),
                    ),
                ],
              )
            : Center(
                child: busy
                    ? const CircularProgressIndicator(strokeWidth: 2.5)
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_photo_alternate_outlined,
                              size: 36),
                          const SizedBox(height: 8),
                          Text(
                            onPick == null
                                ? 'Aucune photo'
                                : 'Ajouter une photo de bannière',
                          ),
                        ],
                      ),
              ),
      ),
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
      crossAxisAlignment: CrossAxisAlignment.center,
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
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
            visualDensity: VisualDensity.compact,
            splashRadius: 18,
          ),
      ],
    );
  }
}

class _TripAccessTile extends StatelessWidget {
  const _TripAccessTile({
    required this.label,
    required this.icon,
    required this.countLabel,
    required this.alertCount,
    required this.onTap,
    this.previewParticipants = const [],
    this.detailLines = const [],
  });

  final String label;
  final IconData icon;
  final String countLabel;
  final int alertCount;
  final VoidCallback onTap;
  final List<_ParticipantBadgePreviewEntry> previewParticipants;
  final List<String> detailLines;
  static const double _kTileHeight = 146;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasPreview = previewParticipants.isNotEmpty;
    final hasDetails = detailLines.isNotEmpty;
    final visibleDetails = detailLines.take(2).toList();
    final moreDetailsCount = detailLines.length - visibleDetails.length;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            height: _kTileHeight,
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(icon, color: colorScheme.primary),
                    const Spacer(),
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Icon(
                          Icons.notifications_none_outlined,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        if (alertCount > 0)
                          Positioned(
                            right: -1,
                            top: -1,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: colorScheme.error,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  countLabel,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (hasPreview) ...[
                  const SizedBox(height: 8),
                  _ParticipantBadgesPreview(participants: previewParticipants),
                ],
                if (hasDetails) ...[
                  const SizedBox(height: 8),
                  ...[
                    for (final line in visibleDetails)
                      Text(
                        '- $line',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                  ],
                  if (moreDetailsCount > 0)
                    Text(
                      '+$moreDetailsCount activité${moreDetailsCount > 1 ? 's' : ''}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ParticipantBadgesPreview extends StatelessWidget {
  const _ParticipantBadgesPreview({required this.participants});

  final List<_ParticipantBadgePreviewEntry> participants;

  static const int _maxVisible = 5;

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(_maxVisible).toList();
    final remaining = participants.length - visible.length;
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final participant in visible)
          CircleAvatar(
            radius: 11,
            backgroundColor: colorScheme.secondaryContainer,
            foregroundColor: colorScheme.onSecondaryContainer,
            backgroundImage: participant.photoUrl.isEmpty
                ? null
                : NetworkImage(participant.photoUrl),
            child: participant.photoUrl.isEmpty
                ? Text(
                    participant.initial,
                    style: Theme.of(context).textTheme.labelSmall,
                  )
                : null,
          ),
        if (remaining > 0)
          CircleAvatar(
            radius: 11,
            backgroundColor: colorScheme.surfaceContainerHighest,
            foregroundColor: colorScheme.onSurfaceVariant,
            child: Text(
              '+$remaining',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
      ],
    );
  }
}

class _ParticipantBadgePreviewEntry {
  const _ParticipantBadgePreviewEntry({
    required this.initial,
    required this.photoUrl,
  });

  final String initial;
  final String photoUrl;
}
