import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../models/wallpaper.dart';
import '../services/native_wallpaper_bridge.dart';

class WakeWallController extends ChangeNotifier {
  WakeWallController({NativeWallpaperBridge? bridge})
    : _bridge = bridge ?? NativeWallpaperBridge();

  final NativeWallpaperBridge _bridge;
  final List<Wallpaper> _wallpapers = [];
  final List<WallpaperAlbum> _albums = [];
  final ValueNotifier<int> _selectedIndexNotifier = ValueNotifier<int>(0);
  Set<String> _activeAlbumIds = {};
  bool _askAlbumsAfterImport = true;
  Set<String> _defaultImportAlbumIds = {};

  int _selectedIndex = 0;
  bool _paused = false;
  RotationOrder _order = RotationOrder.shuffle;
  WallpaperFit _fit = WallpaperFit.cropToFill;
  bool _wallpaperScrolling = false;
  bool _wakeWallActive = false;
  PhotoSource _photoSource = PhotoSource.askEveryTime;
  String? _lastNativeError;
  Future<void>? _initialization;

  List<Wallpaper> get wallpapers => List.unmodifiable(_wallpapers);
  List<WallpaperAlbum> get albums => List.unmodifiable(_albums);
  Set<String> get activeAlbumIds => Set.unmodifiable(_activeAlbumIds);
  bool get askAlbumsAfterImport => _askAlbumsAfterImport;
  Set<String> get defaultImportAlbumIds =>
      Set.unmodifiable(_defaultImportAlbumIds);
  int get selectedIndex => _selectedIndex;
  ValueListenable<int> get selectedIndexListenable => _selectedIndexNotifier;
  bool get hasWallpapers => _wallpapers.isNotEmpty;
  bool get paused => _paused;
  RotationOrder get order => _order;
  WallpaperFit get fit => _fit;
  bool get wallpaperScrolling => _wallpaperScrolling;
  bool get wakeWallActive => _wakeWallActive;
  PhotoSource get photoSource => _photoSource;
  Uint8List? get selectedPreview => selectedWallpaper?.preview;
  String? get lastNativeError => _lastNativeError;

  Wallpaper? get selectedWallpaper =>
      hasWallpapers ? _wallpapers[_selectedIndex] : null;

  // Restores the wallpaper service's saved choices when the app opens.
  Future<void> initialize() {
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    try {
      _applyConfiguration(await _bridge.configuration());
      notifyListeners();
    } on MissingPluginException {
      // Non-Android previews use the in-memory defaults.
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    }
  }

