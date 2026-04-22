enum TripNotificationChannel {
  messages,
  activities,
  cupidon;

  String get firestoreKey => switch (this) {
        messages => 'messages',
        activities => 'activities',
        cupidon => 'cupidon',
      };

  String get androidChannelId => switch (this) {
        messages => 'planerz_messages',
        activities => 'planerz_activities',
        cupidon => 'planerz_cupidon',
      };

  String get androidChannelName => switch (this) {
        messages => 'Messages de voyage',
        activities => 'Activités de voyage',
        cupidon => 'Mode Cupidon',
      };

  String get targetPathSuffix => switch (this) {
        messages => 'messages',
        activities => 'activities',
        cupidon => 'cupidon',
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
