import 'dart:js_interop';

@JS('window.location.reload')
external void _reload();

void reloadPage() => _reload();
