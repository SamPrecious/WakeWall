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

  int _selectedIndex = 0;
  bool _paused = false;
  RotationOrder _order = RotationOrder.shuffle;
  WallpaperFit _fit = WallpaperFit.cropToFill;
  String? _lastNativeError;

  List<Wallpaper> get wallpapers => List.unmodifiable(_wallpapers);
  int get selectedIndex => _selectedIndex;
  bool get hasWallpapers => _wallpapers.isNotEmpty;
  bool get paused => _paused;
  RotationOrder get order => _order;
  WallpaperFit get fit => _fit;
  Uint8List? get selectedPreview => selectedWallpaper?.preview;
  String? get lastNativeError => _lastNativeError;

  Wallpaper? get selectedWallpaper =>
      hasWallpapers ? _wallpapers[_selectedIndex] : null;

  // Restores the wallpaper service's saved choices when the app opens.
  Future<void> initialize() async {
    try {
      _applyConfiguration(await _bridge.configuration());
      notifyListeners();
    } on MissingPluginException {
      // Non-Android previews use the in-memory defaults.
    } on PlatformException catch (error) {
      _lastNativeError = error.message ?? error.code;
    }
  }

  Future<void> select(int index) async {
    if (index < 0 || index >= _wallpapers.length) return;
    _selectedIndex = index;
    notifyListeners();
    await _runNative(() async {
      final selected = await _bridge.setCurrent(index);
      if (selected != null && selected >= 0 && selected < _wallpapers.length) {
        _selectedIndex = selected;
        notifyListeners();
      }
    });
  }

  // Saves a crop in the app and sends the same position to Android.
  Future<void> updateCrop(int index, WallpaperCrop crop) async {
    if (index < 0 || index >= _wallpapers.length) return;
    _wallpapers[index] = _wallpapers[index].copyWith(crop: crop);
    notifyListeners();
    await _runNative(
      () => _bridge.updateCrop(
        index: index,
        scale: crop.scale,
        offsetX: crop.offsetX,
        offsetY: crop.offsetY,
      ),
    );
  }

  Future<void> next() async {
    if (_wallpapers.isEmpty) return;
    _selectedIndex = (_selectedIndex + 1) % _wallpapers.length;
    notifyListeners();
    await _runNative(() async {
      final next = await _bridge.showNext();
      if (next != null) {
        _selectedIndex = next % _wallpapers.length;
        notifyListeners();
      }
    });
  }

  Future<void> addImages() async {
    await _importImages(_bridge.pickImages);
  }

  Future<void> _importImages(
    Future<Map<String, Object?>> Function() picker,
  ) async {
    await _runNative(() async {
      final configuration = await picker();
      _applyConfiguration(configuration);
      final failedImages =
          configuration['failedImages'] as List<Object?>? ?? const [];
      final failedWithoutBytes =
          (configuration['failedWithoutBytesCount'] as num?)?.toInt() ?? 0;
      final normalized = await Future.wait(
        failedImages.map((value) {
          final data = Map<Object?, Object?>.from(value! as Map);
          return compute(_normalizeFailedImage, {
            'name': data['name'] as String? ?? 'Photo',
            'bytes': data['bytes'] as Uint8List,
          });
        }),
      );
      final recovered = normalized.whereType<Map<String, Object?>>().toList();
      var storedRecovered = 0;
      if (recovered.isNotEmpty) {
        final recoveredConfiguration = await _bridge.importNormalizedImages(
          recovered,
        );
        storedRecovered =
            (recoveredConfiguration['normalizedImportedCount'] as num?)
                ?.toInt() ??
            0;
        _applyConfiguration(recoveredConfiguration);
      }
      final failed = failedWithoutBytes + failedImages.length - storedRecovered;
      if (failed > 0) {
        _lastNativeError = failed == 1
            ? 'One photo could not be imported.'
            : '$failed photos could not be imported.';
      }
      notifyListeners();
    });
  }

  Future<void> removeAt(int index) async {
    if (index < 0 || index >= _wallpapers.length) return;
    await _runNative(() async {
      _applyConfiguration(await _bridge.removeWallpaper(index));
      notifyListeners();
    });
  }

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
    _selectedIndex = selectedId == null
        ? 0
        : _wallpapers.indexWhere((wallpaper) => wallpaper.id == selectedId);
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

  Future<void> openWallpaperPicker() => _runNative(_bridge.openWallpaperPicker);

  Future<Map<String, Object?>> diagnostics() async {
    try {
      return await _bridge.diagnostics();
    } on MissingPluginException {
      return {'status': 'Native controls are available on Android builds.'};
    } on PlatformException catch (error) {
      return {'status': error.message ?? error.code};
    }
  }

  Future<void> _syncSettings() {
    return _runNative(
      () => _bridge.updateSettings(
        paused: _paused,
        shuffle: _order == RotationOrder.shuffle,
        fit: _fit.name,
      ),
    );
  }

  // Rebuilds the Flutter list from Android's saved wallpaper collection.
  void _applyConfiguration(Map<String, Object?> configuration) {
    _paused = configuration['paused'] as bool? ?? _paused;
    _order = configuration['shuffle'] == true
        ? RotationOrder.shuffle
        : RotationOrder.sequential;
    _fit = configuration['fit'] == WallpaperFit.fitEntireImage.name
        ? WallpaperFit.fitEntireImage
        : WallpaperFit.cropToFill;

    final savedWallpapers =
        configuration['wallpapers'] as List<Object?>? ?? const [];
    if (savedWallpapers.isNotEmpty || configuration.containsKey('wallpapers')) {
      _wallpapers
        ..clear()
        ..addAll(savedWallpapers.map(_wallpaperFromNative));
    }
    final savedIndex = (configuration['index'] as num?)?.toInt() ?? 0;
    _selectedIndex = _wallpapers.isEmpty ? 0 : savedIndex % _wallpapers.length;
  }

  Wallpaper _wallpaperFromNative(Object? value) {
    final data = Map<Object?, Object?>.from(value! as Map);
    final sampleIndex = (data['sampleIndex'] as num?)?.toInt();
    final cropData = Map<Object?, Object?>.from(data['crop']! as Map);
    final crop = WallpaperCrop(
      scale: (cropData['scale'] as num?)?.toDouble() ?? 1,
      offsetX: (cropData['offsetX'] as num?)?.toDouble() ?? 0,
      offsetY: (cropData['offsetY'] as num?)?.toDouble() ?? 0,
    );
    if (sampleIndex != null) {
      return bundledWallpapers[sampleIndex % bundledWallpapers.length].copyWith(
        crop: crop,
      );
    }
    return Wallpaper(
      id: data['uri']! as String,
      name: data['name'] as String? ?? 'Photo',
      palette: const [Color(0xFF202124), Color(0xFF303134), Color(0xFF8AB4F8)],
      style: 0,
      uri: data['uri']! as String,
      thumbnail: data['thumbnail'] as Uint8List?,
      preview: data['preview'] as Uint8List?,
      imageWidth: (data['imageWidth'] as num?)?.toInt(),
      imageHeight: (data['imageHeight'] as num?)?.toInt(),
      crop: crop,
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
}

// Rewrites photos Android cannot decode into a clean, standard JPEG.
Map<String, Object?>? _normalizeFailedImage(Map<String, Object?> value) {
  try {
    final decoded = image.decodeImage(value['bytes']! as Uint8List);
    if (decoded == null) return null;
    var normalized = image.bakeOrientation(decoded);
    if (normalized.width > 4096 || normalized.height > 4096) {
      if (normalized.width >= normalized.height) {
        normalized = image.copyResize(normalized, width: 4096);
      } else {
        normalized = image.copyResize(normalized, height: 4096);
      }
    }
    return {
      'name': value['name']! as String,
      'bytes': Uint8List.fromList(image.encodeJpg(normalized, quality: 94)),
    };
  } catch (_) {
    return null;
  }
}
