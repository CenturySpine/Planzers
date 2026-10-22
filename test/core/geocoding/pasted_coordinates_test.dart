import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/core/geocoding/pasted_coordinates.dart';

void main() {
  void expectPoint(String input, double lat, double lng) {
    final point = parsePastedCoordinates(input);
    expect(point, isNotNull, reason: input);
    expect(point!.lat, closeTo(lat, 1e-6), reason: input);
    expect(point.lng, closeTo(lng, 1e-6), reason: input);
  }

  test('decimal coordinates, as Google Maps copies them', () {
    expectPoint('37.047812, 15.010234', 37.047812, 15.010234);
    expectPoint('  37.047812,15.010234 ', 37.047812, 15.010234);
    expectPoint('37.047812 15.010234', 37.047812, 15.010234);
    expectPoint('(-22.8, -67.8)', -22.8, -67.8);
  });

  test('decimal coordinates with French decimal commas', () {
    expectPoint('37,047812, 15,010234', 37.047812, 15.010234);
    expectPoint('37,047812 15,010234', 37.047812, 15.010234);
    expectPoint('37,047812;15,010234', 37.047812, 15.010234);
  });

  test('degrees, minutes, seconds', () {
    expectPoint(
      '37°02\'52.1"N 15°00\'36.8"E',
      37 + 2 / 60 + 52.1 / 3600,
      15 + 0 / 60 + 36.8 / 3600,
    );
    expectPoint('22°48′S 67°48′O', -(22 + 48 / 60), -(67 + 48 / 60));
  });

  test('Google Maps links: the place wins over the view', () {
    expectPoint(
      'https://www.google.com/maps/place/Borgo+degli+Ulivi/@37.05,14.9,15z/'
      'data=!3m1!4b1!4m9!3m8!1s0x0:0x0!8m2!3d37.0478!4d15.0102!16s',
      37.0478,
      15.0102,
    );
    expectPoint(
      'https://www.google.com/maps/@36.8912,15.0712,17z',
      36.8912,
      15.0712,
    );
    expectPoint(
      'https://www.google.com/maps/search/36.8912,+15.0712?entry=tts',
      36.8912,
      15.0712,
    );
    expectPoint(
      'https://www.google.com/maps?q=36.8912,15.0712',
      36.8912,
      15.0712,
    );
    expectPoint(
      'https://www.google.com/maps/search/?api=1&query=36.8912%2C15.0712',
      36.8912,
      15.0712,
    );
  });

  test('Apple Maps and OpenStreetMap links', () {
    expectPoint('https://maps.apple.com/?ll=36.8912,15.0712', 36.8912, 15.0712);
    expectPoint(
      'https://www.openstreetmap.org/?mlat=36.8912&mlon=15.0712#map=16/36.9/15.1',
      36.8912,
      15.0712,
    );
    expectPoint(
      'https://www.openstreetmap.org/#map=16/36.8912/15.0712',
      36.8912,
      15.0712,
    );
  });

  test('no point in ordinary searches, short links or out-of-range values',
      () {
    expect(parsePastedCoordinates('Borgo degli Ulivi'), isNull);
    expect(parsePastedCoordinates('12 rue de la Paix'), isNull);
    expect(parsePastedCoordinates('12 34'), isNull);
    expect(parsePastedCoordinates('https://maps.app.goo.gl/AbCd123'), isNull);
    expect(parsePastedCoordinates('95.1, 15.2'), isNull);
    expect(parsePastedCoordinates(''), isNull);
  });

  test('coordinates read back with five decimals', () {
    expect(formatCoordinates(37.0478123, 15.0102), '37.04781, 15.01020');
  });
}
