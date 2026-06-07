import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/wakewall_controller.dart';
import '../models/wallpaper.dart';
import '../navigation/app_router.dart';
import '../theme/wakewall_theme.dart';
import '../widgets/abstract_wallpaper.dart';

@RoutePage()
class HomeScreen extends StatefulWidget {
  const HomeScreen({required this.controller, super.key});

  final WakeWallController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const importOverlayDelay = Duration(milliseconds: 350);

  bool draggingWallpaper = false;
  bool importingImages = false;

  WakeWallController get controller => widget.controller;

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
                    final compact = constraints.maxHeight < 720;
                    final horizontalPadding = constraints.maxWidth < 420
                        ? 20.0
                        : 28.0;
                    final headerHeight = compact ? 70.0 : 88.0;
                    final minimumCollectionHeight = controller.hasWallpapers
                        ? (compact ? 94.0 : 116.0)
                        : 0.0;
                    final reserved =
                        headerHeight +
                        minimumCollectionHeight +
                        (compact ? 30 : 46);
                    final previewHeight = (constraints.maxHeight - reserved)
                        .clamp(320.0, 680.0)
                        .toDouble();
                    // Give portrait thumbnails any space left after preserving the preview.
                    final collectionHeight = controller.hasWallpapers
                        ? (constraints.maxHeight -
                                  headerHeight -
                                  previewHeight -
                                  (compact ? 10 : 18))
                              .clamp(
                                minimumCollectionHeight,
                                compact ? 126.0 : 156.0,
                              )
                              .toDouble()
                        : 0.0;

                    return Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: horizontalPadding,
                      ),
                      child: Column(
                        children: [
                          SizedBox(
                            height: headerHeight,
                            child: _Header(
                              paused: controller.paused,
                              onSettings: () => _showSettings(context),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: _Preview(
                                controller: controller,
                                maximumHeight: previewHeight,
                                draggingWallpaper: draggingWallpaper,
                                onRemoveWallpaper: controller.removeAt,
                                onAdd: _addImages,
                                onCrop: () => context.router.push(
                                  CropEditorRoute(
                                    controller: controller,
                                    wallpaperIndex: controller.selectedIndex,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (controller.hasWallpapers)
                            SizedBox(
                              height: collectionHeight,
                              child: _WallpaperStrip(
                                controller: controller,
                                onAdd: _addImages,
                                onDragChanged: (dragging) {
                                  if (draggingWallpaper == dragging) return;
                                  setState(() => draggingWallpaper = dragging);
                                },
                              ),
                            ),
                          SizedBox(height: compact ? 10 : 18),
                        ],
                      ),
                    );
                  },
                ),
              ),
              if (importingImages) const _ImportOverlay(),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSettings(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _SettingsSheet(controller: controller),
    );
  }

  Future<void> _addImages() async {
    var source = controller.photoSource;
    if (source == PhotoSource.askEveryTime) {
      final choice = await showModalBottomSheet<_AddSourceChoice>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => const _AddSourceSheet(),
      );
      if (choice == null || !mounted) return;
      source = choice.source;
      if (choice.remember) await controller.setPhotoSource(source);
    }

    final overlayTimer = Timer(importOverlayDelay, () {
      if (mounted) setState(() => importingImages = true);
    });
    try {
      if (source == PhotoSource.files) {
        await controller.addImagesFromFiles();
      } else {
        await controller.addImages();
      }
    } finally {
      overlayTimer.cancel();
      if (mounted) setState(() => importingImages = false);
    }

    if (!mounted || controller.lastNativeError == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 5),
          content: Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: WakeWallColors.danger,
                size: 21,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(controller.lastNativeError!)),
            ],
          ),
          action: SnackBarAction(
            label: 'Dismiss',
            textColor: WakeWallColors.tealStrong,
            onPressed: () {},
          ),
        ),
      );
  }
}

