import 'package:planerz/features/trips/data/trip_member_stay.dart';

class InviteJoinParticipantOption {
  const InviteJoinParticipantOption({
    required this.id,
    required this.displayName,
    this.stay,
  });

  /// TripMember document ID.
  final String id;
  final String displayName;

  /// Stay bounds stored on the participant document, when available.
  final TripMemberStay? stay;
}

class InviteJoinContext {
  const InviteJoinContext({
    required this.tripId,
    required this.tripTitle,
    required this.participants,
    required this.requiresParticipantChoice,
    required this.cupidonModeEnabled,
    this.tripStartDate,
    this.tripEndDate,
    this.isDayTrip = false,
  });

  final String tripId;
  final String tripTitle;
  final List<InviteJoinParticipantOption> participants;
  final bool requiresParticipantChoice;
  final bool cupidonModeEnabled;

  /// From Cloud Function [getInviteJoinContext] (ISO), for stay bounds UI.
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;

  /// When true, stay-date UI is hidden on the invite join flow.
  final bool isDayTrip;
}
