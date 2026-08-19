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

  Future<String> beginConnection({
    required String providerId,
    required String redirectUri,
  }) async {
    final callable = _functions.httpsCallable('beginExternalConnection');
    final result = await callable.call(<String, dynamic>{
      'providerId': providerId,
      'redirectUri': redirectUri,
    });
    final data = result.data as Map;
    return (data['authorizeUrl'] as String?) ?? '';
  }

  Future<void> completeConnection({
    required String providerId,
    required String code,
    required String state,
  }) async {
    final callable = _functions.httpsCallable('completeExternalConnection');
    await callable.call(<String, dynamic>{
      'providerId': providerId,
      'code': code,
      'state': state,
    });
  }
}
