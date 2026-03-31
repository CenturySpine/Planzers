import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: FirebaseAuth.instance,
    googleSignIn: GoogleSignIn.instance,
  );
});

class AuthRepository {
  AuthRepository({
    required this.auth,
    required this.googleSignIn,
  });

  final FirebaseAuth auth;
  final GoogleSignIn googleSignIn;
  bool _googleSignInInitialized = false;

  Future<UserCredential> signInWithGoogle() async {
    final provider = GoogleAuthProvider();

    if (kIsWeb) {
      return auth.signInWithPopup(provider);
    }

    final isDesktop =
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isDesktop) {
      throw UnsupportedError(
        'Google Sign-In n est pas disponible sur Desktop pour cette app. '
        'Teste sur Android, iOS, ou Web.',
      );
    }

    try {
      return await auth.signInWithProvider(provider);
    } on UnimplementedError {
      throw UnsupportedError(
        'Google Sign-In non supporte sur cette plateforme.',
      );
    } catch (_) {
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
  }
}