class _ImportOverlay extends StatelessWidget {
  const _ImportOverlay();

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey('import-loading-overlay'),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: .58),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280),
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
            decoration: BoxDecoration(
              color: WakeWallColors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: WakeWallColors.outline.withValues(alpha: .45),
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
                const SizedBox(
                  width: 38,
                  height: 38,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: WakeWallColors.tealStrong,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Adding wallpapers',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  'Preparing your photos...',
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: WakeWallColors.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.paused, required this.onSettings});

  final bool paused;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
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
                style: Theme.of(
                  context,
                ).textTheme.displaySmall?.copyWith(color: Colors.white),
              ),
            ),
          ),
        ),
        Positioned(
          right: 0,
          child: IconButton(
            onPressed: onSettings,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
        if (paused)
          const Positioned(
            left: 0,
            child: _StatusPill(label: 'Paused', icon: Icons.pause_rounded),
          ),
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.controller,
    required this.maximumHeight,
    required this.draggingWallpaper,
    required this.onRemoveWallpaper,
    required this.onAdd,
    required this.onCrop,
  });

  final WakeWallController controller;
  final double maximumHeight;
  final bool draggingWallpaper;
  final ValueChanged<int> onRemoveWallpaper;
  final VoidCallback onAdd;
  final VoidCallback onCrop;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final phoneRatio = (screen.width / screen.height).clamp(.44, .62);
    final availableWidth = MediaQuery.sizeOf(context).width - 40;
    final heightFromWidth = availableWidth / phoneRatio;
    final height = heightFromWidth.clamp(0, maximumHeight).toDouble();
    final width = height * phoneRatio;
    const radius = BorderRadius.all(Radius.circular(22));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: WakeWallColors.background,
        borderRadius: radius,
        border: Border.all(
          color: controller.hasWallpapers
              ? WakeWallColors.outline.withValues(alpha: .25)
              : WakeWallColors.outline,
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
            child: controller.hasWallpapers
                ? Stack(
                    key: const ValueKey('populated'),
                    fit: StackFit.expand,
                    children: [
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        switchInCurve: Curves.easeOut,
                        switchOutCurve: Curves.easeIn,
                        child: AbstractWallpaper(
                          key: ValueKey(
                            'main-preview-${controller.selectedWallpaper!.id}',
                          ),
                          wallpaper: controller.selectedWallpaper!,
                          previewBytes: controller.selectedPreview,
                          borderRadius: radius,
                        ),
                      ),
                      Positioned(
                        right: 14,
                        bottom: 14,
                        child: Row(
                          children: [
                            _OverlayButton(
                              icon: Icons.crop_rounded,
                              tooltip: 'Adjust crop',
                              onTap: onCrop,
                            ),
                            const SizedBox(width: 8),
                            _OverlayButton(
                              icon: Icons.shuffle_rounded,
                              tooltip: 'Next wallpaper',
                              onTap: controller.next,
                            ),
                          ],
                        ),
                      ),
                    ],
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
                      return AnimatedContainer(
                        key: const ValueKey('wallpaper-remove-target'),
                        duration: const Duration(milliseconds: 180),
                        width: removing ? 96 : 82,
                        height: removing ? 96 : 82,
                        decoration: BoxDecoration(
                          color: removing
                              ? WakeWallColors.danger
                              : WakeWallColors.raisedSurface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          size: removing ? 42 : 36,
                          color: removing
                              ? WakeWallColors.ink
                              : WakeWallColors.muted,
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

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: const ValueKey('empty-add-wallpapers'),
        onTap: onAdd,
        borderRadius: BorderRadius.circular(22),
        child: Center(
          child: Text(
            'Add Wallpapers',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontSize: 24,
              letterSpacing: -.6,
            ),
          ),
        ),
      ),
    );
  }
}

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
    return Tooltip(
      message: tooltip,
      child: Material(
        color: const Color(0xCC25262A),
        borderRadius: BorderRadius.circular(11),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(11),
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: const Color(0xFFE3E3E8), size: 21),
          ),
        ),
      ),
    );
  }
}

class _WallpaperStrip extends StatefulWidget {
  const _WallpaperStrip({
    required this.controller,
    required this.onAdd,
    required this.onDragChanged,
  });

  final WakeWallController controller;
  final VoidCallback onAdd;
  final ValueChanged<bool> onDragChanged;

  @override
  State<_WallpaperStrip> createState() => _WallpaperStripState();
}

class _WallpaperStripState extends State<_WallpaperStrip> {
  final ScrollController scrollController = ScrollController();

  WakeWallController get controller => widget.controller;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              'Up Next',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(letterSpacing: 1.2),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: widget.onAdd,
              iconAlignment: IconAlignment.end,
              icon: const Icon(Icons.add_rounded, size: 19),
              label: const Text('ADD'),
              style: TextButton.styleFrom(
                foregroundColor: WakeWallColors.tealStrong,
                padding: const EdgeInsets.symmetric(horizontal: 0),
              ),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screen = MediaQuery.sizeOf(context);
              final phoneRatio = (screen.width / screen.height).clamp(.44, .62);
              final tileHeight = constraints.maxHeight * .84;
              final tileWidth = constraints.maxHeight * phoneRatio;

