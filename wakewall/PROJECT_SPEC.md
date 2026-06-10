# WakeWall Project Specification

> Living project context for developers and AI assistants.
>
> Update this document when a product decision, important behavior, architecture,
> or development convention changes. Verify claims against the code before
> editing them.

## Product Summary

WakeWall is a polished Android live wallpaper app that rotates through a
user-selected collection of images.

Its defining behavior is:

1. The user selects wallpapers.
2. WakeWall becomes the active Android live wallpaper.
3. WakeWall prepares the next wallpaper while the phone is awake.
4. When the screen turns off, WakeWall immediately draws the prepared wallpaper.
5. The next time the screen wakes, the new wallpaper should already be visible.

The product exists because Android and Samsung offer limited support for
rotating home-screen wallpapers. WakeWall should feel like a simple
personalisation app, not a technical background utility.

## Product Principles

- **Fast wake is the priority.** Users should not briefly see the old wallpaper
  before it changes.
- **Preserve image quality.** Do not unnecessarily re-encode original images or
  soften the final wallpaper.
- **Keep the interface minimal.** Add settings only when they solve a real,
  understandable user problem.
- **Make advanced behavior unobtrusive.** Albums, crop modes, scrolling, backup,
  and restore should not complicate the basic workflow.
- **Prefer reliable Android-native behavior.** The live wallpaper engine owns
  time-sensitive wallpaper rendering.
- **Avoid background-app theater.** WakeWall does not use a foreground service
  or permanent notification.
- **Storage must clean up correctly.** Interrupted imports and finalized
  deletions must not leave large orphaned files.

## Platform Scope

- Android is the supported platform.
- Samsung devices are a major testing target.
- The UI is Flutter.
- The live wallpaper engine, image storage, rendering, Android pickers, and
  backups are native Kotlin.
- iOS is not currently supported. Building an iOS equivalent requires a Mac,
  Apple signing, and a different wallpaper approach because iOS does not expose
  Android's live wallpaper APIs.

## Current User Flow

### First Use

1. WakeWall opens to an empty single-screen home page.
2. The large empty preview area acts as the `Add Wallpapers` action.
3. The user imports one or more images through Android Photos or Files.
4. If enabled, WakeWall asks which albums should receive the imported images.
5. After the first successful import, WakeWall offers to open Android's live
   wallpaper setup screen.
6. The same setup action remains available in Settings as `Use WakeWall`.

### Daily Use

- The large preview shows the currently selected wallpaper.
- The `Up Next` strip shows the collection and can scroll edge-to-edge.
- Tapping a thumbnail selects that wallpaper immediately.
- Holding a thumbnail lifts it for drag-to-reorder or drag-to-remove.
- Removal offers a three-second Undo action before files are finalized.
- Overlay actions on the large preview:
  - assign the wallpaper to albums;
  - adjust its crop and display mode;
  - manually show the next wallpaper.

### Main Navigation

WakeWall is intentionally close to a single-page app:

- Home is the persistent base screen.
- Albums and Settings open as bottom sheets.
- The crop editor is the only full-screen route and uses `auto_route`.

Do not introduce a large navigation system unless the product genuinely grows
beyond this structure.

## Rotation Behavior

### Screen-Off Switching

WakeWall rotates on screen off, not screen on.

The native engine prepares the following wallpaper in advance on a background
executor. At screen off it:

1. atomically chooses the next shared index;
2. draws the prepared frame while the surface is hidden;
3. promotes that frame to the current-frame cache;
4. begins preparing the following frame.

Screen on primarily restores the retained current frame. It must not advance the
wallpaper again.

### Multiple Wallpaper Engines

Android may create multiple `WallpaperService.Engine` instances for home,
lock-screen, preview, or recreation purposes. They share rotation state through
`WakeWallStore`.

Important invariants:

