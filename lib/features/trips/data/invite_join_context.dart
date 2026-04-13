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
  });

  final String tripId;
  final String tripTitle;
  final List<InviteJoinPlaceholderOption> placeholders;
  final bool requiresPlaceholderChoice;
}
