package com.zambl.wakewall

import android.app.WallpaperManager
import android.content.ComponentName
import android.content.Intent
import android.net.Uri
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.zambl.wakewall/control"
    private var pendingImageResult: MethodChannel.Result? = null
    private val imagePicker = registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris ->
        handlePickedImages(uris)
    }

    // Connects Flutter's controls to the Android wallpaper service.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> pickImages(result)
                    "importNormalizedImages" -> {
                        val images = call.argument<List<Map<String, Any>>>("images").orEmpty()
                            .mapNotNull { image ->
                                val name = image["name"] as? String ?: return@mapNotNull null
                                val bytes = image["bytes"] as? ByteArray ?: return@mapNotNull null
                                NormalizedImport(name, bytes)
                            }
                        val store = WakeWallStore(this)
                        val imported = store.addNormalizedImages(images)
                        notifyWallpaperService()
                        result.success(
                            store.configuration().toMutableMap().apply {
                                put("normalizedImportedCount", imported)
                                put("normalizedFailedCount", images.size - imported)
                            }
                        )
                    }
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
                        result.success(null)
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

    private fun handlePickedImages(uris: List<Uri>) {
        uris.forEach { uri ->
            runCatching {
                contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        val store = WakeWallStore(this)
        val summary = store.addImages(uris)
        notifyWallpaperService()
        pendingImageResult?.success(
            store.configuration().toMutableMap().apply {
                put("importedCount", summary.imported)
                put("failedCount", summary.failed)
                put(
                    "failedImages",
                    summary.failedImports.map {
                        mapOf(
                            "name" to it.name,
                            "bytes" to it.bytes,
                            "diagnostics" to it.diagnostics,
                        )
                    },
                )
                put(
                    "failedWithoutBytesCount",
                    summary.failed - summary.failedImports.size,
                )
            }
        )
        pendingImageResult = null
    }

    private fun pickImages(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("picker_open", "The image picker is already open.", null)
            return
        }
        pendingImageResult = result
        imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
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
}
