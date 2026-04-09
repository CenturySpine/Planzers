import 'package:intl/date_symbol_data_local.dart';

/// Required before using [DateFormat] with explicit locales (e.g. fr_FR).
Future<void> initializeAppDateFormatting() async {
  await initializeDateFormatting('fr_FR');
  await initializeDateFormatting('en_US');
}
