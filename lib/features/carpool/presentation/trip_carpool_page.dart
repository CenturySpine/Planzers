import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/features/carpool/data/trip_carpools_repository.dart';
import 'package:planerz/features/carpool/presentation/trip_carpool_form_page.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trip_permissions.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

enum _TripCarpoolSelfAssignmentBusyKind { none, join, leave }

class TripCarpoolPage extends ConsumerStatefulWidget {
  const TripCarpoolPage({super.key});

  @override
  ConsumerState<TripCarpoolPage> createState() => _TripCarpoolPageState();
}

class _TripCarpoolPageState extends ConsumerState<TripCarpoolPage> {
  late final TextEditingController _globalMeetupController;
  late final FocusNode _globalMeetupFocusNode;
  bool _isSavingGlobalMeetup = false;
  bool _isEditingGlobalMeetup = false;
  _TripCarpoolSelfAssignmentBusyKind _selfAssignmentBusyKind =
      _TripCarpoolSelfAssignmentBusyKind.none;
  String? _selfAssignmentBusyCarpoolId;

  @override
  void initState() {
    super.initState();
    _globalMeetupController = TextEditingController();
    _globalMeetupFocusNode = FocusNode();
  }

  Future<void> _openCarpoolForm({TripCarpool? carpool}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TripCarpoolFormPage(
          initialCarpool: carpool,
          startReadOnly: carpool != null,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _globalMeetupController.dispose();
    _globalMeetupFocusNode.dispose();
    super.dispose();
  }

  Future<void> _saveGlobalMeetupLink({
    required String tripId,
    required bool canEditGlobalMeetup,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (!canEditGlobalMeetup || _isSavingGlobalMeetup) return;
    final cleanUrl = _globalMeetupController.text.trim();
    if (cleanUrl.isNotEmpty) {
      final parsed = Uri.tryParse(cleanUrl);
      if (parsed == null ||
          !parsed.isAbsolute ||
          (parsed.scheme != 'http' && parsed.scheme != 'https')) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.tripOverviewLinkInvalid)),
        );
        return;
      }
    }
    setState(() => _isSavingGlobalMeetup = true);
    try {
      await ref.read(tripCarpoolsRepositoryProvider).upsertTripCarpoolSection(
            tripId: tripId,
            shoppingMeetupLinkUrl: cleanUrl,
          );
      if (!mounted) return;
      setState(() => _isEditingGlobalMeetup = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonSave)),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.commonErrorWithDetails(error.toString()))),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingGlobalMeetup = false);
      }
    }
  }

  String _messageForSelfAssignmentError(Object error, AppLocalizations l10n) {
    if (error is FirebaseFunctionsException && error.code == 'permission-denied') {
      return l10n.tripCarpoolSelfAssignmentNotMember;
    }
    if (error is FirebaseException && error.code == 'permission-denied') {
      return l10n.tripCarpoolSelfAssignmentNotMember;
    }
    final details = error.toString();
    if (details.contains('Drivers cannot')) {
      return l10n.tripCarpoolSelfAssignmentDriverBlocked;
    }
    if (details.contains('Carpool is full')) {
      return l10n.tripCarpoolFull;
    }
    return l10n.commonErrorWithDetails(details);
  }

  Future<void> _joinTripCarpoolAsPassenger({
    required String tripId,
    required String carpoolId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_selfAssignmentBusyCarpoolId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _selfAssignmentBusyCarpoolId = carpoolId;
      _selfAssignmentBusyKind = _TripCarpoolSelfAssignmentBusyKind.join;
    });
    try {
      await ref.read(tripCarpoolsRepositoryProvider).joinTripCarpoolAsSelfAssignedPassenger(
            tripId: tripId,
            targetCarpoolId: carpoolId,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tripCarpoolJoinedSelfSnack)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_messageForSelfAssignmentError(error, l10n))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _selfAssignmentBusyCarpoolId = null;
          _selfAssignmentBusyKind = _TripCarpoolSelfAssignmentBusyKind.none;
        });
      }
    }
  }

  Future<void> _leaveTripCarpoolAsPassenger({
    required String tripId,
    required String carpoolId,
  }) async {
    final l10n = AppLocalizations.of(context)!;
    if (_selfAssignmentBusyCarpoolId != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _selfAssignmentBusyCarpoolId = carpoolId;
      _selfAssignmentBusyKind = _TripCarpoolSelfAssignmentBusyKind.leave;
    });
    try {
      await ref.read(tripCarpoolsRepositoryProvider).leaveTripCarpoolAsSelfAssignedPassenger(
            tripId: tripId,
            carpoolId: carpoolId,
          );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.tripCarpoolLeftSelfSnack)),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(_messageForSelfAssignmentError(error, l10n))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _selfAssignmentBusyCarpoolId = null;
          _selfAssignmentBusyKind = _TripCarpoolSelfAssignmentBusyKind.none;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final trip = TripScope.of(context);
    final carpoolsAsync = ref.watch(tripCarpoolsStreamProvider(trip.id));
    final carpoolSectionAsync = ref.watch(tripCarpoolSectionStreamProvider(trip.id));
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final canPropose = canProposeCarpoolForTrip(trip: trip, userId: myUid);
    final canEditGlobalMeetup = canUpdateCarpoolShoppingMeetupPointForTrip(
      trip: trip,
      userId: myUid,
    );
    final currentTripRole = resolveTripPermissionRole(trip: trip, userId: myUid);
    final showUnassignedMembersWarning = isTripRoleAllowed(
      currentRole: currentTripRole,
      minRole: TripPermissionRole.admin,
    );
    return Scaffold(
      body: carpoolSectionAsync.when(
        data: (carpoolSection) {
          if (!_globalMeetupFocusNode.hasFocus &&
              !_isEditingGlobalMeetup &&
              _globalMeetupController.text.trim() !=
                  carpoolSection.shoppingMeetupLinkUrl.trim()) {
            _globalMeetupController.text = carpoolSection.shoppingMeetupLinkUrl;
          }
          return carpoolsAsync.when(
            data: (carpools) {
          final carpoolsForList = [...carpools];
          if (myUid != null && carpoolsForList.length > 1) {
            carpoolsForList.sort((a, b) {
              final aMine = a.assignedParticipantIds.contains(myUid);
              final bMine = b.assignedParticipantIds.contains(myUid);
              if (aMine == bMine) return 0;
              return aMine ? -1 : 1;
            });
          }
          final assignedIds = <String>{
            for (final carpool in carpools) ...carpool.assignedParticipantIds,
          };
          final unassignedMembers = trip.memberIds
              .where((memberId) => memberId.trim().isNotEmpty)
              .where((memberId) => !assignedIds.contains(memberId))
              .length;
          final myUidTrimmed = myUid?.trim() ?? '';
          final showSelfUnassignedCard = myUidTrimmed.isNotEmpty &&
              trip.memberIds.any((id) => id.trim() == myUidTrimmed) &&
              !carpools.any(
                (carpool) => carpool.assignedParticipantIds.any(
                  (id) => id.trim() == myUidTrimmed,
                ),
              );
          final showGlobalShoppingMeetupSection = myUidTrimmed.isNotEmpty &&
              carpools.any(
                (carpool) =>
                    carpool.goesShopping &&
                    carpool.assignedParticipantIds.any(
                      (id) => id.trim() == myUidTrimmed,
                    ),
              );

          final labelUserIds = <String>{
            for (final id in trip.memberIds)
              if (id.trim().isNotEmpty) id.trim(),
            for (final carpool in carpools)
              if (carpool.driverUserId.trim().isNotEmpty) carpool.driverUserId.trim(),
          }.toList(growable: false);
          final usersIdsKey = stableUsersIdsKey(labelUserIds);
          final usersAsync = ref.watch(
            usersDataByIdsKeyStreamProvider(usersIdsKey),
          );

          return usersAsync.when(
            data: (userDocs) {
              final memberLabels = tripMemberLabelsFromUserDocsById(
                userDocs,
                labelUserIds,
                tripMemberPublicLabels: trip.memberPublicLabels,
                currentUserId: myUid,
                emptyFallback: l10n.tripParticipantsTraveler,
              );
              final viewerIsDriverOnTrip = myUidTrimmed.isNotEmpty &&
                  carpools.any(
                    (c) => c.driverUserId.trim() == myUidTrimmed,
                  );
              final canUsePassengerSelfAssignment =
                  myUidTrimmed.isNotEmpty &&
                      trip.memberIds.any((id) => id.trim() == myUidTrimmed);
              final passengerSelfAssignmentInteractionLocked =
                  _selfAssignmentBusyCarpoolId != null;
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  Text(
                    l10n.tripCarpoolListTitle,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 16),
                  if (showUnassignedMembersWarning && unassignedMembers > 0) ...[
                    Card(
                      color: Theme.of(context).colorScheme.errorContainer,
                      child: ListTile(
                        leading: Icon(
                          Icons.warning_amber_rounded,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        title: Text(l10n.tripCarpoolUnassignedWarningTitle),
                        subtitle: Text(
                          l10n.tripCarpoolUnassignedWarningBody(unassignedMembers),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showSelfUnassignedCard) ...[
                    Card(
                      color: context.planerzColors.warningContainer,
                      child: ListTile(
                        leading: Icon(
                          Icons.directions_car_outlined,
                          color: context.planerzColors.warning,
                        ),
                        title: Text(l10n.tripCarpoolSelfUnassignedTitle),
                        subtitle: Text(l10n.tripCarpoolSelfUnassignedBody),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (showGlobalShoppingMeetupSection) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.tripCarpoolGlobalMeetupTitle,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 10),
                            if (canEditGlobalMeetup &&
                                (_isEditingGlobalMeetup ||
                                    carpoolSection.shoppingMeetupLinkUrl
                                        .trim()
                                        .isEmpty))
                              TextFormField(
                                controller: _globalMeetupController,
                                focusNode: _globalMeetupFocusNode,
                                decoration: InputDecoration(
                                  labelText: l10n.tripCarpoolGlobalMeetupLabel,
                                  border: const OutlineInputBorder(),
                                  suffixIcon: canEditGlobalMeetup
                                      ? IconButton(
                                          tooltip: l10n.commonSave,
                                          onPressed: _isSavingGlobalMeetup
                                              ? null
                                              : () => _saveGlobalMeetupLink(
                                                    tripId: trip.id,
                                                    canEditGlobalMeetup:
                                                        canEditGlobalMeetup,
                                                  ),
                                          icon: _isSavingGlobalMeetup
                                              ? const SizedBox(
                                                  width: 18,
                                                  height: 18,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                )
                                              : const Icon(Icons.check),
                                        )
                                      : null,
                                ),
                              ),
                            if (!canEditGlobalMeetup &&
                                carpoolSection.shoppingMeetupLinkUrl
                                    .trim()
                                    .isEmpty)
                              Text(
                                l10n.commonNotProvided,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            const SizedBox(height: 10),
                            if (carpoolSection.shoppingMeetupLinkUrl
                                .trim()
                                .isNotEmpty) ...[
                              LinkPreviewCardFromFirestore(
                                url: carpoolSection.shoppingMeetupLinkUrl,
                                preview:
                                    carpoolSection.shoppingMeetupLinkPreview,
                                showCard: true,
                                showTitleLabel: false,
                              ),
                              if (canEditGlobalMeetup) ...[
                                const SizedBox(height: 8),
                                Align(
                                  alignment: AlignmentDirectional.centerEnd,
                                  child: IconButton(
                                    tooltip: l10n.commonEdit,
                                    onPressed: () {
                                      setState(() {
                                        _isEditingGlobalMeetup = true;
                                        _globalMeetupController.text =
                                            carpoolSection
                                                .shoppingMeetupLinkUrl;
                                      });
                                    },
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (carpools.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.tripCarpoolEmptyState),
                      ),
                    ),
                  for (final carpool in carpoolsForList)
                    Builder(
                      builder: (context) {
                        final isUidInThisCarpool =
                            carpool.assignedParticipantIds.any(
                          (id) => id.trim() == myUidTrimmed,
                        );
                        final remainingPassengerSeats =
                            carpool.availableSeats -
                                carpool.assignedParticipantIds.length;
                        final showJoinPassengerAction =
                            canUsePassengerSelfAssignment &&
                                !viewerIsDriverOnTrip &&
                                !isUidInThisCarpool &&
                                remainingPassengerSeats > 0;
                        final showLeavePassengerAction =
                            canUsePassengerSelfAssignment &&
                                !viewerIsDriverOnTrip &&
                                isUidInThisCarpool &&
                                carpool.driverUserId.trim() !=
                                    myUidTrimmed;
                        final joinPassengerSpinner =
                            _selfAssignmentBusyKind ==
                                    _TripCarpoolSelfAssignmentBusyKind.join &&
                                _selfAssignmentBusyCarpoolId == carpool.id;
                        final leavePassengerSpinner =
                            _selfAssignmentBusyKind ==
                                    _TripCarpoolSelfAssignmentBusyKind.leave &&
                                _selfAssignmentBusyCarpoolId == carpool.id;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _TripCarpoolCard(
                              carpool: carpool,
                              isCurrentUserInCarpool: myUidTrimmed.isNotEmpty &&
                                  isUidInThisCarpool,
                              driverLabel:
                                  memberLabels[carpool.driverUserId] ??
                                      l10n.tripParticipantsTraveler,
                              driverUserData:
                                  userDocs[carpool.driverUserId],
                              passengerLabels: carpool
                                  .assignedParticipantIds
                                  .where((id) => id != carpool.driverUserId)
                                  .map(
                                    (id) =>
                                        memberLabels[id] ??
                                        l10n.tripParticipantsTraveler,
                                  )
                                  .toList(growable: false),
                              showJoinPassengerAction:
                                  showJoinPassengerAction,
                              showLeavePassengerAction:
                                  showLeavePassengerAction,
                              joinPassengerActionSpinner:
                                  joinPassengerSpinner,
                              leavePassengerActionSpinner:
                                  leavePassengerSpinner,
                              onJoinPassengerPressed:
                                  showJoinPassengerAction &&
                                          !passengerSelfAssignmentInteractionLocked
                                      ? () {
                                          _joinTripCarpoolAsPassenger(
                                            tripId: trip.id,
                                            carpoolId: carpool.id,
                                          );
                                        }
                                      : null,
                              onLeavePassengerPressed:
                                  showLeavePassengerAction &&
                                          !passengerSelfAssignmentInteractionLocked
                                      ? () {
                                          _leaveTripCarpoolAsPassenger(
                                            tripId: trip.id,
                                            carpoolId: carpool.id,
                                          );
                                        }
                                      : null,
                              onTap: () =>
                                  _openCarpoolForm(carpool: carpool),
                            ),
                            const SizedBox(height: 10),
                          ],
                        );
                      },
                    ),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.commonErrorWithDetails(error.toString())),
              ),
            ),
          );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(l10n.commonErrorWithDetails(error.toString())),
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(l10n.commonErrorWithDetails(error.toString())),
          ),
        ),
      ),
      floatingActionButton: canPropose
          ? FloatingActionButton(
              onPressed: () {
                _openCarpoolForm();
              },
              tooltip: l10n.tripCarpoolCreateAction,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _TripCarpoolCard extends StatelessWidget {
  const _TripCarpoolCard({
    required this.carpool,
    required this.isCurrentUserInCarpool,
    required this.driverLabel,
    required this.driverUserData,
    required this.passengerLabels,
    required this.showJoinPassengerAction,
    required this.showLeavePassengerAction,
    required this.joinPassengerActionSpinner,
    required this.leavePassengerActionSpinner,
    required this.onJoinPassengerPressed,
    required this.onLeavePassengerPressed,
    required this.onTap,
  });

  final TripCarpool carpool;
  final bool isCurrentUserInCarpool;
  final String driverLabel;
  final Map<String, dynamic>? driverUserData;
  final List<String> passengerLabels;
  final bool showJoinPassengerAction;
  final bool showLeavePassengerAction;
  final bool joinPassengerActionSpinner;
  final bool leavePassengerActionSpinner;
  final VoidCallback? onJoinPassengerPressed;
  final VoidCallback? onLeavePassengerPressed;
  final VoidCallback onTap;

  static const String _stepInAsset = 'assets/images/carpool_step_in.svg';
  static const String _stepOutAsset = 'assets/images/carpool_step_out.svg';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final planerzPalette = context.planerzColors;
    final departureTime = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(carpool.departureAt),
      alwaysUse24HourFormat: true,
    );
    final remainingSeats = carpool.availableSeats - carpool.assignedParticipantIds.length;
    final meetingPointLabel = carpool.meetingPointAddress.trim().isEmpty
        ? l10n.commonNotProvided
        : carpool.meetingPointAddress.trim();
    final participantsLabel = passengerLabels.join(', ');
    final seatsStatusLabel = remainingSeats > 0
        ? l10n.tripCarpoolRemainingSeats(remainingSeats)
        : l10n.tripCarpoolFull;
    final meetingLineStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        );
    final hasMeetingPointAddress = carpool.meetingPointAddress.trim().isNotEmpty;

    return Card(
      clipBehavior:
          isCurrentUserInCarpool ? Clip.antiAlias : Clip.none,
      color: isCurrentUserInCarpool ? planerzPalette.successContainer : null,
      shape: isCurrentUserInCarpool
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: planerzPalette.success, width: 2),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  buildProfileBadge(
                    context: context,
                    displayLabel: driverLabel,
                    userData: driverUserData,
                    size: 28,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Flexible(
                          child: Text(
                            driverLabel,
                            style: Theme.of(context).textTheme.titleSmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (carpool.goesShopping) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.shopping_cart_outlined,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showJoinPassengerAction) ...[
                    _CarpoolSelfAssignmentSvgButton(
                      assetPath: _stepInAsset,
                      tooltip: l10n.tripCarpoolJoinTooltip,
                      iconColor: colorScheme.primary,
                      onPressed: onJoinPassengerPressed,
                      showSpinner: joinPassengerActionSpinner,
                    ),
                    const SizedBox(width: 2),
                  ],
                  if (showLeavePassengerAction) ...[
                    _CarpoolSelfAssignmentSvgButton(
                      assetPath: _stepOutAsset,
                      tooltip: l10n.tripCarpoolLeaveTooltip,
                      iconColor: colorScheme.error,
                      onPressed: onLeavePassengerPressed,
                      showSpinner: leavePassengerActionSpinner,
                    ),
                    const SizedBox(width: 4),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              Text.rich(
                TextSpan(
                  children: [
                    if (participantsLabel.isNotEmpty) TextSpan(text: participantsLabel),
                    TextSpan(text: participantsLabel.isNotEmpty ? ' (' : '('),
                    TextSpan(
                      text: seatsStatusLabel,
                      style: TextStyle(
                        color: remainingSeats > 0
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.error,
                      ),
                    ),
                    const TextSpan(text: ')'),
                  ],
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  style: meetingLineStyle,
                  children: [
                    TextSpan(text: '$departureTime - '),
                    TextSpan(text: meetingPointLabel),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 6),
                        child: Tooltip(
                          message: l10n.tripCarpoolNavigateToMeetingPoint,
                          child: hasMeetingPointAddress
                              ? Material(
                                  color: Colors.transparent,
                                  type: MaterialType.transparency,
                                  child: InkWell(
                                    onTap: () => openAddressInGoogleMaps(
                                      context,
                                      carpool.meetingPointAddress,
                                    ),
                                    customBorder: const CircleBorder(),
                                    overlayColor:
                                        WidgetStateProperty.resolveWith(
                                      (states) {
                                        final base =
                                            colorScheme.onSurfaceVariant;
                                        if (states
                                            .contains(WidgetState.pressed)) {
                                          return base.withValues(alpha: 0.18);
                                        }
                                        if (states
                                            .contains(WidgetState.hovered)) {
                                          return base.withValues(alpha: 0.10);
                                        }
                                        if (states
                                            .contains(WidgetState.focused)) {
                                          return base.withValues(alpha: 0.10);
                                        }
                                        return null;
                                      },
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.navigation_outlined,
                                        size: 18,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                )
                              : Icon(
                                  Icons.navigation_outlined,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.38),
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                carpool.nearestTransitStop.trim().isEmpty
                    ? l10n.commonNotProvided
                    : carpool.nearestTransitStop.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CarpoolSelfAssignmentSvgButton extends StatelessWidget {
  const _CarpoolSelfAssignmentSvgButton({
    required this.assetPath,
    required this.tooltip,
    required this.iconColor,
    required this.onPressed,
    required this.showSpinner,
  });

  final String assetPath;
  final String tooltip;
  final Color iconColor;
  final VoidCallback? onPressed;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !showSpinner;
    final effectiveColor =
        enabled ? iconColor : iconColor.withValues(alpha: 0.38);
    final backgroundColor = enabled
        ? iconColor.withValues(alpha: 0.14)
        : iconColor.withValues(alpha: 0.08);
    final borderColor = enabled
        ? iconColor.withValues(alpha: 0.42)
        : iconColor.withValues(alpha: 0.18);
    final roundedRectangleShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
      side: BorderSide(color: borderColor),
    );

    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        elevation: enabled ? 1 : 0,
        shadowColor: iconColor.withValues(alpha: 0.22),
        shape: roundedRectangleShape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          customBorder: roundedRectangleShape,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            final base = iconColor;
            if (states.contains(WidgetState.pressed)) {
              return base.withValues(alpha: 0.24);
            }
            if (states.contains(WidgetState.hovered)) {
              return base.withValues(alpha: 0.16);
            }
            if (states.contains(WidgetState.focused)) {
              return base.withValues(alpha: 0.16);
            }
            return null;
          }),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: showSpinner
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: effectiveColor,
                    ),
                  )
                : SvgPicture.asset(
                    assetPath,
                    width: 22,
                    height: 22,
                    colorFilter: ColorFilter.mode(
                      effectiveColor,
                      BlendMode.srcIn,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
