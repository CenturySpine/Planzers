enum FirebaseTarget {
  prod,
  preview,
}

extension FirebaseTargetX on FirebaseTarget {
  bool get isPreview => this == FirebaseTarget.preview;
}
