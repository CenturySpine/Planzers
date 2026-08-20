import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

final externalConnectionRepositoryProvider =
    Provider<ExternalConnectionRepository>((ref) {
  return ExternalConnectionRepository();
});

class ExternalProviderPublicInfo {
  const ExternalProviderPublicInfo({
    required this.providerId,
    required this.displayName,
    required this.iconUrl,
    required this.scope,
  });

  final String providerId;
  final String displayName;
  final String iconUrl;
  final String scope;

  factory ExternalProviderPublicInfo.fromMap(Map<dynamic, dynamic> map) {
    return ExternalProviderPublicInfo(
      providerId: (map['providerId'] as String?)?.trim() ?? '',
      displayName: (map['displayName'] as String?)?.trim() ?? '',
      iconUrl: (map['iconUrl'] as String?)?.trim() ?? '',
      scope: (map['scope'] as String?)?.trim() ?? '',
    );
  }
}

/// Client for Planerz's own "Planerz-as-OAuth-client" endpoints: browsing
/// the registry of connectable external providers and starting/completing
/// a connection. The code -> access token exchange itself happens
/// server-side (`completeExternalConnection`), never in this app.
class ExternalConnectionRepository {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion);

  Future<List<ExternalProviderPublicInfo>> listProviders() async {
    final callable = _functions.httpsCallable('listExternalProviders');
    final result = await callable.call();
    final data = result.data as Map;
    final providers = (data['providers'] as List?) ?? const [];
    return providers
        .map((p) => ExternalProviderPublicInfo.fromMap(p as Map))
        .toList();
  }

  /// `resumeContext` is an optional, free-form map (e.g.
  /// `{'tripId': tripId, 'module': 'ridgegear'}`) echoed back unchanged by
  /// [completeConnection] once the connection succeeds, so the caller can
  /// pick back up exactly where it left off (e.g. reopen a trip's module
  /// picker) instead of always landing on the generic connected-apps screen.
  Future<String> beginConnection({
    required String providerId,
    required String redirectUri,
    Map<String, dynamic>? resumeContext,
  }) async {
    final callable = _functions.httpsCallable('beginExternalConnection');
    final result = await callable.call(<String, dynamic>{
      'providerId': providerId,
      'redirectUri': redirectUri,
      if (resumeContext != null) 'resumeContext': resumeContext,
    });
    final data = result.data as Map;
    return (data['authorizeUrl'] as String?) ?? '';
  }

  /// No `providerId` here: the provider's redirect only ever carries back
  /// `code` and `state` (standard OAuth2) — `state` alone already
  /// identifies the pending connection server-side.
  ///
  /// Returns the `resumeContext` passed to [beginConnection], if any.
  Future<Map<String, dynamic>?> completeConnection({
    required String code,
    required String state,
  }) async {
    final callable = _functions.httpsCallable('completeExternalConnection');
    final result = await callable.call(<String, dynamic>{
      'code': code,
      'state': state,
    });
    final data = result.data as Map?;
    final resumeContext = data?['resumeContext'] as Map?;
    return resumeContext?.map((key, value) => MapEntry(key.toString(), value));
  }

  /// Generic authenticated call to a connected provider's own business API
  /// (e.g. Ridgegear's `/v1/projects`), using the caller's stored access
  /// token — provider-agnostic; interpreting the returned JSON is the
  /// caller's job.
  Future<Map<String, dynamic>> callProviderApi({
    required String providerId,
    required String path,
  }) async {
    final callable = _functions.httpsCallable('callExternalProviderApi');
    final result = await callable.call(<String, dynamic>{
      'providerId': providerId,
      'path': path,
    });
    final data = result.data as Map;
    return (data['data'] as Map).map((key, value) => MapEntry(key.toString(), value));
  }
}
