class InviteJoinParticipantOption {
  const InviteJoinParticipantOption({
    required this.id,
    required this.displayName,
  });

  /// TripMember document ID.
  final String id;
  final String displayName;
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
  });

  final String tripId;
  final String tripTitle;
  final List<InviteJoinParticipantOption> participants;
  final bool requiresParticipantChoice;
  final bool cupidonModeEnabled;

  /// From Cloud Function [getInviteJoinContext] (ISO), for stay bounds UI.
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
}
