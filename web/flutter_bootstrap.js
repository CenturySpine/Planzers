{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own worker is deprecated and only
// unregisters itself, which would evict the offline worker (sw.js) that
// index.html registers on the same scope.
_flutter.loader.load();
