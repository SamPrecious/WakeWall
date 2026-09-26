import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/wakewall_controller.dart';
import '../models/wallpaper.dart';
import '../navigation/app_router.dart';
import '../services/native_wallpaper_bridge.dart';
import '../theme/wakewall_theme.dart';
import '../widgets/abstract_wallpaper.dart';
import '../widgets/privacy_policy_action.dart';
import '../widgets/wakewall_notice.dart';

const _wallpaperStripHeaderHeight = 34.0;
const _tabletLayoutBreakpoint = 600.0;
const _tabletHomeMaxWidth = 900.0;
const _tabletSheetMaxWidth = 680.0;

void _wakeWallTapHaptic() {
  HapticFeedback.selectionClick();
}

void _wakeWallCommitHaptic() {
  HapticFeedback.mediumImpact();
}

// Picks a title colour that stays readable across dark, light, and midnight themes.
Color _wakeWallProminentTextColor(BuildContext context) {
  final colors = context.wakeWallColors;
  if (colors.isMidnight) return colors.tealStrong;
  if (Theme.of(context).brightness == Brightness.dark) return Colors.white;
  return colors.onSurface;
}

// Uses the physical display when possible so previews match the actual phone shape.
double _wakeWallPhoneRatio(BuildContext context) {
  final physicalSize = View.of(context).physicalSize;
  final displayWidth = math.min(physicalSize.width, physicalSize.height);
  final displayHeight = math.max(physicalSize.width, physicalSize.height);
  if (displayWidth > 0 && displayHeight > 0) {
    return (displayWidth / displayHeight).clamp(.44, .62).toDouble();
  }
  final screen = MediaQuery.sizeOf(context);
  return (screen.width / screen.height).clamp(.44, .62).toDouble();
}

@RoutePage()
// The main WakeWall screen: preview, controls, albums, settings, and import flow.
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final WakeWallController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

// Holds temporary UI state that should not live in the native wallpaper store.
class _HomeScreenState extends State<HomeScreen> {
  static const importOverlayDelay = Duration(milliseconds: 350);
  static const previewWarmupDelay = Duration(milliseconds: 90);

  bool draggingWallpaper = false;
  bool importingImages = false;
  ImportProgress? importProgress;
  final ValueNotifier<int?> optimisticPreviewIndex = ValueNotifier(null);
  Timer? previewWarmupTimer;
  int previewWarmupSerial = 0;
  bool previewWarmupRunning = false;