  // Refreshes changing settings without reloading every image preview.
  Future<void> refreshState() async {
    try {
      _applyConfiguration(await _bridge.state());
      notifyListeners();
    } on MissingPluginException {
      // Non-Android previews use the in-memory defaults.
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    }
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= _wallpapers.length) return;
    _setSelectedIndex(index);
    await _runNative(() async {
      final selected = await _bridge.setCurrent(index);
      if (selected != null && selected >= 0 && selected < _wallpapers.length) {
        _setSelectedIndex(selected);
      }
    });
  }

  // Saves a crop in the app and sends the same position to Android.
  Future<void> updateCrop(
    int index,
    WallpaperCrop crop, {
    WallpaperDisplayMode? displayMode,
    Color? fitBackgroundColor,
  }) async {
    if (index < 0 || index >= _wallpapers.length) return;
    final selectedMode = displayMode ?? _wallpapers[index].displayMode;
    final selectedFitColor =
        fitBackgroundColor ?? _wallpapers[index].fitBackgroundColor;
    _wallpapers[index] = _wallpapers[index].copyWith(
      crop: crop,
      displayMode: selectedMode,
      fitBackgroundColor: selectedFitColor,
    );
    notifyListeners();
    await _runNative(() async {
      final updated = _wallpaperFromNative(
        await _bridge.updateCrop(
          index: index,
          scale: crop.scale,
          offsetX: crop.offsetX,
          offsetY: crop.offsetY,
          displayMode: selectedMode.name,
          fitBackgroundColor: selectedFitColor.toARGB32(),
        ),
      );
      if (updated != null) {
        _wallpapers[index] = updated;
        notifyListeners();
      }
    });
  }

  Future<void> next() async {
    if (_wallpapers.isEmpty) return;
    _setSelectedIndex((_selectedIndex + 1) % _wallpapers.length);
    await _runNative(() async {
      final next = await _bridge.showNext();
      if (next != null) {
        _setSelectedIndex(next % _wallpapers.length);
      }
    });
  }

  Future<void> addImages({
    ValueChanged<ImportProgress>? onImportProgress,
  }) async {
    await _importImages(_bridge.pickImages, onImportProgress: onImportProgress);
  }

  Future<void> addImagesFromFiles({
    ValueChanged<ImportProgress>? onImportProgress,
  }) async {
    await _importImages(
      _bridge.pickImagesFromFiles,
      onImportProgress: onImportProgress,
    );
  }

  Future<void> setPhotoSource(PhotoSource value) async {
    _photoSource = value;
    notifyListeners();
    await _runNative(() => _bridge.updatePhotoSource(value.name));
  }

  Future<void> createAlbum(String name) =>
      _applyNativeConfiguration(() => _bridge.createAlbum(name));

  Future<void> renameAlbum(String id, String name) =>
      _applyNativeConfiguration(() => _bridge.renameAlbum(id, name));

  Future<void> deleteAlbum(
    String id, {
    required bool deleteExclusiveWallpapers,
  }) => _applyNativeConfiguration(
    () => _bridge.deleteAlbum(
      id,
      deleteExclusiveWallpapers: deleteExclusiveWallpapers,
    ),
  );

  Future<void> setActiveAlbums(Set<String> ids) =>
      _applyNativeConfiguration(() => _bridge.setActiveAlbums(ids));

  Future<void> updateWallpaperAlbums(Wallpaper wallpaper, Set<String> ids) =>
      _applyNativeConfiguration(
        () => _bridge.updateWallpaperAlbums(wallpaper.id, ids),
      );

  Future<void> setImportAlbumPreference(bool ask, Set<String> ids) async {
    _askAlbumsAfterImport = ask;
    _defaultImportAlbumIds = {...ids};
    notifyListeners();
    await _applyNativeConfiguration(
      () => _bridge.updateImportAlbumPreference(ask, ids),
    );
  }

  Future<void> _applyNativeConfiguration(
    Future<Map<String, Object?>> Function() action,
  ) async {
    await _runNative(() async {
      _applyConfiguration(await action());
      notifyListeners();
    });
  }

  Future<String?> backup({VoidCallback? onOperationStarted}) =>
      _runFileAction(_bridge.backup, onOperationStarted: onOperationStarted);

  Future<String?> restore({VoidCallback? onOperationStarted}) async {
    final message = await _runFileAction(
      _bridge.restore,
      applyResult: true,
      onOperationStarted: onOperationStarted,
    );
    notifyListeners();
    return message;
  }

  Future<void> _importImages(
    Future<Map<String, Object?>> Function() picker, {
    ValueChanged<ImportProgress>? onImportProgress,
  }) async {
    _bridge.setImageImportProgressListener(onImportProgress);
    try {
      await _runNative(() async {
        final configuration = await picker();
        if (configuration['cancelled'] == true) return;
        _applyImportResult(configuration);
        final failedImages =
            configuration['failedImages'] as List<Object?>? ?? const [];
        final failedWithoutBytes =
            (configuration['failedWithoutBytesCount'] as num?)?.toInt() ?? 0;
        var storedRecovered = 0;
        for (final value in failedImages) {
          final data = Map<Object?, Object?>.from(value! as Map);
          final normalized = await compute(_normalizeFailedImage, {
            'name': data['name'] as String? ?? 'Photo',
            'bytes': data['bytes'] as Uint8List,
          });
          if (normalized == null) continue;
          final recoveredConfiguration = await _bridge.importNormalizedImages([
            normalized,
          ]);
          storedRecovered +=
              (recoveredConfiguration['normalizedImportedCount'] as num?)
                  ?.toInt() ??
              0;
          _applyImportResult(recoveredConfiguration);
        }
        final failed =
            failedWithoutBytes + failedImages.length - storedRecovered;
        if (failed > 0) {
          _lastNativeError = failed == 1
              ? 'One photo could not be imported.'
              : '$failed photos could not be imported.';
        }
        notifyListeners();
      });
    } finally {
      _bridge.setImageImportProgressListener(null);
    }
  }

  Future<WallpaperRemoval?> removeAt(int index) async {
    if (index < 0 || index >= _wallpapers.length) return null;
    WallpaperRemoval? removal;
    await _runNative(() async {
      final configuration = await _bridge.removeWallpaper(index);
      final removed = configuration['removedWallpaper'];
      if (removed is Map) {
        final data = Map<Object?, Object?>.from(removed);
        final value = data['value'] as String?;
        if (value != null) {
          removal = WallpaperRemoval(
            value: value,
            index: (data['index'] as num?)?.toInt() ?? index,
            wasSelected: data['wasSelected'] == true,
          );
        }
      }
      _applyConfiguration(configuration);
      notifyListeners();
    });
    return removal;
  }

  Future<void> undoRemoval(WallpaperRemoval removal) async {
    await _runNative(() async {
      _applyConfiguration(
        await _bridge.restoreWallpaper(
          value: removal.value,
          index: removal.index,
          wasSelected: removal.wasSelected,
        ),
      );
      notifyListeners();
    });
  }

  Future<void> finalizeRemoval(WallpaperRemoval removal) =>
      _runNative(() => _bridge.finalizeRemoval(removal.value));

  // Reorders the list without losing which wallpaper is selected.
  Future<void> move(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        oldIndex >= _wallpapers.length ||
        newIndex < 0 ||
        newIndex >= _wallpapers.length ||
        oldIndex == newIndex) {
      return;
    }
    final selectedId = selectedWallpaper?.id;
    _wallpapers.insert(newIndex, _wallpapers.removeAt(oldIndex));
    _setSelectedIndex(
      selectedId == null
          ? 0
          : math.max(
              0,
              _wallpapers.indexWhere((wallpaper) => wallpaper.id == selectedId),
            ),
    );
    notifyListeners();
    await _runNative(() => _bridge.moveWallpaper(oldIndex, newIndex));
  }

  Future<void> setPaused(bool value) async {
    _paused = value;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setOrder(RotationOrder value) async {
    _order = value;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setFit(WallpaperFit value) async {
    _fit = value;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setWallpaperScrolling(bool value) async {
    _wallpaperScrolling = value;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> openWallpaperPicker() => _runNative(_bridge.openWallpaperPicker);

  Future<bool> claimWallpaperSetupOffer() async {
    try {
      return await _bridge.claimWallpaperSetupOffer();
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> _syncSettings() {
    return _runNative(
      () => _bridge.updateSettings(
        paused: _paused,
        shuffle: _order == RotationOrder.shuffle,
        fit: _fit.name,
        wallpaperScrolling: _wallpaperScrolling,
      ),
    );
  }

  Future<String?> _runFileAction(
    Future<Map<String, Object?>> Function() action, {
    bool applyResult = false,
    VoidCallback? onOperationStarted,
  }) async {
    _bridge.setFileOperationStartedListener(onOperationStarted);
    try {
      _lastNativeError = null;
      final result = await action();
      if (result['cancelled'] == true) return null;
      if (applyResult) _applyConfiguration(result);
      return result['message'] as String?;
    } on MissingPluginException {
      _lastNativeError = 'Backup and restore require Android.';
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    } catch (_) {
      _lastNativeError = 'WakeWall could not complete that file operation.';
    } finally {
      _bridge.setFileOperationStartedListener(null);
    }
    return null;
  }

  // Rebuilds the Flutter list from Android's saved wallpaper collection.
  void _applyConfiguration(Map<String, Object?> configuration) {
    _paused = configuration['paused'] as bool? ?? _paused;
    if (configuration.containsKey('shuffle')) {
      _order = configuration['shuffle'] == true
          ? RotationOrder.shuffle
          : RotationOrder.sequential;
    }
    final savedFit = configuration['fit'] as String?;
    if (savedFit != null) {
      _fit = savedFit == WallpaperFit.fitEntireImage.name
          ? WallpaperFit.fitEntireImage
          : WallpaperFit.cropToFill;
    }
    _wallpaperScrolling =
        configuration['wallpaperScrolling'] as bool? ?? _wallpaperScrolling;
    _wakeWallActive =
        configuration['wakeWallActive'] as bool? ?? _wakeWallActive;
    final savedSource = configuration['photoSource'] as String?;
    if (savedSource != null) {
      _photoSource = PhotoSource.values.firstWhere(
        (source) => source.name == savedSource,
        orElse: () => _photoSource,
      );
    }

    final savedWallpapers =
        configuration['wallpapers'] as List<Object?>? ?? const [];
    if (savedWallpapers.isNotEmpty || configuration.containsKey('wallpapers')) {
      final restored = <Wallpaper>[];
      for (final value in savedWallpapers) {
        final wallpaper = _wallpaperFromNative(value);
        if (wallpaper != null) restored.add(wallpaper);
      }
      _wallpapers
        ..clear()
        ..addAll(restored);
    }
    final savedAlbums = configuration['albums'] as List<Object?>?;
    if (savedAlbums != null) {
      _albums
        ..clear()
        ..addAll(
          savedAlbums
              .whereType<Map>()
              .map((value) {
                final data = Map<Object?, Object?>.from(value);
                return WallpaperAlbum(
                  id: data['id'] as String? ?? '',
                  name: data['name'] as String? ?? 'Album',
                );
              })
              .where((album) => album.id.isNotEmpty),
        );
    }
    final activeIds = configuration['activeAlbumIds'] as List<Object?>?;
    if (activeIds != null) {
      _activeAlbumIds = activeIds.whereType<String>().toSet();
    }
    _askAlbumsAfterImport =
        configuration['askAlbumsAfterImport'] as bool? ?? _askAlbumsAfterImport;
    final defaultAlbumIds =
        configuration['defaultImportAlbumIds'] as List<Object?>?;
    if (defaultAlbumIds != null) {
      _defaultImportAlbumIds = defaultAlbumIds.whereType<String>().toSet();
    }
    final savedIndex =
        (configuration['index'] as num?)?.toInt() ?? _selectedIndex;
    _setSelectedIndex(
      _wallpapers.isEmpty ? 0 : savedIndex % _wallpapers.length,
    );
  }

  void _setSelectedIndex(int index) {
    final normalized = _wallpapers.isEmpty ? 0 : index % _wallpapers.length;
    _selectedIndex = normalized;
    if (_selectedIndexNotifier.value != normalized) {
      _selectedIndexNotifier.value = normalized;
    }
  }

  // Adds only the newly imported previews instead of rebuilding the full library.
  void _applyImportResult(Map<String, Object?> configuration) {
    _applyConfiguration(configuration);
    if (configuration.containsKey('wallpapers')) return;
    final added =
        configuration['addedWallpapers'] as List<Object?>? ?? const [];
    for (final value in added) {
      final wallpaper = _wallpaperFromNative(value);
      if (wallpaper != null) _wallpapers.add(wallpaper);
    }
  }

  Wallpaper? _wallpaperFromNative(Object? value) {
    if (value is! Map) return null;
    final data = Map<Object?, Object?>.from(value);
    final sampleIndex = (data['sampleIndex'] as num?)?.toInt();
    final cropValue = data['crop'];
    final cropData = cropValue is Map
        ? Map<Object?, Object?>.from(cropValue)
        : const <Object?, Object?>{};
    final crop = WallpaperCrop(
      scale: ((cropData['scale'] as num?)?.toDouble() ?? 1)
          .clamp(1, 4)
          .toDouble(),
      offsetX: ((cropData['offsetX'] as num?)?.toDouble() ?? 0)
          .clamp(-4, 4)
          .toDouble(),
      offsetY: ((cropData['offsetY'] as num?)?.toDouble() ?? 0)
          .clamp(-4, 4)
          .toDouble(),
    );
    final displayMode = WallpaperDisplayMode.values.firstWhere(
      (mode) => mode.name == data['displayMode'],
      orElse: () => WallpaperDisplayMode.fill,
    );
    final fitBackgroundColor = Color(
      (data['fitBackgroundColor'] as num?)?.toInt() ?? 0xFF202124,
    );
    if (sampleIndex != null) {
      return bundledWallpapers[sampleIndex % bundledWallpapers.length].copyWith(
        crop: crop,
        displayMode: displayMode,
        fitBackgroundColor: fitBackgroundColor,
      );
    }
    final uri = data['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return Wallpaper(
      id: uri,
      name: data['name'] as String? ?? 'Photo',
      palette: const [Color(0xFF202124), Color(0xFF303134), Color(0xFF8AB4F8)],
      style: 0,
      uri: uri,
      thumbnail: data['thumbnail'] as Uint8List?,
      mainPreview: data['mainPreview'] as Uint8List?,
      preview: data['preview'] as Uint8List?,
      imageWidth: (data['imageWidth'] as num?)?.toInt(),
      imageHeight: (data['imageHeight'] as num?)?.toInt(),
      crop: crop,
      displayMode: displayMode,
      fitBackgroundColor: fitBackgroundColor,
      albumIds: (data['albumIds'] as List<Object?>? ?? const [])
          .whereType<String>()
          .toSet(),
    );
  }

  // Keeps Android-only errors from breaking previews on other platforms.
  Future<void> _runNative(Future<void> Function() action) async {
    try {
      _lastNativeError = null;
      await action();
    } on MissingPluginException {
      _lastNativeError = 'Native wallpaper controls require Android.';
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    } catch (_) {
      _lastNativeError = 'The selected photo could not be imported.';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _selectedIndexNotifier.dispose();
    super.dispose();
  }
}

class WallpaperRemoval {
  const WallpaperRemoval({
    required this.value,
    required this.index,
    required this.wasSelected,
  });

  final String value;
  final int index;
  final bool wasSelected;
}

// Rewrites photos Android cannot decode into a clean, standard JPEG.
Map<String, Object?>? _normalizeFailedImage(Map<String, Object?> value) {
  try {
    final decoded = image.decodeImage(value['bytes']! as Uint8List);
    if (decoded == null) return null;
    var normalized = image.bakeOrientation(decoded);
    if (normalized.width > 6144 || normalized.height > 6144) {
      if (normalized.width >= normalized.height) {
        normalized = image.copyResize(normalized, width: 6144);
      } else {
        normalized = image.copyResize(normalized, height: 6144);
      }
    }
    return {
      'name': value['name']! as String,
      'bytes': Uint8List.fromList(image.encodeJpg(normalized, quality: 98)),
    };
  } catch (_) {
    return null;
  }
}
