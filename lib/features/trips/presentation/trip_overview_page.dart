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
import 'package:url_launcher/url_launcher.dart';
import 'package:planerz/l10n/app_localizations.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/activities/data/activities_repository.dart';
import 'package:planerz/features/activities/data/trip_activity.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/features/carpool/data/trip_carpools_repository.dart';
import 'package:planerz/features/games/data/trip_games_repository.dart';
import 'package:planerz/features/rooms/data/rooms_repository.dart';
import 'package:planerz/app/theme/neon_palette.dart';
import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/open_route_in_map_apps.dart';
import 'package:planerz/features/trips/presentation/trip_create_page.dart';
import 'package:planerz/features/trips/presentation/trip_date_format.dart';
import 'package:planerz/features/trips/presentation/trip_overview_ui.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';

class TripOverviewPage extends ConsumerStatefulWidget {
  const TripOverviewPage({super.key});

  @override
  ConsumerState<TripOverviewPage> createState() => _TripOverviewPageState();
}

class _TripOverviewPageState extends ConsumerState<TripOverviewPage> {
  bool _inviteCodeBusy = false;
  bool _isBannerBusy = false;
  bool _isLeavingTrip = false;
  String? _inviteCode;
  bool _inviteCodeLoadStarted = false;
  Stream<Map<String, Map<String, dynamic>>>? _usersDataStreamCache;
  String? _usersDataStreamKey;

  Trip get _trip => TripScope.of(context);