  WakeWallController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_schedulePreviewWarmup);
    controller.selectedIndexListenable.addListener(_schedulePreviewWarmup);
    _schedulePreviewWarmup();
  }

  @override
  void dispose() {
    controller.removeListener(_schedulePreviewWarmup);
    controller.selectedIndexListenable.removeListener(_schedulePreviewWarmup);
    previewWarmupTimer?.cancel();
    optimisticPreviewIndex.dispose();
    super.dispose();
  }

  // Warms only nearby previews after interaction settles so stale decodes cannot pile up.
  void _schedulePreviewWarmup() {
    previewWarmupTimer?.cancel();
    final serial = ++previewWarmupSerial;
    previewWarmupTimer = Timer(previewWarmupDelay, () async {
      if (previewWarmupRunning) return;
      previewWarmupRunning = true;
      try {
        // endOfFrame schedules a frame even when the UI has settled and is idle.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || serial != previewWarmupSerial) return;
        final wallpapers = controller.wallpapers;
        if (wallpapers.length < 2) return;
        final selectedIndex = controller.selectedIndex
            .clamp(0, wallpapers.length - 1)
            .toInt();
        final neighborIndexes = <int>{
          (selectedIndex + 1) % wallpapers.length,
          (selectedIndex + 2) % wallpapers.length,
          (selectedIndex - 1) % wallpapers.length,
        };
        for (final index in neighborIndexes) {
          if (!mounted || serial != previewWarmupSerial) return;
          final bytes = wallpapers[index].mainPreview;
          if (bytes == null) continue;
          try {
            await precacheImage(MemoryImage(bytes), context);
          } catch (_) {
            // A damaged cache can still use the normal image error path.
          }
        }
      } finally {
        previewWarmupRunning = false;
        if (mounted && serial != previewWarmupSerial) _schedulePreviewWarmup();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          body: Stack(
            children: [
              SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final bottomInset = MediaQuery.viewPaddingOf(
                      context,
                    ).bottom;
                    final landscape =
                        constraints.maxWidth > constraints.maxHeight;
                    final tablet =
                        constraints.maxWidth >= _tabletLayoutBreakpoint;
                    final hasWallpaperLayout = controller.hasStoredWallpapers;
                    final horizontalPadding = tablet
                        ? constraints.maxWidth < 720
                              ? 32.0
                              : 40.0
                        : constraints.maxWidth < 420
                        ? 20.0
                        : 28.0;
                    final headerHeight = tablet
                        ? landscape
                              ? 72.0
                              : (constraints.maxWidth * .10)
                                    .clamp(68.0, 82.0)
                                    .toDouble()
                        : 60.0;
                    final stripHeaderHeight = tablet
                        ? landscape
                              ? 38.0
                              : 40.0
                        : _wallpaperStripHeaderHeight;
                    final bottomGap = bottomInset > 24 ? 10.0 : 18.0;
                    final usableHeight =
                        constraints.maxHeight - headerHeight - bottomGap;
                    final minimumPreviewHeight = hasWallpaperLayout
                        ? 300.0
                        : 340.0;
                    // Size the thumbnail row first so the main preview gets the remaining space.
                    final targetTileHeight = tablet
                        ? landscape
                              ? 112.0
                              : (constraints.maxWidth * .20)
                                    .clamp(120.0, 150.0)
                                    .toDouble()
                        : (usableHeight * .1356).clamp(96.6, 107.6).toDouble();
                    final targetCollectionHeight =
                        stripHeaderHeight + targetTileHeight;
                    final maximumCollectionHeight = math.max(
                      112.0,
                      usableHeight - minimumPreviewHeight,
                    );
                    final collectionHeight = hasWallpaperLayout
                        ? targetCollectionHeight
                              .clamp(112.0, maximumCollectionHeight)
                              .toDouble()
                        : 0.0;
                    // Reserve the collection first so navigation bars cannot squash it.
                    final previewMinimum = hasWallpaperLayout
                        ? tablet
                              ? landscape
                                    ? 360.0
                                    : 420.0
                              : landscape
                              ? 370.0
                              : 260.0
                        : tablet
                        ? 420.0
                        : 320.0;
                    final phoneRatio = _wakeWallPhoneRatio(context);
                    final tabletPreviewMaxWidth = math.min(
                      constraints.maxWidth * .72,
                      620.0,
                    );
                    final availablePreviewHeight =
                        usableHeight - collectionHeight;
                    final previewHeight = tablet
                        ? math
                              .min(
                                availablePreviewHeight,
                                tabletPreviewMaxWidth / phoneRatio,
                              )
                              .clamp(previewMinimum, double.infinity)
                              .toDouble()
                        : availablePreviewHeight
                              .clamp(previewMinimum, 680.0)
                              .toDouble();
                    final contentHeight =
                        headerHeight +
                        previewHeight +
                        collectionHeight +
                        bottomGap;
                    final needsVerticalScroll =
                        contentHeight > constraints.maxHeight;
                    final contentWidth = tablet
                        ? math.min(constraints.maxWidth, _tabletHomeMaxWidth)
                        : constraints.maxWidth;
                    final stripHorizontalPadding = tablet
                        ? (constraints.maxWidth - contentWidth) / 2 +
                              horizontalPadding
                        : horizontalPadding;
                    final tabletTitleSize = tablet
                        ? (constraints.maxWidth * .057)
                              .clamp(42.0, 48.0)
                              .toDouble()
                        : null;

                    final contentBody = Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        mainAxisSize: tablet || needsVerticalScroll
                            ? MainAxisSize.min
                            : MainAxisSize.max,
                        children: [
                          SizedBox(
                            height: headerHeight,
                            child: _Header(
                              onAlbums: () => _showAlbums(context),
                              onSettings: () => _showSettings(context),
                              titleFontSize: tabletTitleSize,
                              actionIconSize: tablet ? 26 : 22,
                            ),
                          ),
                          SizedBox(
                            height: previewHeight,
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: RepaintBoundary(
                                child: _Preview(
                                  controller: controller,
                                  optimisticPreviewIndex:
                                      optimisticPreviewIndex,
                                  maximumHeight: previewHeight,
                                  maximumWidth: tablet
                                      ? tabletPreviewMaxWidth
                                      : null,
                                  draggingWallpaper: draggingWallpaper,
                                  onRemoveWallpaper: _removeWallpaper,
                                  onAdd: _addImages,
                                  onAlbums: _showCurrentWallpaperAlbums,
                                  onResume: () {
                                    _wakeWallTapHaptic();
                                    unawaited(controller.setPaused(false));
                                  },
                                  onCrop: () {
                                    _wakeWallTapHaptic();
                                    unawaited(
                                      context.router.push(
                                        CropEditorRoute(
                                          controller: controller,
                                          wallpaperIndex:
                                              controller.selectedIndex,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                          if (hasWallpaperLayout)
                            SizedBox(
                              height: collectionHeight,
                              child: RepaintBoundary(
                                child: controller.hasWallpapers
                                    ? _WallpaperStrip(
                                        controller: controller,
                                        horizontalPadding:
                                            stripHorizontalPadding,
                                        headerHeight: stripHeaderHeight,
                                        labelFontSize: tablet ? 18 : 15.5,
                                        onAdd: _addImages,
                                        onPreviewIndexChanged: (index) =>
                                            optimisticPreviewIndex.value =
                                                index,
                                        onDragChanged: (dragging) {
                                          if (draggingWallpaper == dragging) {
                                            return;
                                          }
                                          setState(
                                            () => draggingWallpaper = dragging,
                                          );
                                        },
                                      )
                                    : _LoadingWallpaperStrip(
                                        headerHeight: stripHeaderHeight,
                                        labelFontSize: tablet ? 18 : 15.5,
                                      ),
                              ),
                            ),
                          SizedBox(height: bottomGap),
                        ],
                      ),
                    );
                    if (tablet && !needsVerticalScroll) {
                      return Align(
                        alignment: Alignment.center,
                        child: SizedBox(
                          key: const ValueKey('tablet-home-content'),
                          width: contentWidth,
                          height: contentHeight,
                          child: contentBody,
                        ),
                      );
                    }
                    if (!needsVerticalScroll) return contentBody;
                    // Landscape and unusually short windows scroll instead of overflowing.
                    return SingleChildScrollView(
                      key: const ValueKey('short-screen-home-scroll'),
                      physics: const ClampingScrollPhysics(),
                      child: tablet
                          ? Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(
                                width: contentWidth,
                                height: contentHeight,
                                child: contentBody,
                              ),
                            )
                          : contentBody,
                    );
                  },
                ),
              ),
              if (importingImages)
                _OperationOverlay(
                  overlayKey: const ValueKey('import-loading-overlay'),
                  title: 'Adding Wallpapers',
                  description:
                      importProgress == null || importProgress!.total < 1
                      ? 'Preparing your photos...'
                      : '${importProgress!.completed} of ${importProgress!.total} processed',
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSettings(BuildContext context) {
    // Settings can be opened after Android changes state, so refresh first.
    _wakeWallTapHaptic();
    unawaited(controller.refreshState());
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: _tabletBottomSheetConstraints(context),
      builder: (_) => _SettingsSheet(controller: controller),
    );
  }

  Future<void> _showAlbums(BuildContext context) {
    // Album filtering is a lightweight sheet over the current home view.
    _wakeWallTapHaptic();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: _tabletBottomSheetConstraints(context),
      builder: (_) => _AlbumsSheet(controller: controller),
    );
  }

  Future<void> _showCurrentWallpaperAlbums() async {
    // The current wallpaper uses the same album picker as newly imported wallpapers.
    final wallpaper = controller.selectedWallpaper;
    if (wallpaper == null) return;
    _wakeWallTapHaptic();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: _tabletBottomSheetConstraints(context),
      builder: (_) => _AssignAlbumsSheet(
        controller: controller,
        wallpapers: [wallpaper],
        isImport: false,
      ),
    );
  }

  Future<void> _removeWallpaper(int index) async {
    if (draggingWallpaper) setState(() => draggingWallpaper = false);
    final removal = await controller.removeAt(index);
    if (removal == null || !mounted) return;
    // The snackbar is the undo window; closing it commits the native deletion.
    final notice = showWakeWallNotice(
      context,
      message: 'Wallpaper removed',
      icon: Icons.delete_outline_rounded,
      actionLabel: 'Undo',
      onAction: () {},
    );
    final reason = await notice.closed;
    if (reason == SnackBarClosedReason.action) {
      await controller.undoRemoval(removal);
    } else {
      await controller.finalizeRemoval(removal);
    }
  }

  Future<void> _addImages() async {
    _wakeWallTapHaptic();
    final wasEmpty = !controller.hasWallpapers;
    final existingIds = controller.wallpapers
        .map((wallpaper) => wallpaper.id)
        .toSet();
    var source = controller.photoSource;
    // The source sheet only appears while the user has not picked a default.
    if (source == PhotoSource.askEveryTime) {
      final choice = await showModalBottomSheet<_AddSourceChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        constraints: _tabletBottomSheetConstraints(context),
        builder: (_) => const _AddSourceSheet(),
      );
      if (choice == null || !mounted) return;
      source = choice.source;
      if (choice.remember) await controller.setPhotoSource(source);
    }

    Timer? overlayTimer;
    void updateImportProgress(ImportProgress progress) {
      if (mounted) setState(() => importProgress = progress);
      // Fast imports should not flash a loading overlay for a single frame.
      overlayTimer ??= Timer(importOverlayDelay, () {
        if (mounted) setState(() => importingImages = true);
      });
    }

    try {
      if (source == PhotoSource.files) {
        await controller.addImagesFromFiles(
          onImportProgress: updateImportProgress,
        );
      } else {
        await controller.addImages(onImportProgress: updateImportProgress);
      }
    } finally {
      overlayTimer?.cancel();
      if (mounted) {
        setState(() {
          importingImages = false;
          importProgress = null;
        });
      }
    }

    if (!mounted) return;
    if (controller.lastNativeError != null) {
      showWakeWallNotice(
        context,
        message: controller.lastNativeError!,
        icon: Icons.error_outline_rounded,
        iconColor: context.wakeWallColors.danger,
        actionLabel: 'Dismiss',
        onAction: () {},
      );
    }
    final added = controller.wallpapers
        .where((wallpaper) => !existingIds.contains(wallpaper.id))
        .toList();
    if (added.isNotEmpty && mounted) {
      Set<String> assignedAlbumIds = controller.defaultImportAlbumIds;
      // Imported wallpapers get album choices after Android has safely stored them.
      if (controller.askAlbumsAfterImport) {
        assignedAlbumIds =
            await showModalBottomSheet<Set<String>>(
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              constraints: _tabletBottomSheetConstraints(context),
              isDismissible: false,
              enableDrag: false,
              builder: (_) => _AssignAlbumsSheet(
                controller: controller,
                wallpapers: added,
                isImport: true,
              ),
            ) ??
            {};
      } else {
        for (final wallpaper in added) {
          await controller.updateWallpaperAlbums(
            wallpaper,
            controller.defaultImportAlbumIds,
          );
        }
      }
      await controller.revealImportedAlbumSelection(assignedAlbumIds);
    }
    if (mounted && wasEmpty && controller.hasWallpapers) {
      await _offerWallpaperSetupIfNeeded(context, controller);
    }
  }
}

// Offers Android's setup screen once the user has wallpapers ready to use.
Future<void> _offerWallpaperSetupIfNeeded(
  BuildContext context,
  WakeWallController controller,
) async {
  if (!await controller.claimWallpaperSetupOffer() || !context.mounted) return;
  final colors = context.wakeWallColors;
  final openSetup = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.surface,
      icon: const Icon(Icons.wallpaper_rounded),
      title: const Text('Set Up WakeWall?'),
      content: const Text(
        'Your wallpapers are ready. Set WakeWall as your live wallpaper to rotate them automatically.',
      ),
      actions: [
        TextButton(
          onPressed: () {
            _wakeWallTapHaptic();
            Navigator.pop(context, false);
          },
          child: const Text('Not Now'),
        ),
        FilledButton(
          onPressed: () {
            _wakeWallCommitHaptic();
            Navigator.pop(context, true);
          },
          child: const Text('Set Wallpaper'),
        ),
      ],
    ),
  );
  if (openSetup == true && context.mounted) {
    await controller.openWallpaperPicker();
  }
}

class _OperationOverlay extends StatelessWidget {
  const _OperationOverlay({
    required this.overlayKey,
    required this.title,
    required this.description,
  });

  final Key overlayKey;
  final String title;
  final String description;

  @override
  // Blocks the screen during longer native work so the app never looks frozen.
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Positioned.fill(
      key: overlayKey,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: '$title. $description',
        child: ExcludeSemantics(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: .58),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 280),
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: colors.outline.withValues(alpha: .45),
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black54,
                      blurRadius: 28,
                      offset: Offset(0, 12),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 38,
                      height: 38,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: colors.tealStrong,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      textAlign: TextAlign.center,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Top row containing the app wordmark and the two global navigation buttons.
class _Header extends StatelessWidget {
  const _Header({
    required this.onAlbums,
    required this.onSettings,
    required this.actionIconSize,
    this.titleFontSize,
  });

  final VoidCallback onAlbums;
  final VoidCallback onSettings;
  final double actionIconSize;
  final double? titleFontSize;

  @override
  Widget build(BuildContext context) {
    final titleColor = _wakeWallProminentTextColor(context);
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          left: 58,
          right: 58,
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'WakeWall',
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  color: titleColor,
                  fontSize: titleFontSize,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: _HeaderActionButton(
            icon: Icons.settings_outlined,
            tooltip: 'Settings',
            onTap: onSettings,
            iconSize: actionIconSize,
          ),
        ),
        Positioned(
          left: 0,
          child: _HeaderActionButton(
            icon: Icons.photo_library_outlined,
            tooltip: 'Albums',
            onTap: onAlbums,
            iconSize: actionIconSize,
          ),
        ),
      ],
    );
  }
}

