/// Discriminator for trip chat message payloads in Firestore.
enum TripMessageKind {
  text,
  image,
}

extension TripMessageKindFirestore on TripMessageKind {
  String get firestoreValue => switch (this) {
        TripMessageKind.text => 'text',
        TripMessageKind.image => 'image',
      };

  static TripMessageKind fromFirestore(Object? raw, {required bool hasImageUrl}) {
    final value = (raw is String ? raw : '').trim().toLowerCase();
    if (value == 'image' || hasImageUrl) {
      return TripMessageKind.image;
    }
    return TripMessageKind.text;
  }
}
