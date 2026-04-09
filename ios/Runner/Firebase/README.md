# iOS Firebase files by environment

Place the native Firebase plist files here:

- `ios/Runner/Firebase/prod/GoogleService-Info.plist` for Firebase project `planzers`
- `ios/Runner/Firebase/preview/GoogleService-Info.plist` for Firebase project `planzers-preview`

These files are intentionally gitignored.

## Where to download

For each Firebase project:

1. Open Firebase Console.
2. Select project (`planzers` or `planzers-preview`).
3. Open **Project settings** (gear icon).
4. In **Your apps**, select the **iOS app** with bundle id `com.planzers.planzers`.
5. Download **GoogleService-Info.plist**.
6. Save it in the matching folder above.
