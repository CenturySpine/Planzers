import 'page_reload_stub.dart'
    if (dart.library.js_interop) 'page_reload_web.dart' as impl;

/// Reloads the web page (no-op on other platforms).
void reloadPage() => impl.reloadPage();