// Small rounded icon button used by the home header.
class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    required this.iconSize,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final iconColor = colors.isMidnight ? colors.tealStrong : colors.teal;
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(13),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(13),
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  border: Border.all(color: Colors.transparent),
                ),
                child: Icon(icon, color: iconColor, size: iconSize),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Main phone-shaped preview card and its overlay actions.
class _Preview extends StatelessWidget {
  const _Preview({
    required this.controller,
    required this.optimisticPreviewIndex,
    required this.maximumHeight,
    this.maximumWidth,
    required this.draggingWallpaper,
    required this.onRemoveWallpaper,
    required this.onAdd,
    required this.onAlbums,
    required this.onResume,
    required this.onCrop,
  });

  final WakeWallController controller;
  final ValueListenable<int?> optimisticPreviewIndex;
  final double maximumHeight;
  final double? maximumWidth;
  final bool draggingWallpaper;
  final Future<void> Function(int) onRemoveWallpaper;
  final VoidCallback onAdd;
  final VoidCallback onAlbums;
  final VoidCallback onResume;
  final VoidCallback onCrop;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final phoneRatio = _wakeWallPhoneRatio(context);
    final availableWidth =
        maximumWidth ?? MediaQuery.sizeOf(context).width - 40;
    final heightFromWidth = availableWidth / phoneRatio;
    final height = heightFromWidth.clamp(0, maximumHeight).toDouble();
    final width = height * phoneRatio;
    const radius = BorderRadius.all(Radius.circular(22));

