import 'package:firebase_core/firebase_core.dart';
import 'package:planzers/core/firebase/firebase_target.dart';
import 'package:planzers/firebase_options_preview.dart';
import 'package:planzers/firebase_options_prod.dart';

FirebaseOptions firebaseOptionsFor(FirebaseTarget target) {
  switch (target) {
    case FirebaseTarget.prod:
      return DefaultFirebaseOptionsProd.currentPlatform;
    case FirebaseTarget.preview:
      return DefaultFirebaseOptionsPreview.currentPlatform;
  }
}
