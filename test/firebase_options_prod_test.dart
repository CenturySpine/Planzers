import 'package:flutter_test/flutter_test.dart';
import 'package:planerz/firebase_options_prod.dart';

void main() {
  test('production web Firebase options use the registered prod app', () {
    final options = DefaultFirebaseOptionsProd.web;

    expect(options.projectId, 'planerz');
    expect(options.appId, '1:936277491452:web:1794a04a8c81d6f8f1e179');
    expect(options.messagingSenderId, '936277491452');
  });
}
