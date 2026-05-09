import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/core/notifications/notification_center_repository.dart';
import 'package:planerz/core/notifications/notification_channel.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/features/carpool/data/trip_carpools_repository.dart';
import 'package:planerz/features/games/data/trip_games_repository.dart';
import 'package:planerz/features/rooms/data/rooms_repository.dart';
import 'package:planerz/app/theme/activity_filter_colors.dart';
import 'package:planerz/app/theme/static_colors.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_announcements_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_placeholder_member.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/presentation/trip_calendar_stay_bounds_field.dart';
import 'package:planerz/features/trips/presentation/trip_date_format.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';

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
  TripMemberStay? _editStayBounds;
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
      _editStayBounds = TripMemberStay.stayDraftForTripOverviewEditOrNull(trip);
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
      _editStayBounds = TripMemberStay.stayDraftForTripOverviewEditOrNull(trip);
    });
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isSaving) return;
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final bounds = _editStayBounds;
    if (bounds != null && !TripMemberStay.isChronological(bounds)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripStayInvalidRange)),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final title = _titleController.text.trim();
      final destination = _destinationController.text.trim();
      final address = _addressController.text.trim();
      final linkUrl = _linkController.text.trim();

      DateTime? startDate;
      DateTime? endDate;
      if (bounds != null) {
        startDate = TripMemberStay.parseDateKey(bounds.startDateKey);
        endDate = TripMemberStay.parseDateKey(bounds.endDateKey);
      }

      await ref.read(tripsRepositoryProvider).updateTrip(
            tripId: _trip.id,
            title: title,
            destination: destination,
            address: address,
            linkUrl: linkUrl,
            startDate: startDate,
            endDate: endDate,
            tripStartDayPart: bounds?.startDayPart,
            tripEndDayPart: bounds?.endDayPart,
          );

      if (!mounted) return;
      setState(() => _isEditing = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewUpdateError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _copyInviteCode() async {
    final l10n = AppLocalizations.of(context)!;
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
        SnackBar(content: Text(l10n.tripOverviewInviteCodeCopied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(l10n.tripOverviewInviteCodeCopyError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _inviteClipboardBusy = false);
      }
    }
  }

  void _openParticipantsPage() {
    context.push('/trips/${_trip.id}/participants');
  }

  void _openAnnouncementsPage() {
    context.push('/trips/${_trip.id}/announcements');
  }

  void _openTripUserPreferencesPage() {
    context.push('/trips/${_trip.id}/preferences');
  }

  Future<void> _openLinkUrl(String url) async {
    final l10n = AppLocalizations.of(context)!;
    final parsedUrl = Uri.tryParse(url.trim());
    if (parsedUrl == null || !parsedUrl.isAbsolute) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkInvalid)),
      );
      return;
    }

    final launched = await launchUrl(
      parsedUrl,
      mode: LaunchMode.platformDefault,
      webOnlyWindowName: '_blank',
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.linkOpenImpossible)),
      );
    }
  }

  Future<void> _pickAndUploadBannerImage() async {
    final l10n = AppLocalizations.of(context)!;
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
            toolbarTitle: l10n.tripOverviewCropBanner,
            toolbarColor: colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: colorScheme.primary,
            dimmedLayerColor: Colors.black54,
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
          ),
          IOSUiSettings(
            title: l10n.tripOverviewCropBanner,
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
        SnackBar(content: Text(l10n.tripOverviewBannerUpdated)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isBannerBusy = false);
      }
    }
  }

  Future<void> _removeBannerImage() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isBannerBusy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.accountRemovePhotoDialogTitle),
        content: Text(l10n.tripOverviewBannerRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.commonDelete),
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
        SnackBar(content: Text(l10n.accountPhotoDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.accountPhotoDeleteError(e.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isBannerBusy = false);
      }
    }
  }

  Future<void> _confirmAndDeleteTrip() async {
    final l10n = AppLocalizations.of(context)!;
    final tripId = _trip.id;
    final tripTitle = _trip.title;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.tripsDeleteDialogTitle),
          content: Text(l10n.tripsDeleteDialogBody(tripTitle)),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            OutlinedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonDelete),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    try {
      await ref.read(tripsRepositoryProvider).deleteTrip(tripId: tripId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      context.go('/trips');
      messenger.showSnackBar(SnackBar(content: Text(l10n.tripsDeleted)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripsDeleteError(e.toString()))),
      );
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
    final l10n = AppLocalizations.of(context)!;
    final roomsAsync = ref.watch(tripRoomsStreamProvider(_trip.id));
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(_trip.id));
    final announcementsAsync =
        ref.watch(tripAnnouncementsStreamProvider(_trip.id));
    final activitiesCountersAsync =
        ref.watch(tripNotificationCountersProvider(_trip.id));
    final announcementsLastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: _trip.id, channel: TripNotificationChannel.announcements),
      ),
    );
    final activitiesLastReadAtAsync = ref.watch(
      tripChannelLastReadAtProvider(
        (tripId: _trip.id, channel: TripNotificationChannel.activities),
      ),
    );
    final rooms = roomsAsync.asData?.value ?? const [];
    final carpools =
        ref.watch(tripCarpoolsStreamProvider(_trip.id)).asData?.value ??
            const [];
    final boardGames =
        ref.watch(tripBoardGamesStreamProvider(_trip.id)).asData?.value ??
            const [];
    final boardGamesCount = boardGames.length;
    final boardGamesDetailLines = boardGames
        .map((game) => game.name.trim())
        .where((name) => name.isNotEmpty)
        .toList()
      ..shuffle();
    final roomsCount = rooms.length;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final myAssignedRoomNames = myUid == null
        ? const <String>[]
        : rooms
            .where((room) => room.assignedMemberIds.contains(myUid))
            .map(
              (room) => room.name.trim().isEmpty
                  ? l10n.roomsUnnamedRoom
                  : room.name.trim(),
            )
            .toList();
    final roomsDetailLines = myAssignedRoomNames.isEmpty
        ? const <String>[]
        : [
            myAssignedRoomNames.length == 1
                ? l10n.tripOverviewMyRoom
                : l10n.tripOverviewMyRooms,
            myAssignedRoomNames.join(', '),
          ];
    final currentRole = resolveTripPermissionRole(
      trip: _trip,
      userId: myUid,
    );
    final canEdit = (myUid != null && myUid == _trip.ownerId);
    final canManageBanner = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.manageBannerMinRole,
    );
    final canShareAccess = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.shareAccessMinRole,
    );
    final canManageTripSettings = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.manageTripSettingsMinRole,
    );
    final canEditGeneralInfo = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.editGeneralInfoMinRole,
    );
    final canDeleteTrip = canEdit;
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
        final photosStorageUrl =
            ((liveData?['photosStorageUrl'] as String?) ?? '').trim();
        final tripDateLabel =
            formatTripDateRange(context, _trip.startDate, _trip.endDate);
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
            }).toList();
            final TripCarpool? myCarpool = myUid == null
                ? null
                : carpools.cast<TripCarpool?>().firstWhere(
                      (entry) =>
                          entry?.assignedParticipantIds.contains(myUid) == true,
                      orElse: () => null,
                    );
            final myCarpoolDetailLines = <String>[
              if (myCarpool != null && myUid != null && myUid.trim().isNotEmpty)
                ...() {
                  final departureTime =
                      MaterialLocalizations.of(context).formatTimeOfDay(
                    TimeOfDay.fromDateTime(myCarpool.departureAt),
                    alwaysUse24HourFormat: true,
                  );
                  final meetingPointLabel =
                      myCarpool.meetingPointAddress.trim();
                  final driverLabel = (memberLabels[myCarpool.driverUserId] ??
                          l10n.tripParticipantsTraveler)
                      .trim();
                  final passengerIds = myCarpool.assignedParticipantIds
                      .map((id) => id.trim())
                      .where((id) => id.isNotEmpty)
                      .where((id) => id != myCarpool.driverUserId.trim())
                      .toList(growable: false);
                  final passengerLabels = passengerIds
                      .map(
                        (id) => (memberLabels[id]?.trim().isNotEmpty == true)
                            ? memberLabels[id]!.trim()
                            : l10n.tripParticipantsTraveler,
                      )
                      .toList(growable: false);
                  final passengersLabel = passengerLabels.isEmpty
                      ? l10n.tripOverviewCarpoolNoPassengersPlaceholder
                      : passengerLabels.join(', ');
                  final isDriver =
                      myUid.trim() == myCarpool.driverUserId.trim();

                  return <String>[
                    isDriver
                        ? l10n.tripOverviewCarpoolDriverSummary(
                            passengersLabel,
                            departureTime,
                          )
                        : meetingPointLabel.isEmpty
                            ? l10n
                                .tripOverviewCarpoolPassengerSummaryNoMeetingPoint(
                                driverLabel,
                                departureTime,
                              )
                            : l10n.tripOverviewCarpoolPassengerSummary(
                                driverLabel,
                                departureTime,
                                meetingPointLabel,
                              ),
                    if (myCarpool.goesShopping)
                      l10n.tripOverviewCarpoolShoppingTeamLine,
                  ];
                }(),
            ];
            final activitiesCounters = activitiesCountersAsync.asData?.value;
            var unreadActivities = 0;
            var unreadAnnouncements = 0;
            if (activitiesCounters != null &&
                activitiesCounters
                    .hasChannel(TripNotificationChannel.activities)) {
              unreadActivities = activitiesCounters
                  .unreadFor(TripNotificationChannel.activities);
            } else if (myUid != null && myUid.isNotEmpty) {
              final allActivities = activitiesAsync.asData?.value;
              final lastReadAt =
                  activitiesLastReadAtAsync.asData?.value?.toUtc();
              if (allActivities != null) {
                unreadActivities = allActivities.where((activity) {
                  if (activity.createdBy == myUid) return false;
                  if (lastReadAt == null) return true;
                  return activity.createdAt.toUtc().isAfter(lastReadAt);
                }).length;
              }
            }
            if (activitiesCounters != null &&
                activitiesCounters
                    .hasChannel(TripNotificationChannel.announcements)) {
              unreadAnnouncements = activitiesCounters
                  .unreadFor(TripNotificationChannel.announcements);
            } else if (myUid != null && myUid.isNotEmpty) {
              final allAnnouncements = announcementsAsync.asData?.value;
              final lastReadAt =
                  announcementsLastReadAtAsync.asData?.value?.toUtc();
              if (allAnnouncements != null) {
                unreadAnnouncements = allAnnouncements.where((announcement) {
                  if (announcement.authorId == myUid) return false;
                  if (lastReadAt == null) return true;
                  return announcement.createdAt.toUtc().isAfter(lastReadAt);
                }).length;
              }
            }

            final activitiesToday = (activitiesAsync.asData?.value ??
                    const <TripActivity>[])
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
            final plannedActivitiesCount =
                (activitiesAsync.asData?.value ?? const <TripActivity>[])
                    .where((activity) => activity.plannedAt != null)
                    .length;

            return ListView(
              padding: EdgeInsets.zero,
              children: [
                Stack(
                  children: [
                    _TripBanner(
                      imageUrl: liveBannerImageUrl,
                      busy: _isBannerBusy,
                      onPick: canManageBanner && liveBannerImageUrl.isEmpty
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
                                Color(0xCC2E206D),
                                Color(0x662E206D),
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
                                  _trip.title.isEmpty
                                      ? l10n.tripOverviewUntitled
                                      : _trip.title,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _trip.destination.isEmpty
                                      ? l10n.tripOverviewUnknownDestination
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
                                          tooltip: l10n.tripOverviewActions,
                                          onSelected: (value) {
                                            if (value == 'preferences' &&
                                                isTripMember) {
                                              _openTripUserPreferencesPage();
                                              return;
                                            }
                                            if (value == 'copyCode' &&
                                                canShareAccess) {
                                              _copyInviteCode();
                                              return;
                                            }
                                            if (value == 'edit' &&
                                                canEditGeneralInfo) {
                                              _startEditing();
                                              return;
                                            }
                                            if (value == 'settings' &&
                                                canManageTripSettings) {
                                              context.go(
                                                  '/trips/${_trip.id}/settings');
                                              return;
                                            }
                                            if (value == 'delete' &&
                                                canDeleteTrip) {
                                              _confirmAndDeleteTrip();
                                              return;
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            if (isTripMember)
                                              PopupMenuItem(
                                                value: 'preferences',
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                        Icons.tune_outlined),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      l10n.tripUserPreferencesMenuAction,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            if (canShareAccess)
                                              PopupMenuItem(
                                                value: 'copyCode',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                        Icons.vpn_key_outlined),
                                                    SizedBox(width: 10),
                                                    Text(l10n
                                                        .tripOverviewCopyCode),
                                                  ],
                                                ),
                                              ),
                                            if (canEditGeneralInfo)
                                              PopupMenuItem(
                                                value: 'edit',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.edit_outlined),
                                                    SizedBox(width: 10),
                                                    Text(l10n
                                                        .tripOverviewEditTrip),
                                                  ],
                                                ),
                                              ),
                                            if (canManageTripSettings)
                                              PopupMenuItem(
                                                value: 'settings',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons
                                                        .settings_outlined),
                                                    SizedBox(width: 10),
                                                    Text(
                                                        l10n.tripSettingsTitle),
                                                  ],
                                                ),
                                              ),
                                            if (canDeleteTrip) ...[
                                              const PopupMenuDivider(),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.delete_outline,
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Text(
                                                      l10n.commonDelete,
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ],
                                          icon: canEdit && _inviteClipboardBusy
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
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
                                        tooltip: l10n.tripOverviewActions,
                                        onSelected: (value) {
                                          if (value == 'preferences' &&
                                              isTripMember) {
                                            _openTripUserPreferencesPage();
                                            return;
                                          }
                                          if (value == 'copyCode' &&
                                              canShareAccess) {
                                            _copyInviteCode();
                                            return;
                                          }
                                          if (value == 'edit' &&
                                              canEditGeneralInfo) {
                                            _startEditing();
                                            return;
                                          }
                                          if (value == 'settings' &&
                                              canManageTripSettings) {
                                            context.go(
                                                '/trips/${_trip.id}/settings');
                                            return;
                                          }
                                          if (value == 'delete' &&
                                              canDeleteTrip) {
                                            _confirmAndDeleteTrip();
                                            return;
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (isTripMember)
                                            PopupMenuItem(
                                              value: 'preferences',
                                              child: Row(
                                                children: [
                                                  const Icon(
                                                      Icons.tune_outlined),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    l10n.tripUserPreferencesMenuAction,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (canShareAccess)
                                            PopupMenuItem(
                                              value: 'copyCode',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.vpn_key_outlined),
                                                  SizedBox(width: 10),
                                                  Text(l10n
                                                      .tripOverviewCopyCode),
                                                ],
                                              ),
                                            ),
                                          if (canEditGeneralInfo)
                                            PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit_outlined),
                                                  SizedBox(width: 10),
                                                  Text(l10n
                                                      .tripOverviewEditTrip),
                                                ],
                                              ),
                                            ),
                                          if (canManageTripSettings)
                                            PopupMenuItem(
                                              value: 'settings',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.settings_outlined),
                                                  SizedBox(width: 10),
                                                  Text(l10n.tripSettingsTitle),
                                                ],
                                              ),
                                            ),
                                          if (canDeleteTrip) ...[
                                            const PopupMenuDivider(),
                                            PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.delete_outline,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .error,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    l10n.commonDelete,
                                                    style: TextStyle(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ],
                                        icon: canEdit && _inviteClipboardBusy
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
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
                    if (canManageBanner)
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Material(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(999),
                          child: PopupMenuButton<String>(
                            tooltip: l10n.tripOverviewPhotoActions,
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
                              PopupMenuItem(
                                value: 'change',
                                child: Text(l10n.tripOverviewChangePhoto),
                              ),
                              if (liveBannerImageUrl.isNotEmpty)
                                PopupMenuItem(
                                  value: 'remove',
                                  child: Text(l10n.commonDelete),
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
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                  child: _TripOverviewTopSwitch(
                    leftLabel: l10n.tripOverviewTopTabAnnouncements,
                    leftAlertCount: unreadAnnouncements,
                    onLeftTap: _openAnnouncementsPage,
                    thirdLabel: photosStorageUrl.isNotEmpty ? 'Photos' : null,
                    onThirdTap: photosStorageUrl.isNotEmpty
                        ? () => _openLinkUrl(photosStorageUrl)
                        : null,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
                                decoration: InputDecoration(
                                  labelText: l10n.tripsTitleLabel,
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.tripOverviewTitleRequired;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _destinationController,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: l10n.tripsDestinationLabel,
                                  border: const OutlineInputBorder(),
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return l10n.tripOverviewDestinationRequired;
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 8),
                              if (_editStayBounds == null)
                                FilledButton.tonal(
                                  onPressed: _isSaving
                                      ? null
                                      : () => setState(() {
                                            _editStayBounds = TripMemberStay
                                                .defaultForNewTripEditor();
                                          }),
                                  child:
                                      Text(l10n.tripOverviewEditAddTripDates),
                                )
                              else ...[
                                TripCalendarStayBoundsField(
                                  tripStartDate: null,
                                  tripEndDate: null,
                                  value: _editStayBounds!,
                                  onChanged: (next) =>
                                      setState(() => _editStayBounds = next),
                                ),
                                Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: TextButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () => setState(
                                              () => _editStayBounds = null,
                                            ),
                                    child: Text(
                                        l10n.tripOverviewEditRemoveTripDates),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _addressController,
                                textInputAction: TextInputAction.next,
                                decoration: InputDecoration(
                                  labelText: l10n.tripOverviewAddressLabel,
                                  hintText: l10n.tripOverviewAddressHint,
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _linkController,
                                textInputAction: TextInputAction.done,
                                decoration: InputDecoration(
                                  labelText: l10n.tripOverviewLinkLabel,
                                  hintText: l10n.tripOverviewLinkHint,
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.url,
                                validator: (value) {
                                  final v = (value ?? '').trim();
                                  if (v.isEmpty) return null;
                                  final uri = Uri.tryParse(v);
                                  if (uri == null || !uri.isAbsolute) {
                                    return l10n.tripOverviewLinkInvalid;
                                  }
                                  if (uri.scheme != 'http' &&
                                      uri.scheme != 'https') {
                                    return l10n
                                        .tripOverviewLinkMustStartWithHttp;
                                  }
                                  return null;
                                },
                                onFieldSubmitted: (_) => _save(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                      ] else ...[
                        const SizedBox(height: 10),
                      ],
                      if (canEditGeneralInfo && _isEditing)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (_isEditing) ...[
                                IconButton(
                                  tooltip: l10n.commonCancel,
                                  onPressed: _isSaving ? null : _cancelEditing,
                                  icon: const Icon(Icons.close),
                                ),
                                IconButton(
                                  tooltip: l10n.commonSave,
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
                      if (linkUrlForUi.isNotEmpty)
                        Builder(builder: (context) {
                          final cs = Theme.of(context).colorScheme;
                          final isMapsLink =
                              livePreview['isGoogleMaps'] == true;
                          final hasAddress = _trip.address.trim().isNotEmpty;
                          final showDirections = isMapsLink || hasAddress;
                          return LinkPreviewCompact(
                            url: linkUrlForUi,
                            preview: livePreview,
                            trailing: showDirections
                                ? IconButton(
                                    tooltip: l10n.tripOverviewOpenLocation,
                                    icon: const Icon(
                                      Icons.directions_outlined,
                                    ),
                                    color: cs.tertiary,
                                    onPressed: () {
                                      if (isMapsLink) {
                                        _openLinkUrl(linkUrlForUi);
                                      } else {
                                        openAddressInGoogleMaps(
                                          context,
                                          _trip.address,
                                        );
                                      }
                                    },
                                  )
                                : null,
                          );
                        }),
                      if (!_isEditing) ...[
                        const SizedBox(height: 12),
                        Builder(builder: (context) {
                          final cs = Theme.of(context).colorScheme;
                          const tileSpacing = 10.0;
                          return Theme(
                            data: Theme.of(context).copyWith(
                              cardTheme: CardThemeData(
                                color: StaticColors.cardBackground,
                                elevation: 4,
                                shadowColor: StaticColors.cardShadowColor,
                                surfaceTintColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: const BorderSide(
                                    color: StaticColors.cardBorder,
                                  ),
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _TripAccessTile(
                                  label: l10n.tripOverviewTileParticipants,
                                  icon: Icons.assignment_ind_outlined,
                                  countLabel: '$participantsCount',
                                  iconColor: cs.primary,
                                  previewParticipants: participantsPreview,
                                  onTap: _openParticipantsPage,
                                ),
                                const SizedBox(height: tileSpacing),
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _CategoryAccessTile(
                                          label: l10n.tripOverviewTileActivities,
                                          icon: Icons.event_note_outlined,
                                          countLabel: '$plannedActivitiesCount',
                                          viewLabel:
                                              l10n.tripOverviewViewActivities,
                                          primaryColor: ActivityFilterGroup
                                              .loisirs.filterColor,
                                          lightBgColor: ActivityFilterGroup
                                              .loisirs.filterLightBgColor,
                                          borderColor: ActivityFilterGroup
                                              .loisirs.filterBorderColor,
                                          alertCount: unreadActivities,
                                          detailLines: activitiesTodayLabels,
                                          wrapDetailLines: true,
                                          emptyStateMessage: l10n
                                              .tripOverviewTileNoActivitiesToday,
                                          onTap: () => context.go(
                                            '/trips/${_trip.id}/activities?agendaDay=${_agendaDayParam(today)}',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: tileSpacing),
                                      Expanded(
                                        child: _CategoryAccessTile(
                                          label: l10n.tripOverviewTileRooms,
                                          icon: Icons.bed_outlined,
                                          countLabel: '$roomsCount',
                                          viewLabel: l10n.tripOverviewViewRooms,
                                          primaryColor: ActivityFilterGroup
                                              .nuits.filterColor,
                                          lightBgColor: ActivityFilterGroup
                                              .nuits.filterLightBgColor,
                                          borderColor: ActivityFilterGroup
                                              .nuits.filterBorderColor,
                                          detailLines: roomsDetailLines,
                                          wrapDetailLines: true,
                                          emphasizedDetailLineIndex: 1,
                                          emptyStateMessage: l10n
                                              .tripOverviewTileNoAssignedRoom,
                                          onTap: () => context
                                              .go('/trips/${_trip.id}/rooms'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: tileSpacing),
                                IntrinsicHeight(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Expanded(
                                        child: _CategoryAccessTile(
                                          label: l10n.tripOverviewTileCarpool,
                                          icon: Icons.directions_car_outlined,
                                          countLabel: '${carpools.length}',
                                          viewLabel:
                                              l10n.tripOverviewViewCarpool,
                                          primaryColor: ActivityFilterGroup
                                              .trajets.filterColor,
                                          lightBgColor: ActivityFilterGroup
                                              .trajets.filterLightBgColor,
                                          borderColor: ActivityFilterGroup
                                              .trajets.filterBorderColor,
                                          detailLines: myCarpoolDetailLines,
                                          wrapDetailLines: true,
                                          emptyStateMessage:
                                              l10n.tripCarpoolTileNoAssignment,
                                          onTap: () => context
                                              .go('/trips/${_trip.id}/carpool'),
                                        ),
                                      ),
                                      const SizedBox(width: tileSpacing),
                                      Expanded(
                                        child: _CategoryAccessTile(
                                          label: l10n.tripOverviewTileGames,
                                          icon: Icons.sports_esports_outlined,
                                          countLabel: '$boardGamesCount',
                                          viewLabel: l10n.tripOverviewViewGames,
                                          primaryColor: ActivityFilterGroup
                                              .loisirs.filterColor,
                                          lightBgColor: ActivityFilterGroup
                                              .loisirs.filterLightBgColor,
                                          borderColor: ActivityFilterGroup
                                              .loisirs.filterBorderColor,
                                          detailLines: boardGamesDetailLines,
                                          wrapDetailLines: true,
                                          moreDetailsLabelBuilder:
                                              (extraCount) => l10n
                                                  .tripOverviewTileGamesAndMore(
                                                      extraCount),
                                          emptyStateMessage:
                                              l10n.tripOverviewTileNoBoardGames,
                                          onTap: () => context
                                              .push('/trips/${_trip.id}/games'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
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
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFFF2F4FD),
              const Color(0xFFD2DAF8),
            ],
          ),
        ),
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
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 36,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(height: 8),
                          Text(
                            onPick == null
                                ? 'Aucune photo'
                                : 'Ajouter une photo de bannière',
                            style: TextStyle(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
              ),
      ),
    );
  }
}

class _TripOverviewTopSwitch extends StatelessWidget {
  const _TripOverviewTopSwitch({
    required this.leftLabel,
    this.leftAlertCount = 0,
    required this.onLeftTap,
    this.thirdLabel,
    this.onThirdTap,
  });

  final String leftLabel;
  final int leftAlertCount;
  final VoidCallback onLeftTap;
  final String? thirdLabel;
  final VoidCallback? onThirdTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        );
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: _TripOverviewTopSwitchItem(
              label: leftLabel,
              icon: Icons.campaign_outlined,
              alertCount: leftAlertCount,
              color: cs.primaryContainer,
              foregroundColor: cs.onPrimaryContainer,
              borderColor: cs.outlineVariant,
              textStyle: labelStyle,
              onTap: onLeftTap,
            ),
          ),
          if (thirdLabel != null && onThirdTap != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: _TripOverviewTopSwitchItem(
                label: thirdLabel!,
                icon: Icons.photo_library_outlined,
                color: cs.tertiaryContainer,
                foregroundColor: cs.onTertiaryContainer,
                borderColor: cs.outlineVariant,
                textStyle: labelStyle,
                onTap: onThirdTap!,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TripOverviewTopSwitchItem extends StatelessWidget {
  const _TripOverviewTopSwitchItem({
    required this.label,
    required this.icon,
    this.alertCount = 0,
    required this.color,
    required this.foregroundColor,
    required this.borderColor,
    required this.textStyle,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int alertCount;
  final Color color;
  final Color foregroundColor;
  final Color borderColor;
  final TextStyle? textStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 0.8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor.withValues(alpha: 0.75)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: foregroundColor),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(color: foregroundColor),
                ),
              ),
              if (alertCount > 0) ...[
                const SizedBox(width: 6),
                Badge.count(
                  count: alertCount,
                  child: const SizedBox(width: 10, height: 10),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TripAccessTile extends StatelessWidget {
  const _TripAccessTile({
    required this.label,
    required this.icon,
    required this.countLabel,
    required this.onTap,
    this.iconColor,
    this.previewParticipants = const [],
  });

  final String label;
  final IconData icon;
  final String countLabel;
  final VoidCallback onTap;
  final Color? iconColor;
  final List<_ParticipantBadgePreviewEntry> previewParticipants;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    countLabel,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, color: iconColor ?? colorScheme.primary),
                ],
              ),
              const SizedBox(height: 10),
              _ParticipantBadgesPreview(participants: previewParticipants),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryAccessTile extends StatelessWidget {
  const _CategoryAccessTile({
    required this.label,
    required this.icon,
    required this.countLabel,
    required this.viewLabel,
    required this.primaryColor,
    required this.lightBgColor,
    required this.borderColor,
    required this.onTap,
    this.alertCount = 0,
    this.detailLines = const [],
    this.wrapDetailLines = false,
    this.emphasizedDetailLineIndex,
    this.emptyStateMessage,
    this.moreDetailsLabelBuilder,
  });

  final String label;
  final IconData icon;
  final String countLabel;
  final String viewLabel;
  final Color primaryColor;
  final Color lightBgColor;
  final Color borderColor;
  final VoidCallback onTap;
  final int alertCount;
  final List<String> detailLines;
  final bool wrapDetailLines;
  final int? emphasizedDetailLineIndex;
  final String? emptyStateMessage;
  final String Function(int count)? moreDetailsLabelBuilder;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasDetails = detailLines.isNotEmpty;
    final visibleDetails = detailLines.take(3).toList();
    final moreDetailsCount = detailLines.length - visibleDetails.length;

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    countLabel,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: primaryColor,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Badge.count(
                    count: alertCount,
                    isLabelVisible: alertCount > 0,
                    child: Icon(icon, color: primaryColor, size: 22),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: hasDetails
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < visibleDetails.length; i++)
                            Text(
                              visibleDetails[i],
                              maxLines: wrapDetailLines ? null : 1,
                              overflow: wrapDetailLines
                                  ? TextOverflow.visible
                                  : TextOverflow.ellipsis,
                              softWrap: true,
                              textAlign: TextAlign.center,
                              style: (emphasizedDetailLineIndex == i
                                      ? Theme.of(context).textTheme.titleSmall
                                      : Theme.of(context).textTheme.bodySmall)
                                  ?.copyWith(
                                color: emphasizedDetailLineIndex == i
                                    ? primaryColor
                                    : colorScheme.onSurfaceVariant,
                                fontWeight: emphasizedDetailLineIndex == i
                                    ? FontWeight.w700
                                    : null,
                              ),
                            ),
                          if (moreDetailsCount > 0)
                            Text(
                              moreDetailsLabelBuilder?.call(moreDetailsCount) ??
                                  '+$moreDetailsCount',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                        ],
                      )
                    : emptyStateMessage != null
                        ? Text(
                            emptyStateMessage!,
                            textAlign: TextAlign.center,
                            softWrap: true,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                          )
                        : const SizedBox.shrink(),
              ),
              const Spacer(),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: lightBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        viewLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: primaryColor,
                                  fontWeight: FontWeight.w600,
                                ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        color: primaryColor, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ParticipantBadgesPreview extends StatelessWidget {
  const _ParticipantBadgesPreview({required this.participants});

  final List<_ParticipantBadgePreviewEntry> participants;

  static const double _radius = 13;
  static const double _diameter = _radius * 2;
  static const double _minStep = 18;
  static const double _maxStep = _diameter + 6;
  static const int _maxVisible = 14;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final total = participants.length;
        if (total == 0) return const SizedBox.shrink();

        // Max badges that can fit without going below minStep, capped at _maxVisible
        final maxFit = total == 1
            ? 1
            : (((available - _diameter) / _minStep).floor() + 1)
                .clamp(1, _maxVisible);

        final int visibleCount;
        final int remaining;
        if (total <= maxFit) {
          visibleCount = total;
          remaining = 0;
        } else {
          visibleCount = maxFit - 1; // reserve last slot for +X
          remaining = total - visibleCount;
        }

        final n = visibleCount + (remaining > 0 ? 1 : 0);
        final double step = n <= 1
            ? 0
            : ((available - _diameter) / (n - 1)).clamp(_minStep, _maxStep);
        final double rowWidth = n <= 1 ? _diameter : (n - 1) * step + _diameter;
        final bool centered = remaining == 0 && rowWidth < available;

        return Align(
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          child: SizedBox(
            width: rowWidth,
            height: _diameter,
            child: Stack(
              children: [
              for (int i = 0; i < visibleCount; i++)
                Positioned(
                  left: i * step,
                  child: CircleAvatar(
                    radius: _radius,
                    backgroundColor: colorScheme.secondaryContainer,
                    foregroundColor: colorScheme.onSecondaryContainer,
                    foregroundImage: participants[i].photoUrl.isEmpty
                        ? null
                        : NetworkImage(participants[i].photoUrl),
                    child: Text(participants[i].initial, style: labelStyle),
                  ),
                ),
              if (remaining > 0)
                Positioned(
                  left: visibleCount * step,
                  child: CircleAvatar(
                    radius: _radius,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    foregroundColor: colorScheme.onSurfaceVariant,
                    child: Text('+$remaining', style: labelStyle),
                  ),
                ),
            ],
          ),
          ),
        );
      },
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
