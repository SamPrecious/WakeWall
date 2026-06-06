import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import '../controllers/wakewall_controller.dart';
import '../models/wallpaper.dart';
import '../navigation/app_router.dart';
import '../theme/wakewall_theme.dart';
import '../widgets/abstract_wallpaper.dart';

@RoutePage()
class HomeScreen extends StatelessWidget {
  const HomeScreen({required this.controller, super.key});

  final WakeWallController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
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
                  padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
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
                            onAdd: controller.addImages,
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
                          child: _WallpaperStrip(controller: controller),
                        ),
                      SizedBox(height: compact ? 10 : 18),
                    ],
                  ),
                );
              },
            ),
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
    required this.onAdd,
    required this.onCrop,
  });

  final WakeWallController controller;
  final double maximumHeight;
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
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        child: controller.hasWallpapers
            ? Stack(
                key: const ValueKey('populated'),
                fit: StackFit.expand,
                children: [
                  AbstractWallpaper(
                    wallpaper: controller.selectedWallpaper!,
                    borderRadius: radius,
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
    );
  }
}

class _EmptyPreview extends StatelessWidget {
  const _EmptyPreview({required this.onAdd, super.key});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          top: 18,
          left: 0,
          right: 0,
          child: Center(
            child: SizedBox(
              width: 108,
              height: 30,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0xFF303136),
                  borderRadius: BorderRadius.all(Radius.circular(18)),
                ),
              ),
            ),
          ),
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.crop_free_rounded,
                  color: WakeWallColors.muted,
                  size: 38,
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: 170,
                  child: FilledButton(
                    onPressed: onAdd,
                    child: const Text('Add Images'),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Choose images to begin.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: WakeWallColors.teal),
                ),
              ],
            ),
          ),
        ),
      ],
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

class _WallpaperStrip extends StatelessWidget {
  const _WallpaperStrip({required this.controller});

  final WakeWallController controller;

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
              onPressed: controller.addImages,
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
                scrollDirection: Axis.horizontal,
                itemCount: controller.wallpapers.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final selected = index == controller.selectedIndex;
                  return GestureDetector(
                    onTap: () => controller.select(index),
                    onLongPress: () => _showWallpaperActions(context, index),
                    child: AnimatedContainer(
                      key: ValueKey('wallpaper-thumbnail-$index'),
                      duration: const Duration(milliseconds: 220),
                      width: tileWidth,
                      height: tileHeight,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        color: selected
                            ? WakeWallColors.tealStrong.withValues(alpha: .12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: selected
                              ? WakeWallColors.tealStrong
                              : Colors.transparent,
                          width: 1,
                        ),
                      ),
                      child: AbstractWallpaper(
                        wallpaper: controller.wallpapers[index],
                        borderRadius: BorderRadius.circular(10.5),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _showWallpaperActions(BuildContext context, int index) {
    final wallpaper = controller.wallpapers[index];
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                wallpaper.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: index == 0
                          ? null
                          : () {
                              controller.move(index, index - 1);
                              Navigator.pop(context);
                            },
                      icon: const Icon(Icons.arrow_back_rounded),
                      label: const Text('Move left'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: index == controller.wallpapers.length - 1
                          ? null
                          : () {
                              controller.move(index, index + 1);
                              Navigator.pop(context);
                            },
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: const Text('Move right'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  controller.removeAt(index);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Remove wallpaper'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: WakeWallColors.danger,
                ),
              ),
            ],
          ),
        ),
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
                options: const ['Sequential', 'Shuffle'],
                selectedIndex: controller.order == RotationOrder.sequential
                    ? 0
                    : 1,
                onSelected: (index) => controller.setOrder(
                  index == 0 ? RotationOrder.sequential : RotationOrder.shuffle,
                ),
              ),
              const SizedBox(height: 10),
              _SettingTile(
                label: 'Fit mode',
                value: controller.fit == WallpaperFit.cropToFill
                    ? 'Crop to Fill'
                    : 'Fit Entire Image',
                icon: Icons.fit_screen_outlined,
                onTap: () => _showFitPicker(context),
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
                label: const Text('Make WakeWall Active'),
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

  Future<void> _showFitPicker(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Fit mode', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 14),
              _ChoiceTile(
                label: 'Crop to Fill',
                description: 'Fills the screen and crops the edges',
                selected: controller.fit == WallpaperFit.cropToFill,
                onTap: () {
                  controller.setFit(WallpaperFit.cropToFill);
                  Navigator.pop(context);
                },
              ),
              _ChoiceTile(
                label: 'Fit Entire Image',
                description: 'Shows the full image inside the screen',
                selected: controller.fit == WallpaperFit.fitEntireImage,
                onTap: () {
                  controller.setFit(WallpaperFit.fitEntireImage);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
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

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: WakeWallColors.background,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(icon, size: 20, color: WakeWallColors.muted),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: WakeWallColors.muted,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(value, style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
              ),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: WakeWallColors.muted,
              ),
            ],
          ),
        ),
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

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(description),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: selected ? WakeWallColors.teal : WakeWallColors.muted,
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
