class InviteJoinPlaceholderOption {
  const InviteJoinPlaceholderOption({
    required this.id,
    required this.displayName,
  });

  final String id;
  final String displayName;
}

class InviteJoinContext {
  const InviteJoinContext({
    required this.tripId,
    required this.tripTitle,
    required this.placeholders,
    required this.requiresPlaceholderChoice,
    this.tripStartDate,
    this.tripEndDate,
  });

  final String tripId;
  final String tripTitle;
  final List<InviteJoinPlaceholderOption> placeholders;
  final bool requiresPlaceholderChoice;

  /// From Cloud Function [getInviteJoinContext] (ISO), for stay bounds UI.
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;
}