    return AnimatedContainer(
      key: const ValueKey('wakewall-main-preview'),
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: radius,
        border: Border.all(
          color: controller.hasStoredWallpapers
              ? colors.outline.withValues(alpha: .25)
              : colors.outline,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 420),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            child: controller.isLoadingInitialConfiguration
                ? const _InitialLoadingPreview(
                    key: ValueKey('initial-wallpaper-loading'),
                  )
                : controller.hasWallpapers
                ? ValueListenableBuilder<int?>(
                    key: const ValueKey('populated'),
                    valueListenable: optimisticPreviewIndex,
                    builder: (context, optimisticIndex, _) =>
                        ValueListenableBuilder<int>(
                          valueListenable: controller.selectedIndexListenable,
                          builder: (context, selectedIndex, _) {
                            final wallpapers = controller.wallpapers;
                            if (wallpapers.isEmpty) {
                              return _EmptyPreview(onAdd: onAdd);
                            }
                            final displayIndex =
                                optimisticIndex ?? selectedIndex;
                            final boundedIndex = displayIndex
                                .clamp(0, wallpapers.length - 1)
                                .toInt();
                            final wallpaper = wallpapers[boundedIndex];
                            final previewBytes =
                                wallpaper.mainPreview ?? wallpaper.preview;
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                if (previewBytes == null &&
                                    wallpaper.isUserImage)
                                  _MainPreviewPlaceholder(
                                    onRetry:
                                        controller.mainPreviewFailed(
                                          wallpaper.id,
                                        )
                                        ? () => unawaited(
                                            controller.ensureMainPreview(
                                              boundedIndex,
                                            ),
                                          )
                                        : null,
                                  )
                                else
                                  AbstractWallpaper(
                                    wallpaper: wallpaper,
                                    previewBytes: previewBytes,
                                    applyCrop: wallpaper.mainPreview == null,
                                    borderRadius: radius,
                                  ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  top: 14,
                                  child: Center(
                                    child: AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 240,
                                      ),
                                      reverseDuration: const Duration(
                                        milliseconds: 260,
                                      ),
                                      switchInCurve: Curves.easeOut,
                                      switchOutCurve: Curves.easeIn,
                                      child: controller.paused
                                          ? _PausedPreviewButton(
                                              key: const ValueKey(
                                                'paused-chip-visible',
                                              ),
                                              onTap: onResume,
                                            )
                                          : const SizedBox(
                                              key: ValueKey(
                                                'paused-chip-hidden',
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 0,
                                  right: 0,
                                  bottom: 14,
                                  child: Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _OverlayButton(
                                          icon: Icons.photo_album_outlined,
                                          tooltip: 'Add to Albums',
                                          onTap: onAlbums,
                                        ),
                                        const SizedBox(width: 8),
                                        _OverlayButton(
                                          icon: Icons.crop_rounded,
                                          tooltip: 'Adjust Crop',
                                          onTap: onCrop,
                                        ),
                                        const SizedBox(width: 8),
                                        _OverlayButton(
                                          icon: Icons.skip_next_rounded,
                                          tooltip: 'Next Wallpaper',
                                          onTap: () {
                                            _wakeWallTapHaptic();
                                            unawaited(controller.next());
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                  )
                : controller.hasStoredWallpapers
                ? _UnavailablePreview(
                    key: const ValueKey('wallpaper-load-failed'),
                    onRetry: () => unawaited(controller.initialize()),
                  )
                : _EmptyPreview(key: const ValueKey('empty'), onAdd: onAdd),
          ),
          IgnorePointer(
            ignoring: !draggingWallpaper,
            child: AnimatedOpacity(
              key: const ValueKey('wallpaper-remove-overlay'),
              duration: const Duration(milliseconds: 180),
              opacity: draggingWallpaper ? 1 : 0,
              child: ColoredBox(
                color: Colors.black.withValues(alpha: .38),
                child: Center(
                  child: DragTarget<int>(
                    onWillAcceptWithDetails: (_) => draggingWallpaper,
                    onAcceptWithDetails: (details) {
                      HapticFeedback.mediumImpact();
                      onRemoveWallpaper(details.data);
                    },
                    builder: (context, candidates, _) {
                      final removing = candidates.isNotEmpty;
                      return Semantics(
                        label: 'Remove Wallpaper',
                        hint: 'Drop the wallpaper here to remove it',
                        child: AnimatedContainer(
                          key: const ValueKey('wallpaper-remove-target'),
                          duration: const Duration(milliseconds: 180),
                          width: removing ? 96 : 82,
                          height: removing ? 96 : 82,
                          decoration: BoxDecoration(
                            color: removing
                                ? colors.danger
                                : colors.raisedSurface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.delete_outline_rounded,
                            size: removing ? 42 : 36,
                            color: removing ? colors.ink : colors.muted,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Floating pause badge that lets the user resume without entering Settings.
class _PausedPreviewButton extends StatelessWidget {
  const _PausedPreviewButton({required this.onTap, super.key});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foregroundColor = _wakeWallProminentTextColor(context);
    return Tooltip(
      message: 'Resume WakeWall',
      child: Material(
        color: const Color(0xCC25262A),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: .12)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pause_rounded, color: foregroundColor, size: 16),
                const SizedBox(width: 6),
                Text(
                  'Paused',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foregroundColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Avoids presenting a false empty library while Android reloads image previews.
class _InitialLoadingPreview extends StatefulWidget {
  const _InitialLoadingPreview({super.key});

  @override
  State<_InitialLoadingPreview> createState() => _InitialLoadingPreviewState();
}

class _InitialLoadingPreviewState extends State<_InitialLoadingPreview> {
  Timer? indicatorTimer;
  bool showIndicator = false;

  @override
  void initState() {
    super.initState();
    // Normal launches should transition straight to the wallpaper without a flash.
    indicatorTimer = Timer(const Duration(milliseconds: 280), () {
      if (mounted) setState(() => showIndicator = true);
    });
  }

  @override
  void dispose() {
    indicatorTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Center(
      child: AnimatedOpacity(
        key: const ValueKey('initial-loading-indicator'),
        duration: const Duration(milliseconds: 160),
        opacity: showIndicator ? 1 : 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: colors.tealStrong,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Loading Wallpapers',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: colors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

// Keeps tiny strip thumbnails out of the large card while its real preview is built.
class _MainPreviewPlaceholder extends StatelessWidget {
  const _MainPreviewPlaceholder({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Semantics(
      label: onRetry == null
          ? 'Preparing wallpaper preview'
          : 'Wallpaper preview unavailable',
      child: ColoredBox(
        key: ValueKey(
          onRetry == null ? 'main-preview-loading' : 'main-preview-unavailable',
        ),
        color: colors.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onRetry != null)
                Icon(Icons.broken_image_outlined, size: 28, color: colors.muted)
              else
                SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: colors.tealStrong,
                  ),
                ),
              const SizedBox(height: 12),
              Text(
                onRetry == null ? 'Preparing Wallpaper' : 'Preview Unavailable',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.muted),
              ),
              if (onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// Keeps a known library distinct from the genuine first-use empty state after an error.
class _UnavailablePreview extends StatelessWidget {
  const _UnavailablePreview({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sync_problem_rounded, color: colors.muted, size: 28),
          const SizedBox(height: 10),
          Text(
            'Wallpapers Could Not Be Loaded',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

// Empty-state preview that acts as one large add-wallpapers target.
class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Material(
      color: Colors.transparent,
      child: Semantics(
        button: true,
        label: 'Add Wallpapers',
        hint: 'Choose photos for WakeWall',
        child: InkWell(
          key: const ValueKey('empty-add-wallpapers'),
          onTap: onAdd,
          borderRadius: BorderRadius.circular(22),
          child: Center(
            child: Text(
              'Add Wallpapers',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: colors.onSurface,
                fontSize: 24,
                letterSpacing: -.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Reusable dark overlay button for actions on top of the wallpaper preview.
class _OverlayButton extends StatelessWidget {
  const _OverlayButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final iconColor = colors.isMidnight ? colors.tealStrong : Colors.white;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xCC25262A),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: iconColor, size: 21),
          ),
        ),
      ),
    );
  }
}

// Reserves the populated strip geometry while native previews are still loading.
class _LoadingWallpaperStrip extends StatelessWidget {
  const _LoadingWallpaperStrip({
    required this.headerHeight,
    required this.labelFontSize,
  });

  final double headerHeight;
  final double labelFontSize;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Opacity(
      key: const ValueKey('initial-wallpaper-strip'),
      opacity: .48,
      child: Column(
        children: [
          SizedBox(
            height: headerHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Up Next',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.muted,
                  fontSize: labelFontSize,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final fullTileHeight = constraints.maxHeight;
                final tileHeight = fullTileHeight * .85;
                final tileWidth = fullTileHeight * _wakeWallPhoneRatio(context);
                return Align(
                  alignment: Alignment.topLeft,
                  child: Row(
                    children: [
                      for (var index = 0; index < 5; index++) ...[
                        if (index > 0) const SizedBox(width: 5.6),
                        Container(
                          width: tileWidth,
                          height: tileHeight,
                          decoration: BoxDecoration(
                            color: colors.raisedSurface,
                            borderRadius: BorderRadius.circular(10.5),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// Horizontal queue of wallpapers plus the Add action.
class _WallpaperStrip extends StatefulWidget {
  const _WallpaperStrip({
    required this.controller,
    required this.horizontalPadding,
    required this.headerHeight,
    required this.labelFontSize,
    required this.onAdd,
    required this.onPreviewIndexChanged,
    required this.onDragChanged,
  });

  final WakeWallController controller;
  final double horizontalPadding;
  final double headerHeight;
  final double labelFontSize;
  final VoidCallback onAdd;
  final ValueChanged<int?> onPreviewIndexChanged;
  final ValueChanged<bool> onDragChanged;

  @override
  State<_WallpaperStrip> createState() => _WallpaperStripState();
}

class _WallpaperStripState extends State<_WallpaperStrip> {
  final ScrollController scrollController = ScrollController();
  int? optimisticSelectedIndex;
  int previousWallpaperCount = 0;

  WakeWallController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    previousWallpaperCount = controller.wallpapers.length;
    controller.addListener(handleWallpaperCollectionChanged);
  }

  @override
  void dispose() {
    controller.removeListener(handleWallpaperCollectionChanged);
    scrollController.dispose();
    super.dispose();
  }

  void handleWallpaperCollectionChanged() {
    final count = controller.wallpapers.length;
    if (count <= previousWallpaperCount) {
      previousWallpaperCount = count;
      return;
    }
    previousWallpaperCount = count;
    // New imports append to the end, so the strip follows them after layout settles.
    scrollToEndAfterLayout();
  }

  // Scrolls the collection when a lifted wallpaper nears either screen edge.
  void autoScroll(DragUpdateDetails details) {
    if (!scrollController.hasClients) return;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final direction = details.globalPosition.dx < 72
        ? -1
        : details.globalPosition.dx > screenWidth - 72
        ? 1
        : 0;
    if (direction == 0) return;
    final target = (scrollController.offset + direction * 72).clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    scrollController.jumpTo(target);
  }

  void previewSelection(int index) {
    // Both the border and large cached thumbnail move before Android is called.
    if (index < 0 || index >= controller.wallpapers.length) return;
    unawaited(controller.ensureMainPreview(index));
    if (optimisticSelectedIndex != index) {
      setState(() => optimisticSelectedIndex = index);
    }
    widget.onPreviewIndexChanged(index);
  }

  void cancelPreviewSelection() {
    widget.onPreviewIndexChanged(null);
    if (optimisticSelectedIndex != null) {
      setState(() => optimisticSelectedIndex = null);
    }
  }

  void commitSelection(int index) {
    if (index < 0 || index >= controller.wallpapers.length) return;
    final selection = controller.select(index);
    widget.onPreviewIndexChanged(null);
    if (optimisticSelectedIndex != null) {
      setState(() => optimisticSelectedIndex = null);
    }
    unawaited(selection);
  }

  void scrollToEndAfterLayout() {
    // Wait two frames so newly added thumbnail sizes are known before scrolling.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scrollController.hasClients) return;
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final headingColor = _wakeWallProminentTextColor(context);
    final stripLabelStyle = Theme.of(context).textTheme.labelLarge?.copyWith(
      fontSize: widget.labelFontSize,
      letterSpacing: 1.2,
    );
    return ValueListenableBuilder<int>(
      valueListenable: controller.selectedIndexListenable,
      builder: (context, selectedIndex, _) {
        final wallpapers = controller.wallpapers;
        return Column(
          children: [
            SizedBox(
              height: widget.headerHeight,
              child: Row(
                children: [
                  Text(
                    'Up Next',
                    style: stripLabelStyle?.copyWith(color: headingColor),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: widget.onAdd,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.add_rounded, size: 19),
                    label: Text(
                      'Add',
                      style: stripLabelStyle?.copyWith(
                        color: colors.tealStrong,
                        letterSpacing: .2,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.tealStrong,
                      minimumSize: Size.zero,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: OverflowBox(
                alignment: Alignment.center,
                maxWidth: MediaQuery.sizeOf(context).width,
                child: SizedBox(
                  width: MediaQuery.sizeOf(context).width,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final phoneRatio = _wakeWallPhoneRatio(context);
                      final fullTileHeight = math.min(
                        constraints.maxHeight,
                        math.max(89.7, constraints.maxHeight),
                      );
                      final tileWidth = fullTileHeight * phoneRatio;
                      final tileHeight = fullTileHeight * .85;
                      final activeIndex =
                          optimisticSelectedIndex ?? selectedIndex;

                      return ListView.separated(
                        key: const ValueKey('wallpaper-strip-scroll'),
                        controller: scrollController,
                        padding: EdgeInsets.symmetric(
                          horizontal: widget.horizontalPadding,
                        ),
                        scrollDirection: Axis.horizontal,
                        itemCount: wallpapers.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 5.6),
                        itemBuilder: (context, index) {
                          final selected = index == activeIndex;
                          final tile = _WallpaperTile(
                            wallpaper: wallpapers[index],
                            selected: selected,
                            width: tileWidth,
                            height: tileHeight,
                          );
                          return DragTarget<int>(
                            onWillAcceptWithDetails: (details) =>
                                details.data != index,
                            onAcceptWithDetails: (details) {
                              HapticFeedback.selectionClick();
                              controller.move(details.data, index);
                            },
                            builder: (context, candidates, _) {
                              final accepting = candidates.isNotEmpty;
                              return AnimatedPadding(
                                duration: const Duration(milliseconds: 160),
                                padding: EdgeInsets.only(
                                  left: accepting ? 14 : 0,
                                ),
                                child: LongPressDraggable<int>(
                                  key: ValueKey('wallpaper-drag-$index'),
                                  data: index,
                                  rootOverlay: true,
                                  dragAnchorStrategy: pointerDragAnchorStrategy,
                                  onDragStarted: () {
                                    HapticFeedback.mediumImpact();
                                    cancelPreviewSelection();
                                    widget.onDragChanged(true);
                                  },
                                  onDragUpdate: autoScroll,
                                  onDragEnd: (_) => widget.onDragChanged(false),
                                  feedback: Transform.scale(
                                    scale: 1.08,
                                    child: Material(
                                      color: Colors.transparent,
                                      elevation: 14,
                                      shadowColor: Colors.black,
                                      borderRadius: BorderRadius.circular(13),
                                      child: tile,
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: .18,
                                    child: tile,
                                  ),
                                  child: Semantics(
                                    button: true,
                                    selected: selected,
                                    label:
                                        '${wallpapers[index].name}, wallpaper ${index + 1} of ${wallpapers.length}',
                                    hint:
                                        'Double tap to preview. Long press to reorder or remove.',
                                    child: Listener(
                                      onPointerDown: (_) {
                                        previewSelection(index);
                                      },
                                      // Fast scrolls can reject a tap before onTapCancel is sent.
                                      onPointerUp: (_) =>
                                          cancelPreviewSelection(),
                                      onPointerCancel: (_) =>
                                          cancelPreviewSelection(),
                                      child: GestureDetector(
                                        onTapCancel: cancelPreviewSelection,
                                        onTap: () => commitSelection(index),
                                        child: ExcludeSemantics(child: tile),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// Compact wallpaper preview used by the horizontal queue.
class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.wallpaper,
    required this.selected,
    required this.width,
    required this.height,
  });

  final Wallpaper wallpaper;
  final bool selected;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Container(
      key: ValueKey('wallpaper-thumbnail-${wallpaper.id}'),
      width: width,
      height: height,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: selected
            ? colors.tealStrong.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected ? colors.tealStrong : Colors.transparent,
          width: 1,
        ),
      ),
      child: AbstractWallpaper(
        wallpaper: wallpaper,
        applyCrop: wallpaper.thumbnail == null,
        borderRadius: BorderRadius.circular(10.5),
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

// Bottom sheet for choosing which albums are visible on the home page.
class _AlbumsSheet extends StatefulWidget {
  const _AlbumsSheet({required this.controller});

  final WakeWallController controller;

  @override
  State<_AlbumsSheet> createState() => _AlbumsSheetState();
}

class _AlbumsSheetState extends State<_AlbumsSheet> {
  Set<String>? optimisticActiveAlbumIds;
  Timer? albumApplyTimer;
  Set<String>? pendingActiveAlbumIds;

  WakeWallController get controller => widget.controller;
  Set<String> get visibleActiveAlbumIds =>
      optimisticActiveAlbumIds ?? controller.activeAlbumIds;

  @override
  void dispose() {
    albumApplyTimer?.cancel();
    final pending = pendingActiveAlbumIds;
    pendingActiveAlbumIds = null;
    if (pending != null &&
        !_sameStringSet(controller.activeAlbumIds, pending)) {
      // If the user closes mid-debounce, still apply their last visible choice.
      unawaited(controller.setActiveAlbums(pending));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final titleColor = _wakeWallProminentTextColor(context);
    return SingleChildScrollView(
      padding: _bottomSheetPadding(context, left: 20, top: 6, right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Albums',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: titleColor),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  _wakeWallTapHaptic();
                  unawaited(_createAlbum());
                },
                tooltip: 'Create Album',
                icon: const Icon(Icons.add_rounded),
              ),
              IconButton(
                onPressed: () {
                  _wakeWallTapHaptic();
                  Navigator.pop(context);
                },
                tooltip: 'Close Albums',
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _AlbumFilterTile(
            title: 'All Wallpapers',
            icon: Icons.photo_library_outlined,
            selected: visibleActiveAlbumIds.isEmpty,
            onTap: () => _setActiveAlbums({}),
          ),
          for (final album in controller.albums)
            _AlbumFilterTile(
              title: album.name,
              icon: Icons.photo_album_outlined,
              selected: visibleActiveAlbumIds.contains(album.id),
              onTap: () => _toggle(album.id),
              onLongPress: () => _manageAlbum(album),
            ),
          if (controller.albums.isEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Create an album to group wallpapers without making extra copies.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          ],
        ],
      ),
    );
  }

  void _toggle(String id) {
    final updated = {...visibleActiveAlbumIds};
    updated.contains(id) ? updated.remove(id) : updated.add(id);
    _setActiveAlbums(updated);
  }

  void _setActiveAlbums(Set<String> ids) {
    setState(() => optimisticActiveAlbumIds = {...ids});
    pendingActiveAlbumIds = {...ids};
    albumApplyTimer?.cancel();
    // Keep the sheet responsive and apply the real native filter after the tap ripple.
    albumApplyTimer = Timer(const Duration(milliseconds: 220), () {
      final pending = pendingActiveAlbumIds;
      pendingActiveAlbumIds = null;
      if (pending == null ||
          _sameStringSet(controller.activeAlbumIds, pending)) {
        return;
      }
      unawaited(controller.setActiveAlbums(pending));
    });
  }

  Future<void> _createAlbum() async {
    final name = await _albumNameDialog(context, title: 'New Album');
    if (name != null) {
      await controller.createAlbum(name);
      if (mounted) setState(() {});
    }
  }

  Future<void> _manageAlbum(WallpaperAlbum album) async {
    // Long-press actions keep album management out of the main sheet.
    final action = await showModalBottomSheet<String>(
      context: context,
      constraints: _tabletBottomSheetConstraints(context),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () {
                _wakeWallTapHaptic();
                Navigator.pop(context, 'rename');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Delete Album'),
              onTap: () {
                _wakeWallTapHaptic();
                Navigator.pop(context, 'delete');
              },
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'rename') {
      final name = await _albumNameDialog(
        context,
        title: 'Rename Album',
        initialValue: album.name,
      );
      if (name != null) await controller.renameAlbum(album.id, name);
      if (mounted) setState(() {});
    } else if (action == 'delete') {
      final deletePhotos = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Delete ${album.name}?'),
          content: const Text(
            'Photos only in this album can be permanently deleted. '
            'Photos shared with another album will always be kept.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                _wakeWallTapHaptic();
                Navigator.pop(context, false);
              },
              child: const Text('Album Only'),
            ),
            FilledButton(
              onPressed: () {
                _wakeWallCommitHaptic();
                Navigator.pop(context, true);
              },
              child: const Text('Album & Photos'),
            ),
          ],
        ),
      );
      if (deletePhotos != null) {
        await controller.deleteAlbum(
          album.id,
          deleteExclusiveWallpapers: deletePhotos,
        );
        if (mounted) setState(() {});
      }
    }
  }
}

// Bottom sheet for assigning one or more wallpapers to albums.
class _AssignAlbumsSheet extends StatefulWidget {
  const _AssignAlbumsSheet({
    required this.controller,
    required this.wallpapers,
    required this.isImport,
  });
  final WakeWallController controller;
  final List<Wallpaper> wallpapers;
  final bool isImport;

  @override
  State<_AssignAlbumsSheet> createState() => _AssignAlbumsSheetState();
}

class _AssignAlbumsSheetState extends State<_AssignAlbumsSheet> {
  late Set<String> selected = !widget.isImport && widget.wallpapers.length == 1
      ? {...widget.wallpapers.first.albumIds}
      : {};
  bool remember = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final titleColor = _wakeWallProminentTextColor(context);
    return SingleChildScrollView(
      padding: _bottomSheetPadding(context, left: 20, top: 6, right: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Albums',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: titleColor),
              ),
              const Spacer(),
              IconButton(
                onPressed: () {
                  _wakeWallTapHaptic();
                  unawaited(_createAlbum());
                },
                tooltip: 'Create Album',
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (widget.isImport)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('No Album', style: TextStyle(color: titleColor)),
              value: selected.isEmpty,
              onChanged: (_) {
                _wakeWallTapHaptic();
                setState(selected.clear);
              },
            ),
          for (final album in widget.controller.albums)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(album.name, style: TextStyle(color: titleColor)),
              value: selected.contains(album.id),
              onChanged: (_) {
                _wakeWallTapHaptic();
                setState(() {
                  selected.contains(album.id)
                      ? selected.remove(album.id)
                      : selected.add(album.id);
                });
              },
            ),
          if (widget.controller.albums.isEmpty)
            Text(
              widget.isImport
                  ? 'No albums yet. These wallpapers will remain in All Wallpapers.'
                  : 'No albums yet.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
          if (widget.isImport) ...[
            const SizedBox(height: 10),
            _RememberChoiceTile(
              label: "Don't Ask Me Again",
              description: 'You can change this later in Settings',
              value: remember,
              onChanged: (value) => setState(() => remember = value),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(onPressed: _save, child: const Text('Done')),
        ],
      ),
    );
  }

  Future<void> _save() async {
    _wakeWallCommitHaptic();
    // The same selected album set is applied to every wallpaper in this sheet.
    for (final wallpaper in widget.wallpapers) {
      await widget.controller.updateWallpaperAlbums(wallpaper, selected);
    }
    if (widget.isImport && remember) {
      await widget.controller.setImportAlbumPreference(false, selected);
    }
    if (mounted) Navigator.pop(context, selected);
  }

  Future<void> _createAlbum() async {
    // New albums are immediately selected for this assignment flow.
    final existing = widget.controller.albums.map((album) => album.id).toSet();
    final name = await _albumNameDialog(context, title: 'New Album');
    if (name == null) return;
    await widget.controller.createAlbum(name);
    WallpaperAlbum? created;
    for (final album in widget.controller.albums) {
      if (!existing.contains(album.id)) {
        created = album;
        break;
      }
    }
    final createdId = created?.id;
    if (createdId != null && mounted) setState(() => selected.add(createdId));
  }
}

// Album row used by both All Wallpapers and user-created albums.
class _AlbumFilterTile extends StatelessWidget {
  const _AlbumFilterTile({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });
  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final titleColor = _wakeWallProminentTextColor(context);
    final titleStyle = Theme.of(context).textTheme.titleMedium;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? colors.tealStrong.withValues(alpha: .10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            onTap: () {
              _wakeWallTapHaptic();
              onTap();
            },
            onLongPress: onLongPress == null
                ? null
                : () {
                    _wakeWallCommitHaptic();
                    onLongPress!();
                  },
            splashFactory: NoSplash.splashFactory,
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              child: Row(
                children: [
                  Icon(icon, color: selected ? colors.tealStrong : null),
                  const SizedBox(width: 22),
                  Expanded(
                    child: Text(
                      title,
                      style: titleStyle?.copyWith(
                        color: titleColor,
                        fontSize: (titleStyle.fontSize ?? 15) * 1.15,
                      ),
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 90),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      key: ValueKey(selected),
                      color: selected ? colors.tealStrong : colors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

EdgeInsets _bottomSheetPadding(
  BuildContext context, {
  required double left,
  required double top,
  required double right,
}) {
  // Keeps sheet content above gesture and 3-button navigation areas.
  return EdgeInsets.fromLTRB(
    left,
    top,
    right,
    24 + MediaQuery.viewPaddingOf(context).bottom,
  );
}

BoxConstraints? _tabletBottomSheetConstraints(BuildContext context) {
  if (MediaQuery.sizeOf(context).width < _tabletLayoutBreakpoint) return null;
  return const BoxConstraints(maxWidth: _tabletSheetMaxWidth);
}

// Compares album sets without caring about selection order.
bool _sameStringSet(Set<String> left, Set<String> right) {
  if (left.length != right.length) return false;
  for (final value in left) {
    if (!right.contains(value)) return false;
  }
  return true;
}

// Shared text prompt for new album names and renames.
Future<String?> _albumNameDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
}) async {
  final colors = context.wakeWallColors;
  final textController = TextEditingController(text: initialValue);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.surface,
      title: Text(title),
      content: TextField(
        controller: textController,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(hintText: 'Album name'),
      ),
      actions: [
        TextButton(
          onPressed: () {
            _wakeWallTapHaptic();
            Navigator.pop(context);
          },
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            _wakeWallCommitHaptic();
            Navigator.pop(context, textController.text.trim());
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  textController.dispose();
  return result == null || result.isEmpty ? null : result;
}

// Bottom sheet for all app-wide settings and backup/restore actions.
class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.controller});

  final WakeWallController controller;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  bool handlingBackup = false;
  bool showingFileProgress = false;
  Timer? fileProgressTimer;
  String fileProgressTitle = '';

  WakeWallController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final colors = context.wakeWallColors;
        final titleColor = _wakeWallProminentTextColor(context);
        return Stack(
          children: [
            SingleChildScrollView(
              key: const ValueKey('settings-sheet-content'),
              padding: _bottomSheetPadding(
                context,
                left: 22,
                top: 4,
                right: 22,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        'Settings',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: titleColor),
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () {
                          _wakeWallTapHaptic();
                          Navigator.pop(context);
                        },
                        tooltip: 'Close Settings',
                        icon: Icon(
                          Icons.close_rounded,
                          color: colors.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _SegmentedSetting(
                    label: 'Order',
                    icon: Icons.shuffle_rounded,
                    options: const ['Shuffle', 'In Order'],
                    selectedIndex: controller.order == RotationOrder.shuffle
                        ? 0
                        : 1,
                    onSelected: (index) => controller.setOrder(
                      index == 0
                          ? RotationOrder.shuffle
                          : RotationOrder.sequential,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SwitchTile(
                    label: 'Pause WakeWall',
                    description: 'Keep the current wallpaper in place',
                    value: controller.paused,
                    onChanged: controller.setPaused,
                  ),
                  const SizedBox(height: 10),
                  _SegmentedSetting(
                    label: 'Theme',
                    icon: Icons.brightness_auto_outlined,
                    options: const ['System', 'Light', 'Dark', 'Midnight'],
                    selectedIndex: controller.themeMode.index,
                    onSelected: (index) => controller.setThemeMode(
                      WakeWallThemeMode.values[index],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SwitchTile(
                    label: 'Wallpaper Scrolling',
                    description: 'Move the wallpaper as you swipe Home screens',
                    value: controller.wallpaperScrolling,
                    onChanged: _setWallpaperScrolling,
                  ),
                  const SizedBox(height: 10),
                  _SegmentedSetting(
                    label: 'Photo Source',
                    icon: Icons.add_photo_alternate_outlined,
                    options: const ['Ask', 'Photos', 'Files'],
                    selectedIndex: controller.photoSource.index,
                    onSelected: (index) =>
                        controller.setPhotoSource(PhotoSource.values[index]),
                  ),
                  const SizedBox(height: 10),
                  _SwitchTile(
                    label: 'Choose Albums After Import',
                    description: 'Ask where new wallpapers should be added',
                    value: controller.askAlbumsAfterImport,
                    onChanged: (value) => controller.setImportAlbumPreference(
                      value,
                      controller.defaultImportAlbumIds,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _SwitchTile(
                    label: 'Ultra High Resolution',
                    description: 'Skip import caps for very large new photos',
                    badge: 'Experimental',
                    value: controller.ultraHighResolutionMode,
                    onChanged: _setUltraHighResolutionMode,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: handlingBackup
                              ? null
                              : () {
                                  _wakeWallTapHaptic();
                                  unawaited(_backup(false));
                                },
                          icon: const Icon(Icons.save_alt_rounded),
                          label: const Text('Backup'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: handlingBackup
                              ? null
                              : () {
                                  _wakeWallTapHaptic();
                                  unawaited(_backup(true));
                                },
                          icon: const Icon(Icons.restore_rounded),
                          label: const Text('Restore'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: controller.wakeWallActive
                        ? null
                        : () {
                            _wakeWallTapHaptic();
                            unawaited(controller.openWallpaperPicker());
                          },
                    icon: Icon(
                      controller.wakeWallActive
                          ? Icons.check_circle_outline_rounded
                          : Icons.wallpaper_rounded,
                    ),
                    label: Text(
                      controller.wakeWallActive
                          ? 'WakeWall Is Active'
                          : 'Use WakeWall',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const PrivacyPolicyAction(),
                ],
              ),
            ),
            if (showingFileProgress)
              _OperationOverlay(
                overlayKey: const ValueKey('backup-loading-overlay'),
                title: fileProgressTitle,
                description: fileProgressTitle == 'Restoring Backup'
                    ? 'Recovering your wallpapers and settings...'
                    : 'Saving your wallpapers and settings...',
              ),
          ],
        );
      },
    );
  }

  Future<void> _backup(bool restore) async {
    // Restore can wipe the current setup, so confirm only when there is data to lose.
    if (restore && controller.wallpapers.length > 1) {
      final colors = context.wakeWallColors;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: colors.surface,
          title: const Text('Replace Current Setup?'),
          content: const Text(
            'Restoring a backup will replace your current wallpapers, order, crops, and settings.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                _wakeWallTapHaptic();
                Navigator.pop(context, false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                _wakeWallCommitHaptic();
                Navigator.pop(context, true);
              },
              child: const Text('Restore Backup'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => handlingBackup = true);
    fileProgressTitle = restore ? 'Restoring Backup' : 'Creating Backup';
    void beginProgressDelay() {
      fileProgressTimer ??= Timer(_HomeScreenState.importOverlayDelay, () {
        if (mounted) setState(() => showingFileProgress = true);
      });
    }

    String? message;
    try {
      // The overlay timer starts only after Android confirms a file picker destination.
      message = restore
          ? await controller.restore(onOperationStarted: beginProgressDelay)
          : await controller.backup(onOperationStarted: beginProgressDelay);
    } finally {
      fileProgressTimer?.cancel();
      fileProgressTimer = null;
      if (mounted) {
        setState(() {
          handlingBackup = false;
          showingFileProgress = false;
        });
      }
    }
    if (!mounted) return;
    final text = controller.lastNativeError ?? message;
    if (text != null) {
      showWakeWallNotice(
        context,
        message: text,
        icon: controller.lastNativeError == null
            ? Icons.check_circle_outline_rounded
            : Icons.error_outline_rounded,
        iconColor: controller.lastNativeError == null
            ? context.wakeWallColors.tealStrong
            : context.wakeWallColors.danger,
      );
    }
    if (restore &&
        message != null &&
        controller.lastNativeError == null &&
        controller.hasWallpapers) {
      await _offerWallpaperSetupIfNeeded(context, controller);
    }
  }

  Future<void> _setWallpaperScrolling(bool enabled) async {
    // Enabling scrolling prepares wider renders, so ask before increasing storage work.
    if (!enabled) {
      await controller.setWallpaperScrolling(false);
      return;
    }
    final colors = context.wakeWallColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Enable Wallpaper Scrolling?'),
        content: const Text(
          'WakeWall will prepare wider wallpaper copies. This uses more storage and may reduce performance on some devices.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              _wakeWallTapHaptic();
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _wakeWallCommitHaptic();
              Navigator.pop(context, true);
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.setWallpaperScrolling(true);
    }
  }

  Future<void> _setUltraHighResolutionMode(bool enabled) async {
    // Ultra mode keeps future imports larger, so make the storage risk explicit.
    if (!enabled) {
      await controller.setUltraHighResolutionMode(false);
      return;
    }
    final colors = context.wakeWallColors;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surface,
        title: const Text('Enable Ultra High Resolution?'),
        content: const Text(
          'WakeWall will stop optimizing very large new photos down to the normal 8192px and 200MB safety caps. This is experimental and can use more storage, slow imports, or be less stable on some devices.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              _wakeWallTapHaptic();
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              _wakeWallCommitHaptic();
              Navigator.pop(context, true);
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await controller.setUltraHighResolutionMode(true);
    }
  }

  @override
  void dispose() {
    fileProgressTimer?.cancel();
    super.dispose();
  }
}

// Result from the Add Wallpapers source picker.
class _AddSourceChoice {
  const _AddSourceChoice(this.source, this.remember);

  final PhotoSource source;
  final bool remember;
}

// Lets users choose Photos or Files, optionally saving that preference.
class _AddSourceSheet extends StatefulWidget {
  const _AddSourceSheet();

  @override
  State<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends State<_AddSourceSheet> {
  bool remember = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add Wallpapers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Choose where WakeWall should look.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.muted),
          ),
          const SizedBox(height: 18),
          _SourceOption(
            icon: Icons.photo_library_outlined,
            title: 'Photos',
            description: "Use Android's polished photo picker",
            badge: 'Recommended',
            onTap: () => _select(PhotoSource.photos),
          ),
          const SizedBox(height: 10),
          _SourceOption(
            icon: Icons.folder_outlined,
            title: 'Files & Other Apps',
            description: 'Browse Gallery, Downloads, and file providers',
            onTap: () => _select(PhotoSource.files),
          ),
          const SizedBox(height: 14),
          _RememberChoiceTile(
            label: 'Always Use My Choice',
            description: 'You can change this later in Settings',
            value: remember,
            onChanged: (value) => setState(() => remember = value),
          ),
        ],
      ),
    );
  }

  void _select(PhotoSource source) {
    Navigator.pop(context, _AddSourceChoice(source, remember));
  }
}

// Single source choice row inside the Add Wallpapers sheet.
class _SourceOption extends StatelessWidget {
  const _SourceOption({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Material(
      color: colors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          _wakeWallTapHaptic();
          onTap();
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.raisedSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: colors.tealStrong),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        if (badge != null) ...[
                          const SizedBox(width: 8),
                          _StatusPill(label: badge!, icon: Icons.check_rounded),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: colors.muted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

// Shared setting card for compact segmented choices.
class _SegmentedSetting extends StatelessWidget {
  const _SegmentedSetting({
    required this.label,
    required this.icon,
    required this.options,
    required this.selectedIndex,
    required this.onSelected,
  });

  final String label;
  final IconData icon;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final labelColor = _wakeWallProminentTextColor(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: colors.muted),
              const SizedBox(width: 10),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: labelColor),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: [
                for (var i = 0; i < options.length; i++)
                  ButtonSegment(
                    value: i,
                    label: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(options[i]),
                    ),
                  ),
              ],
              selected: {selectedIndex},
              onSelectionChanged: (selection) {
                final next = selection.first;
                if (next != selectedIndex) _wakeWallTapHaptic();
                onSelected(next);
              },
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: colors.teal,
                selectedForegroundColor: colors.ink,
                backgroundColor: colors.raisedSurface,
                foregroundColor: colors.muted,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Shared setting card for boolean options with a short explanation.
class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.badge,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    final labelColor = _wakeWallProminentTextColor(context);
    void toggle(bool next) {
      if (next != value) _wakeWallTapHaptic();
      onChanged(next);
    }

    return MergeSemantics(
      child: Material(
        color: colors.background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => toggle(!value),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: Theme.of(
                          context,
                        ).textTheme.labelLarge?.copyWith(color: labelColor),
                      ),
                      const SizedBox(height: 3),
                      Text.rich(
                        TextSpan(
                          children: [
                            if (badge != null)
                              TextSpan(
                                text: '$badge · ',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: colors.tealStrong,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            TextSpan(
                              text: description,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(value: value, onChanged: toggle),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Reusable remember-my-choice switch used by import source and album prompts.
class _RememberChoiceTile extends StatelessWidget {
  const _RememberChoiceTile({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(description),
      value: value,
      onChanged: (next) {
        if (next != value) _wakeWallTapHaptic();
        onChanged(next);
      },
    );
  }
}

// Small rounded label for optional badges such as Recommended.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.wakeWallColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.raisedSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colors.muted),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
