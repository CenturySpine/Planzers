import 'package:planerz/features/trips/data/trip.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
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
    this.alreadyMember = false,
    this.tripStartDate,
    this.tripEndDate,
    this.tripStartDayPart,
    this.tripEndDayPart,
    this.isDayTrip = false,
  });

  final String tripId;
  final String tripTitle;
  final List<InviteJoinParticipantOption> participants;
  final bool requiresParticipantChoice;
  final bool cupidonModeEnabled;
  final bool alreadyMember;

  /// From Cloud Function [getInviteJoinContext] (ISO), for stay bounds UI.
  final DateTime? tripStartDate;
  final DateTime? tripEndDate;

  /// Organizer meal bounds on the trip calendar (Firestore: `tripStartDayPart` / `tripEndDayPart`).
  final TripDayPart? tripStartDayPart;
  final TripDayPart? tripEndDayPart;

  /// When true, stay-date UI is hidden on the invite join flow.
  final bool isDayTrip;

  /// Stay draft for the join flow: participant slot when set, else trip calendar.
  TripMemberStay stayDraftForJoin({String? selectedParticipantId}) {
    if (!isDayTrip && selectedParticipantId != null) {
      for (final option in participants) {
        if (option.id == selectedParticipantId && option.stay != null) {
          return option.stay!;
        }
      }
    }
    return defaultMemberStayFromTripCalendar();
  }

  /// Stay bounds seeded from the trip document calendar (same rules as trip edit).
  TripMemberStay defaultMemberStayFromTripCalendar() {
    return TripMemberStay.stayDraftForTripCalendarEdit(
      Trip(
        id: tripId,
        title: tripTitle,
        destination: '',
        address: '',
        linkUrl: '',
        photosStorageUrl: '',
        cupidonModeEnabled: cupidonModeEnabled,
        ownerId: '',
        memberUserIds: const [],
        createdAt: DateTime.now(),
        startDate: tripStartDate,
        endDate: tripEndDate,
        tripStartDayPart: tripStartDayPart,
        tripEndDayPart: tripEndDayPart,
        isDayTrip: isDayTrip,
      ),
    );
  }
}