  void _scheduleInviteCodeLoadIfMember(bool isTripMember) {
    if (!isTripMember || _inviteCodeLoadStarted || _inviteCode != null) return;
    _inviteCodeLoadStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadInviteCode());
    });
  }

  Future<void> _loadInviteCode() async {
    try {
      final token =
          await ref.read(tripsRepositoryProvider).getOrCreateInviteToken(
                tripId: _trip.id,
              );
      if (!mounted) return;
      setState(() => _inviteCode = token);
    } catch (_) {
      if (mounted) {
        setState(() => _inviteCodeLoadStarted = false);
      }
    }
  }

  void _openEditTripPage() {
    context.push(TripCreatePage.editRoutePath(_trip.id));
  }

  Future<void> _shareInviteCode() async {
    final l10n = AppLocalizations.of(context)!;
    if (_inviteCodeBusy) return;
    setState(() => _inviteCodeBusy = true);
    try {
      final token = _inviteCode ??
          await ref.read(tripsRepositoryProvider).getOrCreateInviteToken(
                tripId: _trip.id,
              );
      if (_inviteCode == null && mounted) {
        setState(() => _inviteCode = token);
      }
      await Clipboard.setData(ClipboardData(text: token));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.tripOverviewInviteCodeCopied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.tripOverviewInviteCodeCopyError(e.toString())),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _inviteCodeBusy = false);
      }
    }
  }

  void _openParticipantsPage() {
    context.push('/trips/${_trip.id}/participants');
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

  Future<void> _showBannerPhotoMenu(String liveBannerImageUrl) async {
    final l10n = AppLocalizations.of(context)!;
    if (_isBannerBusy) return;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: Text(l10n.tripOverviewChangePhoto),
              onTap: () => Navigator.of(ctx).pop('change'),
            ),
            if (liveBannerImageUrl.isNotEmpty)
              ListTile(
                leading: Icon(Icons.delete_outline,
                    color: Theme.of(ctx).colorScheme.error),
                title: Text(
                  l10n.commonDelete,
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                ),
                onTap: () => Navigator.of(ctx).pop('remove'),
              ),
          ],
        ),
      ),
    );
    if (action == 'change') {
      await _pickAndUploadBannerImage();
    } else if (action == 'remove') {
      await _removeBannerImage();
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

  Future<void> _confirmAndLeaveTrip() async {
    final l10n = AppLocalizations.of(context)!;
    if (_isLeavingTrip) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.tripOverviewLeaveTripTitle),
        content: Text(l10n.tripOverviewLeaveTripDialogBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.tripOverviewLeaveAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isLeavingTrip = true);
    try {
      await ref.read(tripsRepositoryProvider).leaveTripAsMember(
            tripId: _trip.id,
          );
      if (!mounted) return;
      context.go('/trips');
    } catch (error) {
      if (!mounted) return;
      final message = error is FirebaseFunctionsException &&
              error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : l10n.commonErrorWithDetails(error.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _isLeavingTrip = false);
      }
    }
  }

  Stream<Map<String, Map<String, dynamic>>> _usersDataStreamFor(
    List<String> memberIds,
  ) {
    final realIds = memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
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

  DateTime _resolvedAgendaDay(DateTime today) {
    final start = _trip.startDate != null ? _dateOnly(_trip.startDate!) : null;
    final end = _trip.endDate != null ? _dateOnly(_trip.endDate!) : null;
    if (start == null && end == null) return today;
    if (end != null && today.isAfter(end)) return end;
    if (start != null && today.isBefore(start)) return start;
    return today;
  }

  String _moduleStatusText({
    required List<String> detailLines,
    required String? emptyStateMessage,
    String Function(int count)? moreDetailsLabelBuilder,
  }) {
    if (detailLines.isEmpty) {
      return emptyStateMessage ?? '';
    }
    final visible = detailLines.take(2).join(', ');
    final extra = detailLines.length - 2;
    if (extra <= 0) return visible;
    final suffix = moreDetailsLabelBuilder?.call(extra) ?? '+$extra';
    return '$visible $suffix';
  }

  List<TripOverviewSettingsRowData> _settingsRows({
    required AppLocalizations l10n,
    required bool isTripMember,
    required bool canEditGeneralInfo,
    required bool canManageTripSettings,
    required bool canDeleteTrip,
  }) {
    final rows = <TripOverviewSettingsRowData>[];
    if (isTripMember) {
      rows.add(
        TripOverviewSettingsRowData(
          icon: Icons.tune_outlined,
          label: l10n.tripUserPreferencesMenuAction,
          onTap: _openTripUserPreferencesPage,
        ),
      );
    }
    if (canEditGeneralInfo) {
      rows.add(
        TripOverviewSettingsRowData(
          icon: Icons.edit_outlined,
          label: l10n.tripOverviewEditTrip,
          onTap: _openEditTripPage,
        ),
      );
    }
    if (canManageTripSettings) {
      rows.add(
        TripOverviewSettingsRowData(
          icon: Icons.settings_outlined,
          label: l10n.tripSettingsTitle,
          onTap: () => context.go('/trips/${_trip.id}/settings'),
        ),
      );
    }
    if (canDeleteTrip) {
      rows.add(
        TripOverviewSettingsRowData(
          icon: Icons.delete_outline,
          label: l10n.commonDelete,
          onTap: _confirmAndDeleteTrip,
          danger: true,
        ),
      );
    } else if (isTripMember) {
      rows.add(
        TripOverviewSettingsRowData(
          icon: Icons.logout,
          label: l10n.tripOverviewLeaveTripCardTitle,
          onTap: _confirmAndLeaveTrip,
          danger: true,
        ),
      );
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final roomsAsync = ref.watch(tripRoomsStreamProvider(_trip.id));
    final activitiesAsync = ref.watch(tripActivitiesStreamProvider(_trip.id));
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
    final participants =
        ref.watch(tripParticipantsStreamProvider(_trip.id)).asData?.value ?? [];
    final memberLabels = ref.watch(tripMemberResolvedLabelsProvider(_trip.id));
    final myParticipantId = myUid != null
        ? participants
            .where((m) => m.userId?.trim() == myUid)
            .map((m) => m.id)
            .firstOrNull
        : null;
    final myAssignedRoomNames = myParticipantId == null
        ? const <String>[]
        : rooms
            .where((room) => room.assignedMemberIds.contains(myParticipantId))
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
    final canEditGeneralInfo = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.editGeneralInfoMinRole,
    );
    final canManageTripSettings = isTripRoleAllowed(
      currentRole: currentRole,
      minRole: _trip.generalPermissions.manageTripSettingsMinRole,
    );
    final canDeleteTrip = canEdit;
    final tripDocStream = FirebaseFirestore.instance
        .collection('trips')
        .doc(_trip.id)
        .snapshots();

    return Theme(
      data: NeonPalette.overlayOn(Theme.of(context)),
      child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: tripDocStream,
        builder: (context, snapshot) {
          final liveData = snapshot.data?.data();
          final liveLinkUrl = (liveData?['linkUrl'] as String?) ?? _trip.linkUrl;
          final livePreview =
              (liveData?['linkPreview'] as Map<String, dynamic>?) ?? const {};
          final liveMemberUserIds =
              ((liveData?['memberUserIds'] as List<dynamic>?) ??
                      _trip.memberUserIds)
                  .map((id) => id.toString())
                  .toList();
          final liveBannerImageUrl =
              (liveData?['bannerImageUrl'] as String?)?.trim() ??
                  (_trip.bannerImageUrl ?? '').trim();
          final linkUrlForUi = liveLinkUrl.trim();
          final photosStorageUrl =
              ((liveData?['photosStorageUrl'] as String?) ?? '').trim();
          final tripDateLabel = _trip.isDayTrip
              ? formatTripSingleDayDate(context, _trip.startDate)
              : formatTripDateRange(context, _trip.startDate, _trip.endDate);
          final isTripMember = myUid != null &&
              participants.any((m) => m.userId?.trim() == myUid);
          _scheduleInviteCodeLoadIfMember(isTripMember);
          final participantsCount = participants.length;
          final today = _dateOnly(DateTime.now());
          final participantUserIds = participants
              .where((m) => m.userId != null && m.userId!.trim().isNotEmpty)
              .map((m) => m.userId!.trim())
              .toList();
          final usersStream = _usersDataStreamFor(
            {...participantUserIds, ...liveMemberUserIds}.toList(),
          );
          final settingsRows = _settingsRows(
            l10n: l10n,
            isTripMember: isTripMember,
            canEditGeneralInfo: canEditGeneralInfo,
            canManageTripSettings: canManageTripSettings,
            canDeleteTrip: canDeleteTrip,
          );

          return StreamBuilder<Map<String, Map<String, dynamic>>>(
            stream: usersStream,
            builder: (context, userSnap) {
              final usersDataById = userSnap.data ?? const {};
              final participantsPreview = participants
                  .map(
                    (m) {
                      final displayLabel = resolveTripMemberDisplayLabel(
                        m,
                        profileData: usersDataById[m.userId],
                      );
                      final photoUrl = m.isChild
                          ? ''
                          : (m.userId != null
                              ? tripMemberStoredProfileBadgeUrl(
                                  usersDataById[m.userId!],
                                )
                              : '');
                      return TripOverviewParticipantPreviewEntry(
                        initial: avatarInitialFromDisplayLabel(displayLabel),
                        photoUrl: photoUrl,
                      );
                    },
                  )
                  .toList();
              final TripCarpool? myCarpool = myParticipantId == null
                  ? null
                  : carpools.cast<TripCarpool?>().firstWhere(
                        (entry) =>
                            entry?.assignedParticipantIds
                                .contains(myParticipantId) ==
                            true,
                        orElse: () => null,
                      );
              final myCarpoolDetailLines = <String>[
                if (myCarpool != null &&
                    myUid != null &&
                    myUid.trim().isNotEmpty)
                  ...() {
                    final departureTime =
                        MaterialLocalizations.of(context).formatTimeOfDay(
                      TimeOfDay.fromDateTime(myCarpool.departureAt),
                      alwaysUse24HourFormat: true,
                    );
                    final meetingPointLabel =
                        myCarpool.meetingPointAddress.trim();
                    final driverLabel = (memberLabels[
                                myCarpool.driverParticipantId] ??
                            l10n.tripParticipantsTraveler)
                        .trim();
                    final passengerIds = myCarpool.assignedParticipantIds
                        .map((id) => id.trim())
                        .where((id) => id.isNotEmpty)
                        .where((id) => id != myCarpool.driverParticipantId.trim())
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
                    final isDriver = myParticipantId != null &&
                        myParticipantId ==
                            myCarpool.driverParticipantId.trim();

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

              final bannerTitle = _trip.title.isEmpty
                  ? l10n.tripOverviewUntitled
                  : _trip.title;
              final bannerDestination = _trip.isDayTrip
                  ? null
                  : (_trip.destination.isEmpty
                      ? l10n.tripOverviewUnknownDestination
                      : _trip.destination);

              final isMapsLink = livePreview['isGoogleMaps'] == true;
              final hasAddress = _trip.address.trim().isNotEmpty;
              final showDirections =
                  !_trip.isDayTrip && (isMapsLink || hasAddress);

              return ColoredBox(
                color: NeonPalette.scaffoldBackground,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                      child: TripOverviewBanner(
                        title: bannerTitle,
                        destination: bannerDestination,
                        dateLabel:
                            tripDateLabel.isEmpty ? null : tripDateLabel,
                        imageUrl: liveBannerImageUrl,
                        busy: _isBannerBusy,
                        onPick: canManageBanner && liveBannerImageUrl.isEmpty
                            ? _pickAndUploadBannerImage
                            : null,
                        onPhotoMenu: canManageBanner
                            ? () => _showBannerPhotoMenu(liveBannerImageUrl)
                            : null,
                        emptyLabel: l10n.tripOverviewBannerEmpty,
                        addPhotoLabel: l10n.tripOverviewBannerAddPhoto,
                      ),
                    ),
                    if (linkUrlForUi.isNotEmpty) ...[
                      TripOverviewSectionHeader(
                        label: l10n.tripOverviewSectionAccommodation,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TripOverviewLinkCard(
                          url: linkUrlForUi,
                          preview: livePreview,
                          onOpen: () => _openLinkUrl(linkUrlForUi),
                          trailing: showDirections
                              ? IconButton(
                                  tooltip: l10n.tripOverviewOpenLocation,
                                  icon: const Icon(Icons.directions_outlined),
                                  color: NeonPalette.secondary,
                                  onPressed: () {
                                    final destination =
                                        _trip.address.trim().isNotEmpty
                                            ? _trip.address.trim()
                                            : ((livePreview['description']
                                                        as String?) ??
                                                    '')
                                                .trim();
                                    if (destination.isNotEmpty) {
                                      openRouteInMapAppsSelector(
                                        context,
                                        destinationAddress: destination,
                                      );
                                    } else if (isMapsLink) {
                                      _openLinkUrl(linkUrlForUi);
                                    }
                                  },
                                )
                              : null,
                        ),
                      ),
                    ],
                    TripOverviewSectionHeader(
                      label: l10n.tripOverviewSectionGroup,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TripOverviewParticipantsCard(
                        countLabel: '$participantsCount',
                        participantsLabel: l10n.tripOverviewTileParticipants,
                        participants: participantsPreview,
                        onCardTap: _openParticipantsPage,
                        onManageTap: _openParticipantsPage,
                        inviteCodeLabel: isTripMember
                            ? l10n.tripOverviewInviteCodeLabel
                            : null,
                        inviteCode: _inviteCode,
                        shareCodeLabel: isTripMember
                            ? l10n.tripOverviewShareCode
                            : null,
                        onShareCodeTap:
                            isTripMember ? _shareInviteCode : null,
                        shareCodeBusy: _inviteCodeBusy,
                      ),
                    ),
                    TripOverviewSectionHeader(
                      label: l10n.tripOverviewSectionModules,
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          TripOverviewModuleCard(
                            label: l10n.tripOverviewTileActivities,
                            icon: Icons.event_available_outlined,
                            count: plannedActivitiesCount,
                            tileColor: NeonPalette.overviewModulePlanningTile,
                            inkColor: NeonPalette.overviewModulePlanningInk,
                            statusText: _moduleStatusText(
                              detailLines: activitiesTodayLabels,
                              emptyStateMessage:
                                  l10n.tripOverviewTileNoActivitiesToday,
                            ),
                            onTap: () => context.go(
                              '/trips/${_trip.id}/activities?agendaDay=${_agendaDayParam(_resolvedAgendaDay(today))}',
                            ),
                          ),
                          if (_trip.roomsModuleEnabled && !_trip.isDayTrip) ...[
                            const SizedBox(height: 10),
                            TripOverviewModuleCard(
                              label: l10n.tripOverviewTileRooms,
                              icon: Icons.king_bed_outlined,
                              count: roomsCount,
                              tileColor: NeonPalette.overviewModuleRoomsTile,
                              inkColor: NeonPalette.overviewModuleRoomsInk,
                              statusText: _moduleStatusText(
                                detailLines: roomsDetailLines.length > 1
                                    ? [roomsDetailLines.last]
                                    : const [],
                                emptyStateMessage:
                                    l10n.tripOverviewTileNoAssignedRoom,
                              ),
                              onTap: () =>
                                  context.go('/trips/${_trip.id}/rooms'),
                            ),
                          ],
                          if (_trip.carpoolModuleEnabled) ...[
                            const SizedBox(height: 10),
                            TripOverviewModuleCard(
                              label: l10n.tripOverviewTileCarpool,
                              icon: Icons.directions_car_outlined,
                              count: carpools.length,
                              tileColor: NeonPalette.overviewModuleCarpoolTile,
                              inkColor: NeonPalette.overviewModuleCarpoolInk,
                              statusText: _moduleStatusText(
                                detailLines: myCarpoolDetailLines,
                                emptyStateMessage:
                                    l10n.tripCarpoolTileNoAssignment,
                              ),
                              onTap: () =>
                                  context.go('/trips/${_trip.id}/carpool'),
                            ),
                          ],
                          if (_trip.gamesModuleEnabled) ...[
                            const SizedBox(height: 10),
                            TripOverviewModuleCard(
                              label: l10n.tripOverviewTileGames,
                              icon: Icons.sports_esports_outlined,
                              count: boardGamesCount,
                              tileColor: NeonPalette.overviewModuleGamesTile,
                              inkColor: NeonPalette.overviewModuleGamesInk,
                              statusText: _moduleStatusText(
                                detailLines: boardGamesDetailLines,
                                emptyStateMessage:
                                    l10n.tripOverviewTileNoBoardGames,
                                moreDetailsLabelBuilder: (extraCount) =>
                                    l10n.tripOverviewTileGamesAndMore(
                                        extraCount),
                              ),
                              onTap: () =>
                                  context.push('/trips/${_trip.id}/games'),
                            ),
                          ],
                          if (photosStorageUrl.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            TripOverviewModuleCard(
                              label: l10n.tripOverviewPhotosAction,
                              icon: Icons.photo_library_outlined,
                              count: 0,
                              showCount: false,
                              tileColor: NeonPalette.overviewModulePhotosTile,
                              inkColor: NeonPalette.overviewModulePhotosInk,
                              statusText: l10n.tripOverviewPhotosOpenAlbum,
                              onTap: () => _openLinkUrl(photosStorageUrl),
                            ),
                          ],
                          if (canManageTripSettings) ...[
                            const SizedBox(height: 10),
                            TripOverviewModuleAddCard(
                              label: l10n.tripOverviewAddModule,
                              onTap: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      l10n.tripOverviewTileComingSoon,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (settingsRows.isNotEmpty) ...[
                      TripOverviewSectionHeader(
                        label: l10n.tripOverviewSectionSettings,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TripOverviewSettingsCard(rows: settingsRows),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
