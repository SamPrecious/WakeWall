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
import java.util.concurrent.Executors

class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.zambl.wakewall/control"
    private lateinit var controlChannel: MethodChannel
    private var pendingImageResult: MethodChannel.Result? = null
    private var pendingBackupResult: MethodChannel.Result? = null
    private var pendingRestoreResult: MethodChannel.Result? = null
    private val imagePicker = registerForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(),
    ) { uris ->
        handlePickedImages(uris)
    }
    private val documentImagePicker = registerForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        handlePickedImages(uris)
    }
    private val backupFilePicker = registerForActivityResult(
        ActivityResultContracts.CreateDocument("application/zip"),
    ) { uri ->
        handleBackupLocation(uri)
    }
    private val restoreFilePicker = registerForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        handleRestoreFile(uri)
    }

    // Connects Flutter's controls to the Android wallpaper service.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        controlChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        controlChannel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> pickImages(result)
                    "pickImagesFromFiles" -> pickImagesFromFiles(result)
                    "backup" -> createBackup(result)
                    "restore" -> restoreBackup(result)
                    "importNormalizedImages" -> {
                        val images = call.argument<List<Map<String, Any>>>("images").orEmpty()
                            .mapNotNull { image ->
                                val name = image["name"] as? String ?: return@mapNotNull null
                                val bytes = image["bytes"] as? ByteArray ?: return@mapNotNull null
                                NormalizedImport(name, bytes)
                            }
                        runInBackground(result) {
                            val store = WakeWallStore(this)
                            val imported = store.addNormalizedImages(images)
                            notifyWallpaperService()
                            store.state().toMutableMap().apply {
                                put("addedWallpapers", store.wallpaperMaps(imported))
                                put("normalizedImportedCount", imported.size)
                                put("normalizedFailedCount", images.size - imported.size)
                            }
                        }
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
                        val index = call.argument<Int>("index") ?: -1
                        runInBackground(result) {
                            val store = WakeWallStore(this)
                            store.removeWallpaper(index)
                            notifyWallpaperService()
                            store.configuration()
                        }
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

                    "updatePhotoSource" -> {
                        WakeWallStore(this).updatePhotoSource(
                            call.argument<String>("source") ?: "askEveryTime",
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

                    "configuration" -> runInBackground(result) {
                        WakeWallStore(this).configuration()
                    }
                    "state" -> result.success(WakeWallStore(this).state())
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
        val result = pendingImageResult
        pendingImageResult = null
        if (result == null) return
        if (uris.isEmpty()) {
            result.success(mapOf("cancelled" to true))
            return
        }
        controlChannel.invokeMethod("imageImportStarted", null)
        runInBackground(result) {
            val store = WakeWallStore(this)
            val summary = store.addImages(uris)
            notifyWallpaperService()
            store.state().toMutableMap().apply {
                put("addedWallpapers", store.wallpaperMaps(summary.importedValues))
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
        }
    }

    private fun pickImages(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("picker_open", "The image picker is already open.", null)
            return
        }
        pendingImageResult = result
        imagePicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
    }

    // Opens Android's document providers for Gallery, Downloads, and file apps.
    private fun pickImagesFromFiles(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("picker_open", "The image picker is already open.", null)
            return
        }
        pendingImageResult = result
        documentImagePicker.launch(arrayOf("image/*"))
    }

    private fun createBackup(result: MethodChannel.Result) {
        if (pendingBackupResult != null) {
            result.error("backup_open", "A backup save screen is already open.", null)
            return
        }
        pendingBackupResult = result
        backupFilePicker.launch("WakeWall-backup.wakewall")
    }

    private fun restoreBackup(result: MethodChannel.Result) {
        if (pendingRestoreResult != null) {
            result.error("restore_open", "A restore screen is already open.", null)
            return
        }
        pendingRestoreResult = result
        restoreFilePicker.launch(arrayOf("application/zip", "application/octet-stream", "*/*"))
    }

    private fun handleBackupLocation(uri: Uri?) {
        val result = pendingBackupResult ?: return
        pendingBackupResult = null
        if (uri == null) {
            result.success(mapOf("cancelled" to true))
            return
        }
        controlChannel.invokeMethod("fileOperationStarted", null)
        runInBackground(result) {
            contentResolver.openOutputStream(uri, "w")?.use { WakeWallStore(this).writeBackup(it) }
                ?: error("WakeWall could not create the backup file.")
            mapOf("message" to "Backup saved.")
        }
    }

    private fun handleRestoreFile(uri: Uri?) {
        val result = pendingRestoreResult ?: return
        pendingRestoreResult = null
        if (uri == null) {
            result.success(mapOf("cancelled" to true))
            return
        }
        controlChannel.invokeMethod("fileOperationStarted", null)
        runInBackground(result) {
            val store = WakeWallStore(this)
            contentResolver.openInputStream(uri)?.use(store::restoreBackup)
                ?: error("WakeWall could not open the backup file.")
            notifyWallpaperService()
            store.configuration().toMutableMap().apply {
                put("message", "Backup restored.")
            }
        }
    }

    private fun notifyWallpaperService() {
        sendBroadcast(Intent(WakeWallService.ACTION_CONFIGURATION_UPDATED).setPackage(packageName))
    }

    // Keeps image decoding and preview loading away from Android's screen thread.
    private fun runInBackground(result: MethodChannel.Result, action: () -> Any?) {
        backgroundExecutor.execute {
            runCatching(action).fold(
                onSuccess = { value -> runOnUiThread { result.success(value) } },
                onFailure = { error ->
                    runOnUiThread {
                        result.error("native_error", error.message ?: "WakeWall could not finish the task.", null)
                    }
                },
            )
        }
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
        private val backgroundExecutor = Executors.newSingleThreadExecutor()
    }
}
