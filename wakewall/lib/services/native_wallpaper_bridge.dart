import 'package:flutter/services.dart';

class NativeWallpaperBridge {
  static const _channel = MethodChannel('com.zambl.wakewall/control');
  VoidCallback? _onImageImportStarted;
  VoidCallback? _onFileOperationStarted;

  void setImageImportStartedListener(VoidCallback? listener) {
    _onImageImportStarted = listener;
    if (listener != null) _installCallbackHandler();
  }

  void setFileOperationStartedListener(VoidCallback? listener) {
    _onFileOperationStarted = listener;
    if (listener != null) _installCallbackHandler();
  }

  void _installCallbackHandler() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'imageImportStarted':
          _onImageImportStarted?.call();
        case 'fileOperationStarted':
          _onFileOperationStarted?.call();
      }
    });
  }

  Future<void> openWallpaperPicker() async {
    await _channel.invokeMethod<void>('openWallpaperPicker');
  }

  Future<bool> claimWallpaperSetupOffer() async {
    return await _channel.invokeMethod<bool>('claimWallpaperSetupOffer') ??
        false;
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

  Future<Map<String, Object?>> pickImagesFromFiles() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'pickImagesFromFiles',
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

  Future<Map<String, Object?>> backup() async {
    final result = await _channel.invokeMapMethod<String, Object?>('backup');
    return result ?? const {};
  }

  Future<Map<String, Object?>> restore() async {
    final result = await _channel.invokeMapMethod<String, Object?>('restore');
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

  Future<Map<String, Object?>> updateCrop({
    required int index,
    required double scale,
    required double offsetX,
    required double offsetY,
  }) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'updateCrop',
      {'index': index, 'scale': scale, 'offsetX': offsetX, 'offsetY': offsetY},
    );
    return result ?? const {};
  }

  Future<void> updatePhotoSource(String source) async {
    await _channel.invokeMethod<void>('updatePhotoSource', {'source': source});
  }

  Future<Map<String, Object?>> configuration() async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'configuration',
    );
    return result ?? const {};
  }

  Future<Map<String, Object?>> state() async {
    return Map<String, Object?>.from(
      await _channel.invokeMethod<Map<Object?, Object?>>('state') ?? const {},
    );
  }
}
