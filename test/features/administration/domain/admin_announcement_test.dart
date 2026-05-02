import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/features/administration/domain/admin_announcement.dart';

void main() {
  group('AdminAnnouncement.userDismissAllowedFromFirestoreData', () {
    test('defaults to true when field absent', () {
      expect(
        AdminAnnouncement.userDismissAllowedFromFirestoreData(
          const <String, dynamic>{},
        ),
        true,
      );
    });

    test('reads explicit true and false', () {
      expect(
        AdminAnnouncement.userDismissAllowedFromFirestoreData(
          const <String, dynamic>{'userDismissAllowed': true},
        ),
        true,
      );
      expect(
        AdminAnnouncement.userDismissAllowedFromFirestoreData(
          const <String, dynamic>{'userDismissAllowed': false},
        ),
        false,
      );
    });

    test('defaults to true when value is not a bool', () {
      expect(
        AdminAnnouncement.userDismissAllowedFromFirestoreData(
          const <String, dynamic>{'userDismissAllowed': 'yes'},
        ),
        true,
      );
    });
  });
}
