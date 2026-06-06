# WakeWall

WakeWall is an Android live wallpaper prototype that prepares a fresh design
when the device screen turns off, ready for the next wake.

## Current prototype

- Responsive single-screen Flutter interface
- Device-proportional wallpaper preview and horizontally scrolling collection
- Sequential and shuffle rotation modes
- Pause, manual next, fit-mode, reorder, and remove controls
- Non-destructive full-screen crop editor with pinch, drag, reset, and save
- Native Kotlin `WallpaperService`
- Forced screen-off preparation with visibility/surface recovery redraws
- Single-frame next-wallpaper cache for near-instant rapid screen-off switching
- Per-cycle duplicate-event protection and an in-app diagnostics panel

The prototype uses four bundled procedural designs so wake-event reliability can
be validated before gallery permissions and image persistence are introduced.

## Run

```powershell
flutter run
```

Open **Settings -> Make WakeWall Active** to select the live wallpaper. The
diagnostics panel records which Android events are received during testing.

## Personal release APK

Build the smaller ARM64 release used by modern Samsung phones:

```powershell
flutter build apk --release --split-per-abi
```

Install `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` through Samsung
My Files. Enable **Install unknown apps** for My Files when prompted. Developer
Mode and USB debugging are not required after installation.

Release builds currently use the Android debug signing key so they can update
the development installation. Before public distribution, configure and safely
back up a permanent release signing key.

## Architecture

- `lib/`: Flutter interface, state, ordered wallpaper collection, and native bridge
- `android/.../WakeWallService.kt`: live wallpaper rendering and wake listeners
- `android/.../WakeWallStore.kt`: settings, current index, and diagnostics
- `android/.../MainActivity.kt`: Flutter platform-channel integration

The app uses one persistent home screen with modal overlays. The focused crop
editor is presented as a full-screen `auto_route` dialog.

## Prototype boundaries

- Gallery selection is not implemented yet.
- Reorder/remove currently affects the Flutter prototype collection only; the
  native sample wallpaper sequence remains fixed until URI persistence lands.
- Fit Entire Image is reserved for real gallery images.
