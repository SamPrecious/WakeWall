import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as image;

import '../models/wallpaper.dart';
import '../services/native_wallpaper_bridge.dart';

// Owns the app-facing state and keeps it in sync with Android's wallpaper store.
class WakeWallController extends ChangeNotifier {
  WakeWallController({NativeWallpaperBridge? bridge})
    : _bridge = bridge ?? NativeWallpaperBridge();

  final NativeWallpaperBridge _bridge;
  final List<Wallpaper> _wallpapers = [];
  final List<WallpaperAlbum> _albums = [];
  final ValueNotifier<int> _selectedIndexNotifier = ValueNotifier<int>(0);
  final Map<String, Future<void>> _mainPreviewLoads = {};
  final Set<String> _failedMainPreviews = {};
  final Map<String, Future<void>> _editorPreviewLoads = {};
  Set<String> _activeAlbumIds = {};
  bool _askAlbumsAfterImport = true;
  Set<String> _defaultImportAlbumIds = {};

  int _selectedIndex = 0;
  bool _paused = false;
  RotationOrder _order = RotationOrder.shuffle;
  WallpaperFit _fit = WallpaperFit.cropToFill;
  WakeWallThemeMode _themeMode = WakeWallThemeMode.system;
  bool _wallpaperScrolling = false;
  bool _ultraHighResolutionMode = false;
  bool _wakeWallActive = false;
  PhotoSource _photoSource = PhotoSource.askEveryTime;
  String? _lastNativeError;
  Future<void>? _initialization;
  bool _initialConfigurationLoaded = false;
  int? _knownWallpaperCount;
  int _selectionSerial = 0;
  bool _disposed = false;

  List<Wallpaper> get wallpapers => UnmodifiableListView(_wallpapers);
  List<WallpaperAlbum> get albums => UnmodifiableListView(_albums);
  Set<String> get activeAlbumIds => UnmodifiableSetView(_activeAlbumIds);
  bool get askAlbumsAfterImport => _askAlbumsAfterImport;
  Set<String> get defaultImportAlbumIds =>
      UnmodifiableSetView(_defaultImportAlbumIds);
  int get selectedIndex => _selectedIndex;
  ValueListenable<int> get selectedIndexListenable => _selectedIndexNotifier;
  bool get hasWallpapers => _wallpapers.isNotEmpty;
  bool get isLoadingInitialConfiguration => !_initialConfigurationLoaded;
  bool get hasStoredWallpapers =>
      hasWallpapers || (_knownWallpaperCount ?? 0) > 0;
  bool get paused => _paused;
  RotationOrder get order => _order;
  WallpaperFit get fit => _fit;
  WakeWallThemeMode get themeMode => _themeMode;
  bool get wallpaperScrolling => _wallpaperScrolling;
  bool get ultraHighResolutionMode => _ultraHighResolutionMode;
  bool get wakeWallActive => _wakeWallActive;
  PhotoSource get photoSource => _photoSource;
  Uint8List? get selectedPreview => selectedWallpaper?.preview;
  String? get lastNativeError => _lastNativeError;
  bool mainPreviewFailed(String wallpaperId) =>
      _failedMainPreviews.contains(wallpaperId);

  Wallpaper? get selectedWallpaper =>
      hasWallpapers ? _wallpapers[_selectedIndex] : null;

  // Restores the wallpaper service's saved choices when the app opens.
  Future<void> initialize() {
    return _initialization ??= _initialize().whenComplete(() {
      _initialization = null;
    });
  }

  Future<void> _initialize() async {
    if (_disposed) return;
    _initialConfigurationLoaded = false;
    _lastNativeError = null;
    notifyListeners();
    try {
      // The small state response reveals whether a library exists before Android
      // verifies or rebuilds every image preview in the full configuration.
      try {
        final state = await _bridge.state();
        if (_disposed) return;
        _applyConfiguration(state);
        notifyListeners();
      } catch (_) {
        // A failed optional fast path must not prevent the complete configuration.
      }
      _applyConfiguration(await _bridge.configuration());
    } on MissingPluginException {
      // Non-Android previews use the in-memory defaults.
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    } finally {
      _initialConfigurationLoaded = true;
      notifyListeners();
    }
  }

