import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

class ExternalProviderAdminSummary {
  const ExternalProviderAdminSummary({
    required this.providerId,
    required this.displayName,
    required this.iconUrl,
    required this.authorizeUrl,
    required this.tokenUrl,
    required this.apiBaseUrl,
    required this.scope,
    required this.clientId,
  });

  final String providerId;
  final String displayName;
  final String iconUrl;
  final String authorizeUrl;
  final String tokenUrl;
  final String apiBaseUrl;
  final String scope;
  final String clientId;

  factory ExternalProviderAdminSummary.fromMap(Map<dynamic, dynamic> map) {
    return ExternalProviderAdminSummary(
      providerId: (map['providerId'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      iconUrl: (map['iconUrl'] as String?) ?? '',
      authorizeUrl: (map['authorizeUrl'] as String?) ?? '',
      tokenUrl: (map['tokenUrl'] as String?) ?? '',
      apiBaseUrl: (map['apiBaseUrl'] as String?) ?? '',
      scope: (map['scope'] as String?) ?? '',
      clientId: (map['clientId'] as String?) ?? '',
    );
  }
}

/// Administration-only: manages the registry of external ecosystem
/// providers (e.g. Ridgegear) Planerz users can connect their account to.
/// Mirror image of [OAuthClientsRepository]. The client secret is only ever
/// sent up (write-only) — it is never returned by any of these calls.
class ExternalProvidersRepository {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion);

  Future<List<ExternalProviderAdminSummary>> listProviders() async {
    final result =
        await _functions.httpsCallable('listExternalProvidersAdmin').call();
    final data = result.data as Map;
    final providers = (data['providers'] as List?) ?? const [];
    return providers
        .map((p) => ExternalProviderAdminSummary.fromMap(p as Map))
        .toList();
  }

  Future<void> createProvider({
    required String providerId,
    required String displayName,
    required String iconUrl,
    required String authorizeUrl,
    required String tokenUrl,
    required String apiBaseUrl,
    required String scope,
    required String clientId,
    required String clientSecret,
  }) async {
    await _functions.httpsCallable('createExternalProvider').call({
      'providerId': providerId,
      'displayName': displayName,
      'iconUrl': iconUrl,
      'authorizeUrl': authorizeUrl,
      'tokenUrl': tokenUrl,
      'apiBaseUrl': apiBaseUrl,
      'scope': scope,
      'clientId': clientId,
      'clientSecret': clientSecret,
    });
  }

  Future<void> updateSecret({
    required String providerId,
    required String clientSecret,
  }) async {
    await _functions.httpsCallable('updateExternalProviderSecret').call({
      'providerId': providerId,
      'clientSecret': clientSecret,
    });
  }

  /// Edits non-secret fields (here: just `apiBaseUrl`) without touching the
  /// secret or recreating the provider.
  Future<void> updateApiBaseUrl({
    required String providerId,
    required String apiBaseUrl,
  }) async {
    await _functions.httpsCallable('updateExternalProviderConfig').call({
      'providerId': providerId,
      'apiBaseUrl': apiBaseUrl,
    });
  }

  Future<void> deleteProvider(String providerId) async {
    await _functions
        .httpsCallable('deleteExternalProvider')
        .call({'providerId': providerId});
  }
}
