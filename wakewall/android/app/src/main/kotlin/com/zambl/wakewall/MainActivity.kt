package com.zambl.wakewall

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.zambl.wakewall/control"
    private var pendingImageResult: MethodChannel.Result? = null

    // Connects Flutter's controls to the Android wallpaper service.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> pickImages(result)
                    "openWallpaperPicker" -> {
                        openWallpaperPicker()
                        result.success(null)
                    }

                    "showNext" -> {
                        val store = WakeWallStore(this)
                        val next = store.advance("manual")
                        sendBroadcast(
                            Intent(WakeWallService.ACTION_CONFIGURATION_UPDATED).setPackage(packageName)
                        )
                        result.success(next)
                    }

                    "setCurrent" -> {
                        val index = call.argument<Int>("index") ?: 0
                        WakeWallStore(this).commitIndex(index, "manual_select")
                        sendBroadcast(
                            Intent(WakeWallService.ACTION_CONFIGURATION_UPDATED).setPackage(packageName)
                        )
                        result.success(index)
                    }

                    "removeWallpaper" -> {
                        val store = WakeWallStore(this)
                        store.removeWallpaper(call.argument<Int>("index") ?: -1)
                        notifyWallpaperService()
                        result.success(store.configuration())
                    }

                    "moveWallpaper" -> {
                        val store = WakeWallStore(this)
                        store.moveWallpaper(
                            call.argument<Int>("oldIndex") ?: -1,
                            call.argument<Int>("newIndex") ?: -1,
                        )
                        notifyWallpaperService()
                        result.success(store.configuration())
                    }

                    "updateSettings" -> {
                        val store = WakeWallStore(this)
                        store.updateSettings(
                            paused = call.argument<Boolean>("paused") ?: false,
                            shuffle = call.argument<Boolean>("shuffle") ?: false,
                            fit = call.argument<String>("fit") ?: "cropToFill",
                        )
                        sendBroadcast(
                            Intent(WakeWallService.ACTION_CONFIGURATION_UPDATED).setPackage(packageName)
                        )
                        result.success(null)
                    }

                    "updateCrop" -> {
                        val index = call.argument<Int>("index") ?: 0
                        WakeWallStore(this).setCrop(
                            index = index,
                            scale = call.argument<Double>("scale") ?: 1.0,
                            offsetX = call.argument<Double>("offsetX") ?: 0.0,
                            offsetY = call.argument<Double>("offsetY") ?: 0.0,
                        )
                        sendBroadcast(Intent(WakeWallService.ACTION_CROP_UPDATED).setPackage(packageName))
                        result.success(null)
                    }

                    "configuration" -> result.success(WakeWallStore(this).configuration())
                    "diagnostics" -> result.success(WakeWallStore(this).diagnostics())
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != PICK_IMAGES_REQUEST) return

        val uris = mutableListOf<Uri>()
        data?.data?.let(uris::add)
        data?.clipData?.let { clip ->
            repeat(clip.itemCount) { uris.add(clip.getItemAt(it).uri) }
        }
        uris.forEach { uri ->
            runCatching {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val store = WakeWallStore(this)
        store.addImages(uris)
        notifyWallpaperService()
        pendingImageResult?.success(store.configuration())
        pendingImageResult = null
    }

    private fun pickImages(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("picker_open", "The image picker is already open.", null)
            return
        }
        pendingImageResult = result
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Intent(MediaStore.ACTION_PICK_IMAGES).apply {
                type = "image/*"
                putExtra(
                    MediaStore.EXTRA_PICK_IMAGES_MAX,
                    MediaStore.getPickImagesMaxLimit().coerceAtMost(50),
                )
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        } else {
            Intent(Intent.ACTION_PICK, MediaStore.Images.Media.EXTERNAL_CONTENT_URI).apply {
                type = "image/*"
                putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        startActivityForResult(intent, PICK_IMAGES_REQUEST)
    }

    private fun notifyWallpaperService() {
        sendBroadcast(Intent(WakeWallService.ACTION_CONFIGURATION_UPDATED).setPackage(packageName))
    }

    private fun openWallpaperPicker() {
        val component = ComponentName(this, WakeWallService::class.java)
        val directIntent = Intent(WallpaperManager.ACTION_CHANGE_LIVE_WALLPAPER).apply {
            putExtra(WallpaperManager.EXTRA_LIVE_WALLPAPER_COMPONENT, component)
        }
        try {
            startActivity(directIntent)
        } catch (_: Exception) {
            startActivity(Intent(WallpaperManager.ACTION_LIVE_WALLPAPER_CHOOSER))
        }
    }

    companion object {
        private const val PICK_IMAGES_REQUEST = 4401
    }
}
