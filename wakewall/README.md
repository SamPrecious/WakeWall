# WakeWall

WakeWall is an Android live wallpaper app that prepares the next selected photo
when the screen turns off, so it is ready for the next wake.

## Features

- Multi-photo import through Android Photos or file providers
- In-order and shuffle rotation modes
- Screen-proportional preview and crop editor
- Drag-to-reorder and drag-to-remove wallpaper collection
- Pause and manual-next controls
- Portable `.wakewall` backup and restore files containing photos, crops, order,
  and settings
- Native Kotlin live wallpaper engine with a prepared next-frame cache

## Architecture

- `lib/`: Flutter UI, crop editor, controller, and Android platform bridge
- `android/.../WakeWallService.kt`: live wallpaper rendering and screen events
- `android/.../WakeWallStore.kt`: image persistence, previews, crops, and backups
- `android/.../MainActivity.kt`: Android pickers and Flutter platform channel

WakeWall copies readable original images into app-private storage without
re-encoding them. Unusual provider results use a high-quality normalized JPEG
fallback. The native wallpaper engine reads those files directly, while Flutter
receives smaller cached previews for the in-app UI.

## Run

```powershell
flutter run
```

Open **Settings -> Use WakeWall** to select the live wallpaper.

## Verify

```powershell
flutter test
flutter analyze
cd android
.\gradlew.bat :app:compileDebugKotlin :app:lintDebug
```

## Personal Release APK

```powershell
flutter build apk --release --split-per-abi
```

Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` through Samsung
My Files. Release builds currently use the Android debug signing key; configure
a permanent signing key before public distribution.
