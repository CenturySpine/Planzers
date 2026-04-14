enum TripNotificationChannel {
  messages,
  activities;

  String get firestoreKey => switch (this) {
        TripNotificationChannel.messages => 'messages',
        TripNotificationChannel.activities => 'activities',
      };

  String get targetPathSuffix => switch (this) {
        TripNotificationChannel.messages => 'messages',
        TripNotificationChannel.activities => 'activities',
      };

  static TripNotificationChannel? fromFirestoreKey(String raw) {
    final clean = raw.trim();
    for (final channel in TripNotificationChannel.values) {
      if (channel.firestoreKey == clean) {
        return channel;
      }
    }
    return null;
  }
}