- Only one logical rotation should occur per screen-off event.
- A stale engine must not revert a manually selected wallpaper.
- Shuffle must not visibly double-skip.
- Do not add timing guards or throttles that prevent rapid screen-off/on cycling.
- Keep expensive decoding and rendering away from the screen-event thread.

### Rotation Modes

- `Shuffle` is the default.
- `In Order` advances through the active collection sequentially.
- Pause keeps the current wallpaper in place.
- Manual next remains available while WakeWall is active.

## Albums

Albums are lightweight memberships, not duplicated image folders.

- A wallpaper stores a set of album IDs.
- One wallpaper may belong to multiple albums.
- `All Wallpapers` is the catch-all view and includes every wallpaper.
- Selecting one or more albums filters both the visible home collection and the
  wallpapers used by rotation.
- An image with no album membership still exists in `All Wallpapers`.
- Import assignment may select no album, one album, or multiple albums.
- The user may choose whether WakeWall asks for album assignment after imports.

### Album Deletion

Deleting an album asks whether to delete:

- the album only; or
- the album and photos exclusive to that album.

Wallpapers shared with another album must always remain. Deleting an album must
remove its ID from retained wallpaper memberships and active album filters.

## Crop and Display Modes

Every wallpaper stores its own crop transform and display mode.

### Crop Transform

- Scale starts at `1.0`.
- The user can pinch to zoom and drag to position in every display mode.
- Crop offsets and scale are persisted per wallpaper.
- Reset returns to Fill, default crop, and default Fit background colour.

### Display Modes

- **Fill:** fills the screen and may crop image edges.
- **Fit:** shows the complete image over a user-selected solid border colour.
- **Blur:** shows the complete image over a blurred cover version of itself.

The crop editor is a preview of the actual native result. Flutter and Kotlin
rendering behavior should remain visually aligned.

## Wallpaper Scrolling

Wallpaper scrolling is optional and disabled by default.

- Enabling it prepares one wider cached wallpaper render per image.
- Fill uses the existing full horizontal scrolling movement.
- Fit and Blur remain centred while scrolling is enabled because moving a
  complete bordered foreground exposes uneven borders. Fill remains scrollable.
- Disabling scrolling returns to the normal non-scrolling pipeline.
- Valid scrolling caches are retained when scrolling is disabled so re-enabling
  it is instant.
- Users who never enable scrolling should not pay its storage or preparation
  cost.
- Scrolling must not alter or degrade the normal non-scrolling render.

## Image and Storage Pipeline

### Originals

- WakeWall copies readable selected originals into app-private storage.
- Readable originals should be preserved without re-encoding.
- The native pipeline currently caps normalized oversized/fallback image edges
  at 6144 pixels.
- Unusual or provider-backed images may use a normalized high-quality JPEG
  fallback when direct copying or decoding is impossible.

### Derived Images

WakeWall creates replaceable cached derivatives rather than modifying originals:

- a full-aspect source preview for crop editing;
- a 720-pixel-wide main cropped preview for the large Flutter preview;
- a 180-pixel-wide cropped thumbnail for `Up Next`;
- a phone-sized finished native wallpaper render;
- an optional wider scrolling render when scrolling has been enabled.

Display mode, crop, Fit colour, and scrolling composition are baked into the
appropriate derived render. Changing those properties must invalidate and
replace stale derivatives.

### Runtime Frames

The live wallpaper engine keeps current and next rendered frames in memory so
screen-off switching can copy pixels instead of decoding an original image.
Temporary bitmaps must be recycled when replaced or when an engine is destroyed.

### Cleanup

- Imports are transactionally tracked until complete.
- Incomplete imports are cleaned after interruption or force-stop recovery.
- Removed wallpapers remain temporarily restorable during the Undo window.
- Finalized removals delete the original private copy, previews, renders, and
  metadata.
- Orphaned managed files are cleaned automatically.
- Cached scrolling renders may remain after scrolling is disabled because they
  make re-enabling instant.

## Backup and Restore

