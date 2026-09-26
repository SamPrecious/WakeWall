package com.sprecious.wakewall

import android.content.Context
import android.graphics.Bitmap
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import org.robolectric.util.ReflectionHelpers
import org.robolectric.util.ReflectionHelpers.ClassParameter.from
import java.io.ByteArrayOutputStream
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class WakeWallStoreTest {
    private lateinit var context: Context
    private lateinit var store: WakeWallStore

    @Before fun setUp() {
        context = RuntimeEnvironment.getApplication()
        context.getSharedPreferences("wakewall", Context.MODE_PRIVATE).edit().clear()
            .putString("wallpapers", "[\"sample:0\",\"sample:1\",\"sample:2\"]")
            .putBoolean("shuffle", false).commit()
        store = WakeWallStore(context)
    }

    @Test fun storageKeysRemainIdenticalToExistingCacheNames() {
        for (value in listOf("local:photo.image", "content://media/images/123", "sample:0")) {
            val expected = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
                .joinToString("") { "%02x".format(it) }
            val actual = ReflectionHelpers.callInstanceMethod<String>(store, "storageKey", from(String::class.java, value))
            assertEquals(expected, actual)
        }
    }

    @Test fun failedRotationLeavesCropAndModeUnchanged() {
        context.getSharedPreferences("wakewall", Context.MODE_PRIVATE).edit()
            .putString("wallpapers", "[\"local:missing.image\"]").commit()
        store.refreshActiveWallpapers()
        store.setCrop(0, 1.25, 0.0, 0.0, "fit", 0xff123456.toInt())
        assertThrows(IllegalStateException::class.java) {
            store.setCrop(0, 2.0, 0.3, 0.2, "blur", 0xffabcdef.toInt(), 1)
        }
        assertEquals(1.25f, store.crop(0).scale)
        assertEquals("fit", store.displayMode(0))
        assertEquals(0xff123456.toInt(), store.fitBackgroundColor(0))
    }

    @Test fun screenOffDoesNotWaitForStorageTransactionsAndEnginesAdvanceOnlyOnce() {
        val executor = Executors.newSingleThreadExecutor()
        val locked = CountDownLatch(1)
        val release = CountDownLatch(1)
        try {
            val task = executor.submit {
                WakeWallTransactionStore(context.getSharedPreferences("wakewall", Context.MODE_PRIVATE)).locked {
                    locked.countDown()
                    check(release.await(10, TimeUnit.SECONDS))
                }
            }
            assertTrue(locked.await(5, TimeUnit.SECONDS))
            val rotation = Executors.newSingleThreadExecutor()
            try {
                assertEquals(1, rotation.submit<Int> { store.advanceForScreenOff(0) }.get(2, TimeUnit.SECONDS))
                assertEquals(1, WakeWallStore(context).advanceForScreenOff(0))
                assertEquals(2, store.advanceForScreenOff(1))
            } finally {
                rotation.shutdownNow()
            }
            release.countDown()
            task.get(5, TimeUnit.SECONDS)
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test fun cleanupSkipsLiveCacheWritersButRemovesAbandonedTemporaryFiles() {
        val fileStore = WakeWallFileStore(context, { listOf("local:photo.image") }, { emptySet() },
            { emptySet() }, {}, { "stablekey" }, {})
        val directory = File(context.cacheDir, "wallpaper_previews").apply { mkdirs() }
        val temporary = File(directory, "stablekey_main_crop_v3.jpg.tmp")
        val ready = CountDownLatch(1)
        val release = CountDownLatch(1)
        val executor = Executors.newSingleThreadExecutor()
        try {
            val writer = executor.submit {
                fileStore.withPreviewLock("local:photo.image") {
                    temporary.writeText("writing")
                    ready.countDown()
                    check(release.await(10, TimeUnit.SECONDS))
                }
            }
            assertTrue(ready.await(5, TimeUnit.SECONDS))
            fileStore.cleanupOrphanedFiles()
            assertTrue(temporary.isFile)
            release.countDown()
            writer.get(5, TimeUnit.SECONDS)
            fileStore.cleanupOrphanedFiles()
            assertFalse(temporary.exists())
        } finally {
            release.countDown()
            executor.shutdownNow()
        }
    }

    @Test fun missingRenderDoesNotEraseUsableDirectBootFrame() {
        val bootContext = context.createDeviceProtectedStorageContext()
        val file = File(bootContext.filesDir, "boot_frame/current.jpg")
        file.parentFile!!.mkdirs()
        file.writeBytes(byteArrayOf(1, 2, 3))
        val bootStore = WakeWallBootFrameStore(context)
        assertFalse(bootStore.saveFrom(null))
        assertArrayEquals(byteArrayOf(1, 2, 3), bootStore.frameFile()!!.readBytes())
        bootStore.clear()
        assertNull(bootStore.frameFile())
    }

    @Test fun damagedImageBackupIsRejectedBeforeReplacingCollection() {
        val png = ByteArrayOutputStream().use { output ->
            val bitmap = Bitmap.createBitmap(20, 30, Bitmap.Config.ARGB_8888)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
            bitmap.recycle()
            output.toByteArray()
        }
        val broken = png.copyOf(41) // Retain dimensions but omit the encoded pixel stream.
        val before = store.wallpapers
        val manifest = JSONObject().put("format", "com.zambl.wakewall.backup").put("version", 3)
            .put("albums", JSONArray()).put("activeAlbumIds", JSONArray())
            .put("defaultImportAlbumIds", JSONArray()).put("wallpapers", JSONArray().put(
                JSONObject().put("file", "images/0.image").put("albumIds", JSONArray()),
            ))
        val backup = ByteArrayOutputStream().use { output ->
            ZipOutputStream(output).use { zip ->
                zip.putNextEntry(ZipEntry("manifest.json"))
                zip.write(manifest.toString().toByteArray())
                zip.closeEntry()
                zip.putNextEntry(ZipEntry("images/0.image"))
                zip.write(broken)
                zip.closeEntry()
            }
            output.toByteArray()
        }
        val error = assertThrows(IllegalArgumentException::class.java) { store.restoreBackup(backup.inputStream()) }
        assertEquals("A wallpaper in this backup is damaged.", error.message)
        assertEquals(before, store.wallpapers)
    }
}