  // Refreshes changing settings without reloading every image preview.
  Future<void> refreshState() async {
    final serial = _selectionSerial;
    try {
      final state = await _bridge.state();
      // A resume response may describe the wallpaper from before the latest tap.
      _applyConfiguration({
        ...state,
        if (serial != _selectionSerial) 'index': _selectedIndex,
      });
      notifyListeners();
    } on MissingPluginException {
      // Non-Android previews use the in-memory defaults.
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    }
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= _wallpapers.length) return;
    final serial = ++_selectionSerial;
    unawaited(ensureMainPreview(index));
    // Update the UI first, then let Android confirm the real current index.
    _setSelectedIndex(index);
    await _runNative(() async {
      final selected = await _bridge.setCurrent(index);
      if (serial == _selectionSerial &&
          selected != null &&
          selected >= 0 &&
          selected < _wallpapers.length) {
        _setSelectedIndex(selected);
      }
    });
  }

  // Fetches a missing large preview once without blocking wallpaper selection.
  Future<void> ensureMainPreview(int index) {
    if (_disposed || index < 0 || index >= _wallpapers.length) {
      return Future.value();
    }
    final wallpaper = _wallpapers[index];
    if (!wallpaper.isUserImage || wallpaper.mainPreview != null) {
      return Future.value();
    }
    final load = _mainPreviewLoads.putIfAbsent(
      wallpaper.id,
      () => _loadMainPreview(wallpaper.id),
    );
    if (_failedMainPreviews.remove(wallpaper.id)) notifyListeners();
    return load;
  }

  Future<void> _loadMainPreview(String wallpaperId) async {
    try {
      Uint8List? bytes;
      try {
        bytes = await Future<Uint8List?>.sync(
          () => _bridge.mainPreview(wallpaperId),
        );
      } catch (_) {
        // A failed native request is a completed failure, not an ongoing load.
      }
      if (_disposed) return;
      final index = _wallpapers.indexWhere((item) => item.id == wallpaperId);
      if (index < 0 || _wallpapers[index].mainPreview != null) return;
      if (bytes == null || bytes.isEmpty) {
        _failedMainPreviews.add(wallpaperId);
      } else {
        _failedMainPreviews.remove(wallpaperId);
        _wallpapers[index] = _wallpapers[index].copyWith(mainPreview: bytes);
      }
      notifyListeners();
    } finally {
      _mainPreviewLoads.remove(wallpaperId);
    }
  }

  // Loads the larger full-aspect source only when the crop editor needs it.
  Future<void> ensureEditorPreview(int index) {
    if (index < 0 || index >= _wallpapers.length) return Future.value();
    final wallpaper = _wallpapers[index];
    if (!wallpaper.isUserImage || wallpaper.preview != null) {
      return Future.value();
    }
    return _editorPreviewLoads.putIfAbsent(
      wallpaper.id,
      () => _loadEditorPreview(wallpaper.id),
    );
  }

  Future<void> _loadEditorPreview(String wallpaperId) async {
    try {
      final bytes = await _bridge.editorPreview(wallpaperId);
      if (bytes == null || bytes.isEmpty || _disposed) return;
      final index = _wallpapers.indexWhere((item) => item.id == wallpaperId);
      if (index < 0 || _wallpapers[index].preview != null) return;
      _wallpapers[index] = _wallpapers[index].copyWith(preview: bytes);
      notifyListeners();
    } on MissingPluginException {
      // Sample/non-Android builds do not have native preview generation.
    } on PlatformException {
      // The editor reports an unavailable source without changing saved data.
    } catch (_) {
      // Damaged sources use the editor's unavailable-preview state.
    } finally {
      _editorPreviewLoads.remove(wallpaperId);
    }
  }

  // Saves a crop in the app and sends the same position to Android.
  Future<bool> updateCrop(
    int index,
    WallpaperCrop crop, {
    WallpaperDisplayMode? displayMode,
    Color? fitBackgroundColor,
    int rotationQuarterTurns = 0,
  }) async {
    if (index < 0 || index >= _wallpapers.length) return false;
    final selectedMode = displayMode ?? _wallpapers[index].displayMode;
    final selectedFitColor =
        fitBackgroundColor ?? _wallpapers[index].fitBackgroundColor;
    var saved = false;
    await _runNative(() async {
      final updated = _wallpaperFromNative(
        await _bridge.updateCrop(
          index: index,
          scale: crop.scale,
          offsetX: crop.offsetX,
          offsetY: crop.offsetY,
          displayMode: selectedMode.name,
          fitBackgroundColor: selectedFitColor.toARGB32(),
          rotationQuarterTurns: rotationQuarterTurns,
        ),
      );
      if (updated != null) {
        _failedMainPreviews.remove(updated.id);
        _wallpapers[index] = updated;
        saved = true;
        notifyListeners();
      } else {
        throw StateError('WakeWall did not return the updated wallpaper.');
      }
    });
    return saved;
  }

  Future<void> next() async {
    if (_wallpapers.isEmpty) return;
    final serial = ++_selectionSerial;
    // Sequential next is predictable; shuffle must wait for Android's actual choice.
    if (_order == RotationOrder.sequential) {
      _setSelectedIndex((_selectedIndex + 1) % _wallpapers.length);
      unawaited(ensureMainPreview(_selectedIndex));
    }
    await _runNative(() async {
      final next = await _bridge.showNext();
      if (!_disposed &&
          serial == _selectionSerial &&
          next != null &&
          hasWallpapers) {
        _setSelectedIndex(next % _wallpapers.length);
        unawaited(ensureMainPreview(_selectedIndex));
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

  Future<void> revealImportedAlbumSelection(
    Set<String> assignedAlbumIds,
  ) async {
    // If the new wallpaper would be hidden by the active filters, reveal All Wallpapers.
    if (_activeAlbumIds.isEmpty) return;
    if (assignedAlbumIds.isEmpty) {
      await setActiveAlbums({});
      return;
    }
    if (assignedAlbumIds.any(_activeAlbumIds.contains)) return;
    await setActiveAlbums({});
  }

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
    // Most settings return a complete native state, so this shared path applies it.
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
        // Some providers expose bytes Flutter can decode even when Android cannot.
        for (final value in failedImages) {
          final data = Map<Object?, Object?>.from(value! as Map);
          final normalized = await compute(_normalizeFailedImage, {
            'name': data['name'] as String? ?? 'Photo',
            'bytes': data['bytes'] as Uint8List,
            'maxEdge': _ultraHighResolutionMode ? null : 8192,
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

  Future<void> setThemeMode(WakeWallThemeMode value) async {
    _themeMode = value;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setWallpaperScrolling(bool value) async {
    _wallpaperScrolling = value;
    notifyListeners();
    await _syncSettings();
  }

  Future<void> setUltraHighResolutionMode(bool value) async {
    _ultraHighResolutionMode = value;
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
        themeMode: _themeMode.name,
        wallpaperScrolling: _wallpaperScrolling,
        ultraHighResolutionMode: _ultraHighResolutionMode,
      ),
    );
  }

  Future<String?> _runFileAction(
    Future<Map<String, Object?>> Function() action, {
    bool applyResult = false,
    VoidCallback? onOperationStarted,
  }) async {
    // Backup and restore launch Android file pickers, so progress starts later.
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
    if (_disposed) return;
    final savedWallpaperCount = (configuration['wallpaperCount'] as num?)
        ?.toInt();
    if (savedWallpaperCount != null) {
      _knownWallpaperCount = math.max(0, savedWallpaperCount);
    }
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
    _ultraHighResolutionMode =
        configuration['ultraHighResolutionMode'] as bool? ??
        _ultraHighResolutionMode;
    final savedThemeMode = configuration['themeMode'] as String?;
    if (savedThemeMode != null) {
      _themeMode = WakeWallThemeMode.values.firstWhere(
        (mode) => mode.name == savedThemeMode,
        orElse: () => WakeWallThemeMode.system,
      );
    }
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
      final existingById = {for (final item in _wallpapers) item.id: item};
      final restored = <Wallpaper>[];
      for (final value in savedWallpapers) {
        final wallpaper = _wallpaperFromNative(value);
        if (wallpaper == null) continue;
        final existing = existingById[wallpaper.id];
        restored.add(
          wallpaper.copyWith(
            thumbnail: wallpaper.thumbnail ?? existing?.thumbnail,
            mainPreview: wallpaper.mainPreview ?? existing?.mainPreview,
            preview: wallpaper.preview ?? existing?.preview,
          ),
        );
      }
      _wallpapers
        ..clear()
        ..addAll(restored);
      final missingPreviewIds = restored
          .where((wallpaper) => wallpaper.mainPreview == null)
          .map((wallpaper) => wallpaper.id)
          .toSet();
      _failedMainPreviews.retainAll(missingPreviewIds);
      _knownWallpaperCount = _wallpapers.length;
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
    if (_disposed) return;
    final normalized = _wallpapers.isEmpty ? 0 : index % _wallpapers.length;
    _selectedIndex = normalized;
    if (_selectedIndexNotifier.value != normalized) {
      _selectedIndexNotifier.value = normalized;
    }
    // Startup, resume, and album changes can select a photo without a thumbnail tap.
    if (!mainPreviewFailed(selectedWallpaper?.id ?? '')) {
      unawaited(ensureMainPreview(normalized));
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
    _knownWallpaperCount = _wallpapers.length;
  }

  Wallpaper? _wallpaperFromNative(Object? value) {
    if (value is! Map) return null;
    final data = Map<Object?, Object?>.from(value);
    // Native sends compact maps so Flutter never receives the full original image.
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
    if (_disposed) return;
    try {
      _lastNativeError = null;
      await action();
    } on MissingPluginException {
      _lastNativeError = 'Native wallpaper controls require Android.';
      notifyListeners();
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
      notifyListeners();
    } catch (_) {
      _lastNativeError = 'WakeWall could not complete that action.';
      notifyListeners();
    }
  }

  // Native operations cannot be cancelled, but late completions must not notify dead widgets.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
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

// Rewrites photos Android cannot decode into a clean, capped JPEG on an isolate.
Map<String, Object?>? _normalizeFailedImage(Map<String, Object?> value) {
  try {
    final decoded = image.decodeImage(value['bytes']! as Uint8List);
    if (decoded == null) return null;
    var normalized = image.bakeOrientation(decoded);
    final maxEdge = value['maxEdge'] as int?;
    if (maxEdge != null &&
        (normalized.width > maxEdge || normalized.height > maxEdge)) {
      if (normalized.width >= normalized.height) {
        normalized = image.copyResize(normalized, width: maxEdge);
      } else {
        normalized = image.copyResize(normalized, height: maxEdge);
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
