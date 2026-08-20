import 'package:cloud_functions/cloud_functions.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

class OAuthClientSummary {
  const OAuthClientSummary({
    required this.clientId,
    required this.displayName,
    required this.iconUrl,
    required this.redirectUris,
    required this.scopesAllowed,
  });

  final String clientId;
  final String displayName;
  final String iconUrl;
  final List<String> redirectUris;
  final List<String> scopesAllowed;

  factory OAuthClientSummary.fromMap(Map<dynamic, dynamic> map) {
    return OAuthClientSummary(
      clientId: (map['clientId'] as String?) ?? '',
      displayName: (map['displayName'] as String?) ?? '',
      iconUrl: (map['iconUrl'] as String?) ?? '',
      redirectUris: (map['redirectUris'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      scopesAllowed: (map['scopesAllowed'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// Administration-only: manages third-party OAuth clients (e.g. Ridgegear)
/// allowed to request read access to a user's trips via the public API.
class OAuthClientsRepository {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion);

  Future<List<OAuthClientSummary>> listClients() async {
    final result = await _functions.httpsCallable('listOAuthClients').call();
    final data = result.data as Map;
    final clients = (data['clients'] as List?) ?? const [];
    return clients
        .map((c) => OAuthClientSummary.fromMap(c as Map))
        .toList();
  }

  /// Returns the freshly generated `clientSecret` — shown once, never
  /// stored or retrievable again.
  Future<String> createClient({
    required String clientId,
    required String displayName,
    required String iconUrl,
    required List<String> redirectUris,
    required List<String> scopesAllowed,
  }) async {
    final result = await _functions.httpsCallable('createOAuthClient').call({
      'clientId': clientId,
      'displayName': displayName,
      'iconUrl': iconUrl,
      'redirectUris': redirectUris,
      'scopesAllowed': scopesAllowed,
    });
    final data = result.data as Map;
    return (data['clientSecret'] as String?) ?? '';
  }

  Future<void> deleteClient(String clientId) async {
    await _functions
        .httpsCallable('deleteOAuthClient')
        .call({'clientId': clientId});
  }
}
