/// Release metadata used by [latestReleaseProvider] (GitHub prod or Storage preview).
class RemoteRelease {
  const RemoteRelease({required this.tag, required this.apkDownloadUrl});

  final String tag;
  final String apkDownloadUrl;
}
