class TripCarpoolSection {
  const TripCarpoolSection({
    this.shoppingMeetupLinkUrl = '',
    this.shoppingMeetupLinkPreview = const <String, dynamic>{},
    this.cars = const <Map<String, dynamic>>[],
  });

  final String shoppingMeetupLinkUrl;
  final Map<String, dynamic> shoppingMeetupLinkPreview;
  final List<Map<String, dynamic>> cars;

  factory TripCarpoolSection.fromMap(Map<String, dynamic> data) {
    return TripCarpoolSection(
      shoppingMeetupLinkUrl: (data['shoppingMeetupLinkUrl'] as String? ?? '').trim(),
      shoppingMeetupLinkPreview:
          (data['shoppingMeetupLinkPreview'] as Map<String, dynamic>?) ??
              const <String, dynamic>{},
      cars: ((data['cars'] as List<dynamic>?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList(growable: false),
    );
  }
}
