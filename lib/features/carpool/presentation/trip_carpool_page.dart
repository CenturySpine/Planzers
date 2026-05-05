import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/presentation/profile_badge.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/carpool/data/trip_carpool.dart';
import 'package:planerz/features/carpool/data/trip_carpools_repository.dart';
import 'package:planerz/features/carpool/presentation/trip_carpool_form_page.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/presentation/link_preview_from_firestore.dart';
import 'package:planerz/features/trips/presentation/open_address_in_google_maps.dart';
import 'package:planerz/app/theme/planerz_colors.dart';
import 'package:planerz/features/trips/presentation/trip_scope.dart';
import 'package:planerz/l10n/app_localizations.dart';

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
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
                children: [
                  if (unassignedMembers > 0) ...[
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
                                  carpoolSection.shoppingMeetupLinkUrl.trim().isEmpty))
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
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                ),
                                              )
                                            : const Icon(Icons.check),
                                      )
                                    : null,
                              ),
                            ),
                          if (!canEditGlobalMeetup &&
                              carpoolSection.shoppingMeetupLinkUrl.trim().isEmpty)
                            Text(
                              l10n.commonNotProvided,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          const SizedBox(height: 10),
                          if (carpoolSection.shoppingMeetupLinkUrl.trim().isNotEmpty) ...[
                            LinkPreviewCardFromFirestore(
                              url: carpoolSection.shoppingMeetupLinkUrl,
                              preview: carpoolSection.shoppingMeetupLinkPreview,
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
                                          carpoolSection.shoppingMeetupLinkUrl;
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
                  if (carpools.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(l10n.tripCarpoolEmptyState),
                      ),
                    ),
                  for (final carpool in carpoolsForList) ...[
                    _TripCarpoolCard(
                      carpool: carpool,
                      isCurrentUserInCarpool: myUid != null &&
                          carpool.assignedParticipantIds.contains(myUid),
                      driverLabel: memberLabels[carpool.driverUserId] ??
                          l10n.tripParticipantsTraveler,
                      driverUserData: userDocs[carpool.driverUserId],
                      passengerLabels: carpool.assignedParticipantIds
                          .where((id) => id != carpool.driverUserId)
                          .map(
                            (id) =>
                                memberLabels[id] ?? l10n.tripParticipantsTraveler,
                          )
                          .toList(growable: false),
                      onTap: () => _openCarpoolForm(carpool: carpool),
                    ),
                    const SizedBox(height: 10),
                  ],
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
    required this.onTap,
  });

  final TripCarpool carpool;
  final bool isCurrentUserInCarpool;
  final String driverLabel;
  final Map<String, dynamic>? driverUserData;
  final List<String> passengerLabels;
  final VoidCallback onTap;

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
                    child: Text(
                      driverLabel,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (carpool.goesShopping)
                    Icon(
                      Icons.shopping_cart_outlined,
                      color: colorScheme.primary,
                    ),
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: l10n.tripCarpoolNavigateToMeetingPoint,
                    onPressed: carpool.meetingPointAddress.trim().isEmpty
                        ? null
                        : () => openAddressInGoogleMaps(
                              context,
                              carpool.meetingPointAddress,
                            ),
                    icon: const Icon(Icons.navigation_outlined),
                  ),
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
              Text(
                '$departureTime - $meetingPointLabel',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
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
