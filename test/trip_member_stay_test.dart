import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/trips/data/invite_join_context.dart';
import 'package:planerz/features/trips/data/trip_day_part.dart';
import 'package:planerz/features/trips/data/trip_member_stay.dart';

void main() {
  test('join stay draft mirrors trip calendar from Firestore', () {
    final start = DateTime(2026, 6, 26);
    final end = DateTime(2026, 6, 28);
    final ctx = InviteJoinContext(
      tripId: 'trip-1',
      tripTitle: 'Test',
      participants: const [],
      requiresParticipantChoice: false,
      cupidonModeEnabled: true,
      tripStartDate: start,
      tripEndDate: end,
      tripStartDayPart: TripDayPart.evening,
      tripEndDayPart: TripDayPart.morning,
    );

    final stay = ctx.defaultMemberStayFromTripCalendar();

    expect(stay.startDateKey, TripMemberStay.dateKeyFromDateTime(start));
    expect(stay.endDateKey, TripMemberStay.dateKeyFromDateTime(end));
    expect(stay.startDayPart, TripDayPart.evening);
    expect(stay.endDayPart, TripDayPart.morning);
  });

  test('join stay draft prefers selected participant slot stay', () {
    final slotStay = TripMemberStay(
      startDateKey: '2026-06-27',
      startDayPart: TripDayPart.morning,
      endDateKey: '2026-06-27',
      endDayPart: TripDayPart.evening,
    );
    final ctx = InviteJoinContext(
      tripId: 'trip-1',
      tripTitle: 'Test',
      participants: [
        InviteJoinParticipantOption(
          id: 'p1',
          displayName: 'Bruno',
          stay: slotStay,
        ),
      ],
      requiresParticipantChoice: true,
      cupidonModeEnabled: true,
      tripStartDate: DateTime(2026, 6, 26),
      tripEndDate: DateTime(2026, 6, 28),
      tripStartDayPart: TripDayPart.evening,
      tripEndDayPart: TripDayPart.morning,
    );

    final draft = ctx.stayDraftForJoin(selectedParticipantId: 'p1');
    expect(draft.startDateKey, slotStay.startDateKey);
    expect(draft.startDayPart, slotStay.startDayPart);
    expect(draft.endDateKey, slotStay.endDateKey);
    expect(draft.endDayPart, slotStay.endDayPart);
    final fallback = ctx.stayDraftForJoin(selectedParticipantId: 'missing');
    final calendar = ctx.defaultMemberStayFromTripCalendar();
    expect(fallback.startDateKey, calendar.startDateKey);
    expect(fallback.endDateKey, calendar.endDateKey);
  });

  test('invite context tracks already-member responses', () {
    const freshContext = InviteJoinContext(
      tripId: 'trip-1',
      tripTitle: 'Test',
      participants: [],
      requiresParticipantChoice: false,
      cupidonModeEnabled: true,
    );
    const alreadyMemberContext = InviteJoinContext(
      tripId: 'trip-1',
      tripTitle: 'Test',
      participants: [],
      requiresParticipantChoice: false,
      cupidonModeEnabled: true,
      alreadyMember: true,
    );

    expect(freshContext.alreadyMember, isFalse);
    expect(alreadyMemberContext.alreadyMember, isTrue);
  });
}
