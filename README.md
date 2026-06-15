# WakeWall

WakeWall is an Android live wallpaper app that rotates through a user-selected
collection of photos. It is built to solve a small but stubborn Android
personalisation gap: many phones can rotate lock-screen wallpapers, but home
screen wallpaper rotation is limited, inconsistent, or hidden behind clunky
utility apps.

WakeWall keeps the workflow simple:

```text
Choose wallpapers -> preview and adjust -> enable WakeWall -> wake to a fresh wallpaper
```

Under the hood, WakeWall uses a native Android live wallpaper engine so the next
image can be prepared before the phone wakes. The result is a wallpaper switcher
that feels closer to a polished personalisation feature than a background
utility.

> This README covers the core WakeWall app. Experimental AI-fill work is
> intentionally outside this overview.

## Contents

- [Demo](#demo)
- [Built With](#built-with)
- [Project Highlights](#project-highlights)
- [Feature Overview](#feature-overview)
- [How The Wallpaper Switching Works](#how-the-wallpaper-switching-works)
- [Image Quality And Cropping](#image-quality-and-cropping)
- [Albums, Backup, And Storage](#albums-backup-and-storage)
- [Architecture](#architecture)
- [Key Files](#key-files)
- [Running And Building](#running-and-building)
- [Current Status](#current-status)
- [Project Goal](#project-goal)

## Demo

Add GIFs or short screen recordings here as the release visuals come together.
They are separated by feature so someone new to the project can understand the
app quickly without reading every implementation detail first.

### 1. Home Screen

Show the main screen, large phone-shaped preview, `Up Next` strip, and quick
actions.

```md
![WakeWall home screen](docs/gifs/home-screen.gif)
```

### 2. Automatic Rotation

Show the wallpaper changing through the lock/wake cycle or via the manual next
action.

```md
![WakeWall wallpaper rotation](docs/gifs/wallpaper-rotation.gif)
```

### 3. Crop And Display Modes

Show the crop editor, pinch/drag adjustment, Fill, Blur, and Fit modes.

```md
![WakeWall crop editor](docs/gifs/crop-editor.gif)
```

### 4. Albums And Reordering

Show album filtering, long-press drag-to-reorder, drag-to-remove, and Undo.

```md
![WakeWall albums and reordering](docs/gifs/albums-reorder-remove.gif)
```

### 5. Backup And Restore

Show exporting or restoring a `.wakewall` backup file.

```md
![WakeWall backup and restore](docs/gifs/backup-restore.gif)
```

## Built With

WakeWall is intentionally small on the surface, but it combines a few different
Android and Flutter pieces:

- **Flutter and Dart** for the app shell, single-screen interface, crop editor,
  albums, settings, and themes.
- **Kotlin** for the Android live wallpaper engine, image import, render cache,
  backups, and storage cleanup.
- **Android `WallpaperService`** for native wallpaper drawing instead of a
  foreground background service.
- **Flutter MethodChannels** to keep the Flutter UI and Kotlin wallpaper engine
  in sync.
- **Android Photos and Files pickers** for importing user-selected images
  without broad photo-library permissions.
- **App-private storage** for originals, cropped previews, wallpaper renders,
  and portable `.wakewall` backup files.

## Project Highlights

- **Hybrid Flutter + Kotlin architecture:** Flutter handles the app interface,
  while Kotlin owns the live wallpaper engine and native image pipeline.
- **Android-native live wallpaper rendering:** WakeWall draws directly to the
  wallpaper surface instead of repeatedly setting static wallpapers.
- **Screen-off preparation:** the next wallpaper is prepared before wake, which
  reduces the visible delay when the phone turns back on.
- **Quality-preserving image storage:** readable originals are copied into
  app-private storage without unnecessary re-encoding.
- **Per-wallpaper crop settings:** every image stores its own zoom, offset,
  display mode, and Fit background colour.
- **Lightweight albums:** wallpapers can belong to multiple albums without
  duplicating image files.
- **Portable backups:** `.wakewall` backups include photos, order, crops,
  albums, display modes, and app settings.
- **Storage cleanup:** interrupted imports, finalized removals, cached previews,
  and orphaned files are handled deliberately.
- **Responsive interaction polish:** selection state, album filters, haptics,
  and notification fades are tuned so the app feels immediate rather than
  utility-like.

## Feature Overview

WakeWall currently supports:

- multi-photo import through Android Photos or Files;
- a single-screen home layout with a large preview and `Up Next` strip;
- `Shuffle` and `In Order` rotation modes;
- pause and manual-next controls;
- per-image crop, zoom, and drag positioning;
- Fill, Blur, and Fit display modes;
- optional solid background colours for Fit mode;
- album filtering for both the visible collection and rotation set;
- long-press drag-to-reorder and drag-to-remove thumbnails;
- a short Undo window after removing wallpapers;
- optional wallpaper scrolling for launchers that support it;
- System, Light, Dark, and Midnight themes;
- subtle haptic feedback on key interactions;
- backup and restore using `.wakewall` files.

The product is intentionally scoped. WakeWall is not a photo manager, social
app, cloud sync service, or account-based platform. Its job is to make a
personal wallpaper collection feel alive with as little friction as possible.

## How The Wallpaper Switching Works

WakeWall is implemented as a live wallpaper because that is the most reliable
way for an Android app to own wallpaper drawing.

A simpler-looking approach would be to listen for screen on/off broadcasts and
set a new static wallpaper each time. On modern Android that is unreliable for a
dormant app, and a foreground service would add a persistent notification.
WakeWall avoids that trade-off by living inside Android's wallpaper system.

The native engine follows this rough flow:

```text
User selects wallpapers
  -> WakeWall stores originals and cached renders
  -> Android live wallpaper engine becomes active
  -> next wallpaper frame is prepared in advance
  -> screen turns off
  -> WakeWall atomically advances the shared index
  -> prepared frame is drawn while the surface is hidden
  -> phone wakes with the new wallpaper already visible
```

Android may create multiple wallpaper engine instances for home screen, lock
screen, preview, or recreation events. WakeWall stores shared state in
`WakeWallStore` so those engines do not double-advance, revert a manual
selection, or visibly skip through multiple images.

## Image Quality And Cropping

WakeWall treats user photos as source assets, not just thumbnails.

When possible, selected images are copied into app-private storage without
re-encoding. If an Android provider returns unusual image data, WakeWall falls
back to a normalized high-quality JPEG so the image can still be used.

From the stored source, WakeWall creates replaceable derived files:

```text
Original private copy
  -> full-aspect source preview for crop editing
  -> large cropped preview for the home screen
  -> small cropped thumbnail for Up Next
  -> phone-sized render for the live wallpaper engine
  -> optional wider render for wallpaper scrolling
```

The crop editor supports:

- **Fill:** fills the screen and may crop edges.
- **Blur:** keeps the full image visible over a blurred background.
- **Fit:** keeps the full image visible over a chosen solid background colour.

The Flutter preview and native Kotlin render are kept visually aligned so the
crop editor behaves like a real preview of the final wallpaper.

## Albums, Backup, And Storage

### Albums

Albums are stored as memberships, not duplicated folders.

A wallpaper can belong to multiple albums, and `All Wallpapers` remains the
catch-all view. Selecting one or more albums filters the home screen and the
rotation set, but the underlying image is still stored once.

Deleting an album can remove only the album or also remove photos exclusive to
that album. Photos shared with another album are kept.

### Backup And Restore

WakeWall exports portable `.wakewall` backup files. A backup includes:

- image files;
- wallpaper order;
- crop transforms;
- display modes;
- Fit colours;
- albums and memberships;
- active album filters;
- settings.

Restore validates the backup before replacing the current setup and warns before
overwriting an existing collection.

### Storage Cleanup

Wallpaper images can be large, so WakeWall tracks file lifecycle carefully.

- Imports are staged until they are safely added to the collection.
- Interrupted imports can be cleaned automatically.
- Removed wallpapers remain available during the Undo window.
- Finalized removals delete the original private copy, cached previews, renders,
  and metadata.
- Derived previews and renders can be recreated from the stored source.

## Architecture

WakeWall is split between Flutter and native Android code.

```text
Flutter UI
  -> WakeWallController
  -> NativeWallpaperBridge
  -> Android MethodChannel
  -> WakeWallStore / WakeWallService
```

Flutter is used where iteration speed and UI polish matter:

- main screen;
- settings and album sheets;
- crop editor;
- thumbnail selection;
- drag-to-reorder and drag-to-remove;
- optimistic UI state;
- theme handling.

Kotlin is used where Android platform behaviour and performance matter:

- `WallpaperService` and `WallpaperService.Engine`;
- wallpaper surface drawing;
- screen-off / visibility handling;
- image import and storage;
- cached preview and render generation;
- backup and restore file access;
- Photos and Files picker integration;
- storage cleanup and transaction tracking.

This split keeps the app pleasant to build in Flutter while keeping the
time-sensitive wallpaper path native.

## Key Files

```text
lib/
  app.dart                         App entry point and theme selection
  controllers/wakewall_controller.dart
                                   Main Flutter state controller
  screens/home_screen.dart          Main one-screen app interface
  screens/crop_editor_screen.dart   Crop and display-mode editor
  services/native_wallpaper_bridge.dart
                                   Flutter <-> Android platform channel
  theme/wakewall_theme.dart         Light, Dark, and Midnight palettes
  widgets/abstract_wallpaper.dart   Flutter wallpaper preview renderer

android/app/src/main/kotlin/com/zambl/wakewall/
  MainActivity.kt                   Android pickers and platform-channel entry
  WakeWallService.kt                Native live wallpaper engine
  WakeWallStore.kt                  Storage, crops, renders, albums, backups
  WakeWallFileStore.kt              Managed image/cache cleanup
  WakeWallTransactionStore.kt       Import/removal transaction tracking
  WakeWallBlurRenderer.kt           Native blur render helper
```

For more detailed product and implementation notes, see
[PROJECT_SPEC.md](PROJECT_SPEC.md).

## Running And Building

WakeWall is currently Android-focused. The Flutter project contains generated
platform folders, but the live wallpaper feature is Android-specific.

### Run

From the Flutter project directory:

```powershell
flutter pub get
flutter run
```

To enable WakeWall on a device:

1. Open the app.
2. Add one or more wallpapers.
3. Open Settings.
4. Tap `Use WakeWall`.
5. Select WakeWall in Android's live wallpaper setup flow.

### Verify

```powershell
flutter analyze
flutter test
```

Optional Android checks:

```powershell
cd android
.\gradlew.bat :app:compileDebugKotlin :app:lintDebug
```

### Build Release APK

Flutter creates `app-release.apk` by default. The short script below builds the
release APK and gives the final file the stable tester-friendly name
`WakeWall.apk`.

```powershell
$ErrorActionPreference = 'Stop'
flutter build apk --release
$outputDir = Join-Path (Get-Location) 'build\app\outputs\flutter-apk'
$releaseApk = Join-Path $outputDir 'app-release.apk'
$releaseSha = Join-Path $outputDir 'app-release.apk.sha1'
$wakeWallApk = Join-Path $outputDir 'WakeWall.apk'
Move-Item -LiteralPath $releaseApk -Destination $wakeWallApk -Force
Remove-Item -LiteralPath $releaseSha -Force -ErrorAction SilentlyContinue
Write-Output "Built $wakeWallApk"
```

The APK will be available at:

```text
build/app/outputs/flutter-apk/WakeWall.apk
```

## Current Status

WakeWall is a working Android prototype with:

- a native live wallpaper engine;
- automatic screen-off wallpaper rotation;
- multi-image import;
- crop and display-mode editing;
- album filtering;
- drag-to-reorder and drag-to-remove;
- backup and restore;
- light/dark theme support.

Before a broader public release, the main remaining work is:

- more device testing across Android versions, launchers, and OEMs;
- final release signing configuration;
- Play Store privacy and listing copy;
- long-run storage and battery validation;
- final UI polish from tester feedback.

## Project Goal

WakeWall is built around a narrow product promise: make home-screen wallpaper
rotation feel native, polished, and effortless on Android.

The technical challenge is not simply displaying images. The challenge is doing
it at the right moment, with good crop control, without visible wake delay,
without wasting battery, and without turning a simple personalisation app into a
background utility.
