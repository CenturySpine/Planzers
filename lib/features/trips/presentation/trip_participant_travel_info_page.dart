import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:planerz/features/administration/data/maintenance_repository.dart';
import 'package:planerz/features/auth/data/user_display_label.dart';
import 'package:planerz/features/auth/data/users_repository.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';
import 'package:planerz/features/trips/data/trip_members_repository.dart';
import 'package:planerz/features/trips/data/trip_permission_helpers.dart';
import 'package:planerz/features/trips/data/trips_repository.dart';
import 'package:planerz/features/trips/presentation/trip_participant_name_editor.dart';
import 'package:planerz/features/trips/presentation/trip_participant_stay_dates_editor.dart';
import 'package:planerz/features/trips/presentation/trip_member_stay_options_editor.dart';
import 'package:planerz/l10n/app_localizations.dart';

class TripParticipantTravelInfoPage extends ConsumerWidget {
  const TripParticipantTravelInfoPage({
    super.key,
    required this.tripId,
    required this.participantId,
  });

  final String tripId;
  final String participantId;

  static String _messageForError(BuildContext context, Object error) {
    final l10n = AppLocalizations.of(context)!;
    if (error is FirebaseFunctionsException) {
      final message = error.message;
      if (message != null && message.trim().isNotEmpty) {
        return message.trim();
      }
    }
    return l10n.commonErrorWithDetails(error.toString());
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final tripAsync = ref.watch(tripStreamProvider(tripId));
    final participant = ref.watch(
      tripParticipantByIdProvider(
        (tripId: tripId, participantId: participantId),
      ),
    );
    final participantsAsync = ref.watch(tripParticipantsStreamProvider(tripId));

    return tripAsync.when(
      data: (trip) {
        if (trip == null) {
          return _scaffoldWithMessage(
            context: context,
            title: l10n.tripParticipantTravelInfoTitle,
            message: l10n.tripNotFoundOrNoAccess,
          );
        }

        final myUid = FirebaseAuth.instance.currentUser?.uid;
        final isApplicationOwner =
            ref.watch(isApplicationOwnerProvider).asData?.value ?? false;
        final canManageParticipants = canManageTripParticipantsForUser(
          trip: trip,
          userId: myUid,
          isApplicationOwner: isApplicationOwner,
        );
        if (!canManageParticipants) {
          return _scaffoldWithMessage(
            context: context,
            title: l10n.tripParticipantTravelInfoTitle,
            message: l10n.tripNotFoundOrNoAccess,
          );
        }

        if (participantsAsync.isLoading && participant == null) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.tripParticipantTravelInfoTitle)),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (participant == null) {
          return _scaffoldWithMessage(
            context: context,
            title: l10n.tripParticipantTravelInfoTitle,
            message: l10n.tripParticipantNotFound,
            onBack: () => context.pop(),
          );
        }

        final userId = participant.userId;
        final usersDataById = userId != null
            ? ref
                .watch(
                  usersDataByIdsKeyStreamProvider(
                    stableUsersIdsKey([userId]),
                  ),
                )
                .asData
                ?.value
            : null;
        Map<String, dynamic>? profileData;
        if (participant.isClaimed && userId != null && usersDataById != null) {
          profileData = usersDataById[userId];
        }
        final profileName = profileNameFromData(profileData);
        final displayLabel = resolveTripMemberDisplayLabel(
          participant,
          profileData: profileData,
        );
        final currentStay =
            participant.stay ?? TripMemberStay.defaultForTrip(trip);

        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.tripParticipantTravelInfoTitle),
                if (displayLabel.trim().isNotEmpty)
                  Text(
                    l10n.tripParticipantTravelInfoSubtitle(displayLabel),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TripParticipantNameEditor(
                initialName: participant.participantName,
                initialUseProfileName: participant.useProfileName,
                initialIsChild: participant.isChild,
                isClaimed: participant.isClaimed,
                profileName: profileName,
                onSave: (result) async {
                  final name = result.name;
                  if (name.isEmpty && !result.useProfileName) return;
                  try {
                    await ref.read(tripsRepositoryProvider).updateTripParticipantName(
                          tripId: tripId,
                          participantId: participantId,
                          participantName: name,
                          useProfileName: result.useProfileName,
                          isChild: result.isChild,
                        );
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.tripParticipantsNameUpdated),
                      ),
                    );
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_messageForError(context, error)),
                      ),
                    );
                    rethrow;
                  }
                },
              ),
              if (!trip.isDayTrip) ...[
                const SizedBox(height: 12),
                TripParticipantStayDatesEditor(
                  mode: TripMemberStayOptionsEditorMode.live,
                  tripStartDate: trip.startDate,
                  tripEndDate: trip.endDate,
                  initialStay: currentStay,
                  trip: trip,
                  onLiveChanged: (stay) async {
                    try {
                      await ref
                          .read(tripMembersRepositoryProvider)
                          .updateParticipantProfile(
                            tripId: tripId,
                            participantId: participantId,
                            stay: stay,
                          );
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.tripStayUpdated)),
                      );
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(_messageForError(context, error)),
                        ),
                      );
                      rethrow;
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
      loading: () => Scaffold(
        appBar: AppBar(title: Text(l10n.tripParticipantTravelInfoTitle)),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _scaffoldWithMessage(
        context: context,
        title: l10n.tripParticipantTravelInfoTitle,
        message: l10n.commonErrorWithDetails(error.toString()),
      ),
    );
  }

  Widget _scaffoldWithMessage({
    required BuildContext context,
    required String title,
    required String message,
    VoidCallback? onBack,
  }) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: IconButton(
          onPressed: onBack ?? () => context.pop(),
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
