class AppUsageStats {
  const AppUsageStats({
    required this.tripsTotal,
    required this.tripsPast,
    required this.tripsOngoing,
    required this.tripsUpcoming,
    required this.tripsUncategorized,
    required this.tripsMaxParticipants,
    required this.tripsMaxDurationDays,
    required this.usersTotal,
    this.usersLatestSignIn,
  });

  final int tripsTotal;
  final int tripsPast;
  final int tripsOngoing;
  final int tripsUpcoming;
  final int tripsUncategorized;
  final int tripsMaxParticipants;
  final int tripsMaxDurationDays;
  final int usersTotal;
  final DateTime? usersLatestSignIn;

  factory AppUsageStats.fromMap(Map<String, dynamic> map) {
    final trips = map['trips'] as Map<String, dynamic>? ?? {};
    final users = map['users'] as Map<String, dynamic>? ?? {};
    final latestSignInMs = users['latestSignInMs'] as num?;
    return AppUsageStats(
      tripsTotal: (trips['total'] as num?)?.toInt() ?? 0,
      tripsPast: (trips['past'] as num?)?.toInt() ?? 0,
      tripsOngoing: (trips['ongoing'] as num?)?.toInt() ?? 0,
      tripsUpcoming: (trips['upcoming'] as num?)?.toInt() ?? 0,
      tripsUncategorized: (trips['uncategorized'] as num?)?.toInt() ?? 0,
      tripsMaxParticipants: (trips['maxParticipants'] as num?)?.toInt() ?? 0,
      tripsMaxDurationDays: (trips['maxDurationDays'] as num?)?.toInt() ?? 0,
      usersTotal: (users['total'] as num?)?.toInt() ?? 0,
      usersLatestSignIn: latestSignInMs != null
          ? DateTime.fromMillisecondsSinceEpoch(latestSignInMs.toInt())
          : null,
    );
  }
}
