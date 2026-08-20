import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:planerz/core/firebase/firebase_functions_region.dart';

final oauthRepositoryProvider = Provider<OAuthRepository>((ref) {
  return OAuthRepository();
});

class OAuthClientPublicInfo {
  const OAuthClientPublicInfo({
    required this.displayName,
    required this.iconUrl,
    required this.redirectUris,
  });

  final String displayName;
  final String iconUrl;
  final List<String> redirectUris;

  factory OAuthClientPublicInfo.fromMap(Map<dynamic, dynamic> map) {
    return OAuthClientPublicInfo(
      displayName: (map['displayName'] as String?)?.trim() ?? '',
      iconUrl: (map['iconUrl'] as String?)?.trim() ?? '',
      redirectUris: (map['redirectUris'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// Client for Planerz's own OAuth 2.0 authorization endpoints (consent
/// screen data + issuing single-use authorization codes). The actual code
/// -> access token exchange happens server-to-server between the third-party
/// app and Planerz's `/oauth/token` HTTP endpoint — never from this app.
class OAuthRepository {
  FirebaseFunctions get _functions =>
      FirebaseFunctions.instanceFor(region: kFirebaseFunctionsRegion);

  Future<OAuthClientPublicInfo> getClientPublicInfo(String clientId) async {
    final callable = _functions.httpsCallable('getOAuthClientPublicInfo');
    final result = await callable.call(<String, dynamic>{'clientId': clientId});
    return OAuthClientPublicInfo.fromMap(result.data as Map);
  }

  Future<String> authorize({
    required String clientId,
    required String redirectUri,
    required String scope,
    required String state,
  }) async {
    final callable = _functions.httpsCallable('authorizeOAuthClient');
    final result = await callable.call(<String, dynamic>{
      'clientId': clientId,
      'redirectUri': redirectUri,
      'scope': scope,
      if (state.isNotEmpty) 'state': state,
    });
    final data = result.data as Map;
    return (data['redirectUrl'] as String?) ?? '';
  }
}
