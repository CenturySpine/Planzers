import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:planerz/core/firebase/app_public_hosts.dart';
import 'package:planerz/core/firebase/firebase_target.dart';
import 'package:planerz/core/firebase/firebase_target_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: FirebaseAuth.instance,
    googleSignIn: GoogleSignIn.instance,
    firebaseTarget: ref.watch(firebaseTargetProvider),
  );
});

class AuthRepository {
  AuthRepository({
    required this.auth,
    required this.googleSignIn,
    required this.firebaseTarget,
  });

  final FirebaseAuth auth;
  final GoogleSignIn googleSignIn;
  final FirebaseTarget firebaseTarget;
  bool _googleSignInInitialized = false;
  static const String _pendingEmailLinkEmailKey =
      'auth_pending_email_link_email';

  Future<UserCredential> signInWithGoogle() async {
    final provider = GoogleAuthProvider()
      ..setCustomParameters({
        'prompt': 'select_account',
      });

    if (kIsWeb) {
      return auth.signInWithPopup(provider);
    }

    final isDesktop = defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isDesktop) {
      throw UnsupportedError(
        'Google Sign-In n est pas disponible sur Desktop pour cette app. '
        'Teste sur Android, iOS, ou Web.',
      );
    }

    // On mobile, use the native Google Sign-In flow to avoid browser
    // redirection issues and ensure return to the app.
    if (!_googleSignInInitialized) {
      await googleSignIn.initialize();
      _googleSignInInitialized = true;
    }

    final googleUser = await googleSignIn.authenticate();
    final googleAuth = googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
    );
    return auth.signInWithCredential(credential);
  }

  bool isSignInWithEmailLink(String emailLink) {
    return auth.isSignInWithEmailLink(emailLink);
  }

  Future<void> sendSignInLinkToEmail(String email) async {
    final linkDomain = _emailLinkDomain();
    final actionCodeSettings = ActionCodeSettings(
      url: _signInEmailLinkUri().toString(),
      handleCodeInApp: true,
      linkDomain: linkDomain,
    );
    await auth.sendSignInLinkToEmail(
      email: email,
      actionCodeSettings: actionCodeSettings,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingEmailLinkEmailKey, email);
  }

  Future<String?> consumePendingEmailLinkEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_pendingEmailLinkEmailKey);
    if (email == null || email.trim().isEmpty) {
      return null;
    }
    await prefs.remove(_pendingEmailLinkEmailKey);
    return email;
  }

  Future<UserCredential> signInWithEmailLink({
    required String email,
    required String emailLink,
  }) {
    return auth.signInWithEmailLink(
      email: email,
      emailLink: emailLink,
    );
  }

  Uri _signInEmailLinkUri() {
    if (kIsWeb) {
      return Uri.parse(Uri.base.origin).replace(path: '/sign-in');
    }
    final inviteBaseUri = mobileInviteBaseUriForTarget(firebaseTarget);
    return inviteBaseUri.replace(path: '/sign-in');
  }

  String? _emailLinkDomain() {
    if (kIsWeb) {
      final host = Uri.base.host.trim().toLowerCase();
      if (host.isEmpty || host == 'localhost' || host == '127.0.0.1') {
        return null;
      }
      return host;
    }

    final host =
        mobileInviteBaseUriForTarget(firebaseTarget).host.trim().toLowerCase();
    if (host.isEmpty) {
      return null;
    }
    return host;
  }
}
