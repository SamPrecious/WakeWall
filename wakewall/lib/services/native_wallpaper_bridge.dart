import 'package:flutter/services.dart';

class NativeWallpaperBridge {
  static const _channel = MethodChannel('com.zambl.wakewall/control');

  Future<void> openWallpaperPicker() async {
    await _channel.invokeMethod<void>('openWallpaperPicker');
  }

  Future<int?> showNext() async {
    return _channel.invokeMethod<int>('showNext');
  }

  Future<int?> setCurrent(int index) async {
    return _channel.invokeMethod<int>('setCurrent', {'index': index});
  }

  Future<Map<String, Object?>> pickImages() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickImages',
    );
    return result ?? const {};
  }

  Future<Map<String, Object?>> importNormalizedImages(
    List<Map<String, Object?>> images,
  ) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'importNormalizedImages',
      {'images': images},
    );
    return result ?? const {};
  }

  Future<Map<String, Object?>> removeWallpaper(int index) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'removeWallpaper',
      {'index': index},
    );
    return result ?? const {};
  }

  Future<void> moveWallpaper(int oldIndex, int newIndex) async {
    await _channel.invokeMethod<void>('moveWallpaper', {
      'oldIndex': oldIndex,
      'newIndex': newIndex,
    });
  }

  Future<void> updateSettings({
    required bool paused,
    required bool shuffle,
    required String fit,
  }) async {
    await _channel.invokeMethod<void>('updateSettings', {
      'paused': paused,
      'shuffle': shuffle,
      'fit': fit,
    });
  }

  Future<void> updateCrop({
    required int index,
    required double scale,
    required double offsetX,
    required double offsetY,
  }) async {
    await _channel.invokeMethod<void>('updateCrop', {
      'index': index,
      'scale': scale,
      'offsetX': offsetX,
      'offsetY': offsetY,
    });
  }

  Future<Map<String, Object?>> configuration() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'configuration',
    );
    return result ?? const {};
  }

  Future<Map<String, Object?>> diagnostics() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'diagnostics',
    );
    return result ?? const {};
  }
}
