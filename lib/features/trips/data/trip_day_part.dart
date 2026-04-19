/// Bound for presence on a calendar day (inclusive): morning, lunch, or dinner.
enum TripDayPart {
  morning,
  midday,
  evening,
}

TripDayPart? tripDayPartFromFirestore(String? raw) {
  switch (raw?.trim()) {
    case 'morning':
      return TripDayPart.morning;
    case 'midday':
      return TripDayPart.midday;
    case 'evening':
      return TripDayPart.evening;
    default:
      return null;
  }
}

String tripDayPartToFirestore(TripDayPart part) {
  return switch (part) {
    TripDayPart.morning => 'morning',
    TripDayPart.midday => 'midday',
    TripDayPart.evening => 'evening',
  };
}

/// French UI labels (product language).
String tripDayPartLabelFr(TripDayPart part) {
  return switch (part) {
    TripDayPart.morning => 'Matin',
    TripDayPart.midday => 'Midi',
    TripDayPart.evening => 'Soir',
  };
}

int tripDayPartSortIndex(TripDayPart part) {
  return switch (part) {
    TripDayPart.morning => 0,
    TripDayPart.midday => 1,
    TripDayPart.evening => 2,
  };
}
