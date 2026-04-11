import 'configure_url_strategy_stub.dart'
    if (dart.library.html) 'configure_url_strategy_web.dart' as url_strategy_impl;

/// Web: path URLs (`/invite?…`) so invite links match mobile and hosting rewrites.
void configureUrlStrategyIfWeb() {
  url_strategy_impl.configureUrlStrategyForPlatform();
}