- WakeWall exports portable `.wakewall` backup files.
- Backups include original private wallpaper files and the current
  configuration, including order, crops, display modes, Fit colours, albums,
  active album filters, and settings.
- Restore validates the backup before replacing the current setup.
- Restore warns before replacing a populated setup.
- Current backup format version: `3`.
- Until explicitly requested, do **not** spend development effort supporting
  older backup versions. The tester group is small and backups can be recreated.

## Current Settings

- Order: `Shuffle` or `In Order`
- Photo Source: `Ask`, `Photos`, or `Files`
- Choose Albums After Import
- Pause WakeWall
- Wallpaper Scrolling
- Backup
- Restore
- Use WakeWall / WakeWall Is Active

Avoid adding a setting when the behavior can be automatic, contextual, or
placed directly beside the feature it controls.

## Visual and Copy Direction

### Visual Style

- Dark-first interface with a charcoal/neutral background.
- Inspired by the restrained dark surfaces of Google Messages and ChatGPT.
- Rounded screens, cards, sheets, thumbnails, and notifications.
- Blue is the primary accent; avoid the earlier green-heavy utility aesthetic.
- The large wallpaper preview should retain a realistic phone-like proportion.
- `Up Next` thumbnails are portrait, compact, rounded, and may visually fall off
  either edge while scrolling.
- The home layout should reserve `Up Next` space before sizing the main preview
  so 3-button navigation, gesture navigation, and display scaling behave alike.
- Bottom-sheet content must reserve the Android bottom safe area so rows and
  buttons never dip under gesture or 3-button navigation.
- Avoid shifting major layout elements when contextual controls appear.
- Interactive controls should acknowledge taps immediately. Selection borders,
  checkmarks, and lightweight visual state may update optimistically before
  native sync or heavier preview work completes.
- Selected-wallpaper changes should use the lightweight selected-index listener
  rather than forcing a full home-screen rebuild.
- Album filter taps keep sheet feedback local and debounce native filter sync so
  the checkmark animation is not competing with wallpaper-list refresh work.
- Crop-editor header actions should keep stable positions.
- The crop-editor title is `Adjust Wallpaper`; it stays centred in the header
  and scales down on narrow screens rather than wrapping, overlapping, or
  moving the corner actions. Reset appears as a preview overlay action only when
  there is something to reset.

### Copy Style

- Headers, named settings, named options, and button actions use Title Case.
- Supporting descriptions use natural sentence case.
- Prefer friendly user language over implementation language.
- Keep labels short where possible.
- Avoid terms such as `sequential` in visible copy; use `In Order`.
- Notifications use a consistent rounded floating style, fade out, and normally
  disappear after approximately three seconds.

## Architecture

### Flutter

- `lib/screens/home_screen.dart`
  - Main page, Settings and Albums sheets, import UI, drag/reorder/remove UI.
- `lib/screens/crop_editor_screen.dart`
  - Full-screen crop, mode, zoom, position, and Fit-colour editor.
- `lib/controllers/wakewall_controller.dart`
  - Flutter state coordinator and native-operation wrapper.
- `lib/services/native_wallpaper_bridge.dart`
  - Method-channel contract with Android.
- `lib/models/wallpaper.dart`
  - Flutter wallpaper, crop, album, order, source, and display-mode models.
- `lib/widgets/abstract_wallpaper.dart`
  - Flutter preview renderer.
- `lib/theme/wakewall_theme.dart`
  - Shared colours and Material theme.
- `lib/navigation/`
  - Small `auto_route` configuration.

### Native Android

- `MainActivity.kt`
  - Method-channel handler, Android Photos/Files pickers, backup/restore pickers,
    background work dispatch, and service update broadcasts.
- `WakeWallService.kt`
  - `WallpaperService`, screen lifecycle, shared rotation, frame preparation,
    surface drawing, and launcher scrolling.
- `WakeWallStore.kt`
  - Persistent configuration, albums, rotation state, import pipeline, image
    derivatives, crop metadata, backups, and restores.
