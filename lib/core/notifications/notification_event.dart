import 'package:planzers/core/notifications/notification_channel.dart';

class TripNotificationEvent {
  const TripNotificationEvent({
    required this.channel,
    required this.tripId,
    required this.actorId,
    required this.type,
    required this.title,
    required this.body,
    required this.targetPath,
    required this.createdAt,
    this.payload = const <String, String>{},
  });

  final TripNotificationChannel channel;
  final String tripId;
  final String actorId;
  final String type;
  final String title;
  final String body;
  final String targetPath;
  final DateTime createdAt;
  final Map<String, String> payload;
}