              return ListView.separated(
                controller: scrollController,
                scrollDirection: Axis.horizontal,
                itemCount: controller.wallpapers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final selected = index == controller.selectedIndex;
                  final tile = _WallpaperTile(
                    wallpaper: controller.wallpapers[index],
                    selected: selected,
                    width: tileWidth,
                    height: tileHeight,
                  );
                  return DragTarget<int>(
                    onWillAcceptWithDetails: (details) => details.data != index,
                    onAcceptWithDetails: (details) {
                      HapticFeedback.selectionClick();
                      controller.move(details.data, index);
                    },
                    builder: (context, candidates, _) {
                      final accepting = candidates.isNotEmpty;
                      return AnimatedPadding(
                        duration: const Duration(milliseconds: 160),
                        padding: EdgeInsets.only(left: accepting ? 14 : 0),
                        child: LongPressDraggable<int>(
                          key: ValueKey('wallpaper-drag-$index'),
                          data: index,
                          rootOverlay: true,
                          dragAnchorStrategy: pointerDragAnchorStrategy,
                          onDragStarted: () {
                            HapticFeedback.mediumImpact();
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
                          childWhenDragging: Opacity(opacity: .18, child: tile),
                          child: GestureDetector(
                            onTap: () => controller.select(index),
                            child: tile,
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
      ],
    );
  }
}

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
    return AnimatedContainer(
      key: ValueKey('wallpaper-thumbnail-${wallpaper.id}'),
      duration: const Duration(milliseconds: 220),
      width: width,
      height: height,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        color: selected
            ? WakeWallColors.tealStrong.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: selected ? WakeWallColors.tealStrong : Colors.transparent,
          width: 1,
        ),
      ),
      child: AbstractWallpaper(
        wallpaper: wallpaper,
        borderRadius: BorderRadius.circular(10.5),
      ),
    );
  }
}

class _SettingsSheet extends StatelessWidget {
  const _SettingsSheet({required this.controller});

  final WakeWallController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Settings',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFFE3E3E8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              _SegmentedSetting(
                label: 'Order',
                icon: Icons.shuffle_rounded,
                options: const ['Shuffle', 'Sequential'],
                selectedIndex: controller.order == RotationOrder.shuffle
                    ? 0
                    : 1,
                onSelected: (index) => controller.setOrder(
                  index == 0 ? RotationOrder.shuffle : RotationOrder.sequential,
                ),
              ),
              const SizedBox(height: 10),
              _SegmentedSetting(
                label: 'Photo source',
                icon: Icons.add_photo_alternate_outlined,
                options: const ['Ask', 'Photos', 'Files'],
                selectedIndex: controller.photoSource.index,
                onSelected: (index) =>
                    controller.setPhotoSource(PhotoSource.values[index]),
              ),
              const SizedBox(height: 10),
              _SwitchTile(
                label: 'Pause WakeWall',
                description: 'Keep the current wallpaper in place',
                value: controller.paused,
                onChanged: controller.setPaused,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: controller.openWallpaperPicker,
                icon: const Icon(Icons.wallpaper_rounded),
                label: const Text('Use WakeWall'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => _showDiagnostics(context),
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('Wake-event diagnostics'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDiagnostics(BuildContext context) async {
    final result = await controller.diagnostics();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: WakeWallColors.surface,
        title: const Text('Wake diagnostics'),
        content: SelectableText(
          result.entries
              .map((entry) => '${entry.key}: ${entry.value}')
              .join('\n'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}

class _AddSourceChoice {
  const _AddSourceChoice(this.source, this.remember);

  final PhotoSource source;
  final bool remember;
}

class _AddSourceSheet extends StatefulWidget {
  const _AddSourceSheet();

  @override
  State<_AddSourceSheet> createState() => _AddSourceSheetState();
}

class _AddSourceSheetState extends State<_AddSourceSheet> {
  bool remember = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Add wallpapers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'Choose where WakeWall should look.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: WakeWallColors.muted),
          ),
          const SizedBox(height: 18),
          _SourceOption(
            icon: Icons.photo_library_outlined,
            title: 'Photos',
            description: 'Use Android’s polished photo picker',
            badge: 'Recommended',
            onTap: () => _select(PhotoSource.photos),
          ),
          const SizedBox(height: 10),
          _SourceOption(
            icon: Icons.folder_outlined,
            title: 'Files & other apps',
            description: 'Browse Gallery, Downloads, and file providers',
            onTap: () => _select(PhotoSource.files),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Always use my choice'),
            subtitle: const Text('You can change this later in Settings'),
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
    return Material(
      color: WakeWallColors.background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: WakeWallColors.raisedSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: WakeWallColors.tealStrong),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: WakeWallColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: WakeWallColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WakeWallColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: WakeWallColors.muted),
              const SizedBox(width: 10),
              Text(label, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              segments: [
                for (var i = 0; i < options.length; i++)
                  ButtonSegment(value: i, label: Text(options[i])),
              ],
              selected: {selectedIndex},
              onSelectionChanged: (selection) => onSelected(selection.first),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: WakeWallColors.teal,
                selectedForegroundColor: WakeWallColors.ink,
                backgroundColor: WakeWallColors.raisedSurface,
                foregroundColor: WakeWallColors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: WakeWallColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: WakeWallColors.muted),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: WakeWallColors.raisedSurface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: WakeWallColors.muted),
          const SizedBox(width: 5),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
