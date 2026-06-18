import 'package:flutter/material.dart';
import 'package:planerz/core/firebase/firebase_target.dart';

/// Wrapper kept for app bootstrap structure; preview is indicated in the trips header.
class PreviewEnvironmentChrome extends StatelessWidget {
  const PreviewEnvironmentChrome({
    required this.target,
    required this.child,
    super.key,
  });

  final FirebaseTarget target;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
