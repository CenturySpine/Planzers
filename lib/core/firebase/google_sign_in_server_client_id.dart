import 'package:planzers/core/firebase/firebase_target.dart';

/// Web OAuth client ID (`client_type`: 3) from each flavor's
/// `google-services.json`, required by Android Credential Manager for a valid
/// ID token when initializing Google Sign-In on Android.
String googleSignInServerClientIdFor(FirebaseTarget target) {
  switch (target) {
    case FirebaseTarget.preview:
      return '426381891835-puh9j653ubiphukrg6o6572dvdfd19h8.apps.googleusercontent.com';
    case FirebaseTarget.prod:
      return '936277491452-hupshq346o9rpbtkiejdol6s3c1l2p8b.apps.googleusercontent.com';
  }
}