- `WakeWallFileStore.kt`
  - Private-file ownership and cleanup.
- `WakeWallTransactionStore.kt`
  - Pending import and removal transaction tracking.
- `WakeWallBlurRenderer.kt`
  - Shared smooth CPU blur renderer used by native derived and fallback renders.

### State Ownership

The native Android store is the durable source of truth. Flutter reads native
configuration and sends user changes through the method channel.

Do not create a second independent durable Flutter database unless there is a
clear migration plan and a strong reason.

## Android Constraints

- WakeWall uses `WallpaperService`, not repeated static `WallpaperManager`
  updates.
- Runtime screen broadcasts are useful because the wallpaper engine is active;
  they are not assumed to cold-start a dormant normal app reliably.
- Lock-screen behavior can vary by OEM and device configuration.
- Android controls the final live-wallpaper setup screen.
- Launcher offset callbacks vary between launchers; scrolling should degrade
  gracefully when offsets are not supplied.

## Development Rules

- Preserve existing code patterns and keep changes scoped.
- Do not add timing guards that block rapid wake/sleep cycling.
- Do not sacrifice the screen-off fast path for UI convenience.
- Do not re-encode originals unless a compatibility fallback requires it.
- Do not add permanent one-time migration code for a tiny tester group without
  discussing whether manual regeneration is preferable.
- Do not support old backup versions unless explicitly requested.
- Keep storage cleanup behavior in mind whenever adding a new file derivative.
- When adding a new cached suffix, ensure deletion and orphan cleanup know it.
- Keep Flutter and native display-mode rendering consistent.
- Prefer automatic housekeeping over a user-facing `Clean Storage` button.
- Avoid large refactors or new abstractions unless they remove real complexity.
- Add simple one-line comments only when behavior is not obvious.
- Use `auto_route` if additional routing genuinely becomes necessary.

## Verification

Run from the Flutter project root:

```powershell
flutter analyze
flutter test
```

Run native checks when Kotlin or Android behavior changes:

```powershell
cd android
.\gradlew.bat :app:compileDebugKotlin
.\gradlew.bat :app:lintDebug
```

After completed development work, start a release APK build from the Flutter
project root:

```powershell
flutter build apk --release
```

The release build is currently signed with the debug key for personal testing.
A permanent release signing configuration is required before distribution.

## High-Risk Regression Checklist

Test these behaviors on a physical Android phone after relevant changes:

- Rapidly turn the screen off and on repeatedly.
- Confirm exactly one rotation per screen-off.
- Confirm the new wallpaper is already visible on wake.
- Manually select a wallpaper, then screen off/on; ensure it advances once and
  does not revert.
- Test both Shuffle and In Order.
- Test one wallpaper and multiple wallpapers.
- Test active album filters and wallpapers shared between albums.
- Test Fill, Fit, and Blur on home and lock screens.
- Test wallpaper scrolling with Fill, Fit, and Blur.
- Test large and unusual provider-backed photos.
- Force-stop during a large import, reopen, and confirm storage cleanup.
- Remove a large image, close WakeWall during Undo, and confirm final cleanup.
- Create and restore a backup.

## Deliberately Deferred or Optional Ideas

These are ideas, not committed requirements:

- Duplicate-image detection during import.
- `Save & Next` while cropping a newly imported batch.
- Automatically keep the active wallpaper visible in `Up Next`.
- Subtle haptic feedback for lift, reorder, delete target, and crop save.
- Import summary after large batches.
- Better empty-album import action.
- Dated default backup filenames.
- Startup scaling work if very large collections become a measured problem.

Do not implement deferred ideas solely because they appear here. Re-evaluate
their value, complexity, and effect on the minimal interface first.

## Source of Truth Priority

When documentation and implementation disagree:

1. Confirm the current behavior in code and tests.
2. Preserve explicit product principles and user decisions in this document.
3. Fix either the implementation or this document so they agree.
4. Record new durable decisions here after completing the change.
