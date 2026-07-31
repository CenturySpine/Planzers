Set<String> initialExpenseEditParticipantIds({
  required Iterable<String> storedParticipantIds,
  required Iterable<String> fallbackScopeIds,
}) {
  final stored = storedParticipantIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
  if (stored.isNotEmpty) return stored;
  return fallbackScopeIds
      .map((id) => id.trim())
      .where((id) => id.isNotEmpty)
      .toSet();
}

String? initialExpenseEditPaidBy({
  required String storedPaidBy,
  required Iterable<String> fallbackScopeIds,
}) {
  final paidBy = storedPaidBy.trim();
  if (paidBy.isNotEmpty) return paidBy;
  for (final id in fallbackScopeIds) {
    final cleanId = id.trim();
    if (cleanId.isNotEmpty) return cleanId;
  }
  return null;
}

List<String> editableExpenseMemberIds({
  required Iterable<String> scopeIds,
  required Iterable<String> participantIds,
  required String? paidBy,
}) {
  final ids = <String>[];
  final seen = <String>{};
  void add(String id) {
    final cleanId = id.trim();
    if (cleanId.isEmpty || !seen.add(cleanId)) return;
    ids.add(cleanId);
  }

  for (final id in scopeIds) {
    add(id);
  }
  for (final id in participantIds) {
    add(id);
  }
  if (paidBy != null) add(paidBy);
  return ids;
}
