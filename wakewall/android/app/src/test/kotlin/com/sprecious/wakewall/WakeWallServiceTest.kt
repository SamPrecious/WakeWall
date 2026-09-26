package com.sprecious.wakewall

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Rect
import android.os.Looper
import android.os.UserManager
import android.view.SurfaceHolder
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.util.ReflectionHelpers
import java.util.concurrent.AbstractExecutorService
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class WakeWallServiceTest {
    private lateinit var service: WakeWallService
    private lateinit var engine: WakeWallService.WakeWallEngine
    private lateinit var store: WakeWallStore
    private lateinit var holder: SurfaceHolder
    private lateinit var executor: ManualExecutor

    @Before fun setUp() {
        service = Robolectric.buildService(WakeWallService::class.java).create().get()
        shadowOf(service.getSystemService(UserManager::class.java)).setUserUnlocked(true)
        service.getSharedPreferences("wakewall", Context.MODE_PRIVATE).edit()
            .putString("wallpapers", "[\"sample:0\",\"sample:1\",\"sample:2\"]")
            .putBoolean("shuffle", false).commit()
        store = spy(WakeWallStore(service))
        engine = mock(WakeWallService.WakeWallEngine::class.java,
            withSettings().useConstructor(service).defaultAnswer(CALLS_REAL_METHODS))
        holder = mock(SurfaceHolder::class.java)
        doReturn(Rect(0, 0, 100, 200)).`when`(holder).surfaceFrame
        doReturn(Canvas(Bitmap.createBitmap(100, 200, Bitmap.Config.ARGB_8888)))
            .`when`(holder).lockHardwareCanvas()
        doReturn(Canvas(Bitmap.createBitmap(100, 200, Bitmap.Config.ARGB_8888)))
            .`when`(holder).lockCanvas()
        doReturn(holder).`when`(engine).surfaceHolder
        doReturn(false).`when`(engine).isPreview
        executor = ManualExecutor()
        ReflectionHelpers.setField(engine, "preparationExecutor", executor)
        ReflectionHelpers.setField(engine, "store\$delegate", lazyOf(store))
        engine.onCreate(holder)
        engine.onSurfaceChanged(holder, 0, 100, 200)
        shadowOf(Looper.getMainLooper()).idle()
    }

    @After fun tearDown() {
        engine.onDestroy()
        while (executor.tasks.isNotEmpty()) executor.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        service.onDestroy()
    }

    @Test fun failedNextFrameDoesNotResubmitUntilAnotherEvent() {
        executor.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        doReturn("local:broken.image").`when`(store).wallpaperAt(1)
        doThrow(OutOfMemoryError("Simulated render memory pressure"))
            .`when`(store).wallpaperRenderFile(1, false)
        executor.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        assertTrue("A failed render must not create an endless allocation loop", executor.tasks.isEmpty())
        engine.onVisibilityChanged(true)
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals("A later lifecycle event can retry", 1, executor.tasks.size)
    }

    @Test fun screenOffCacheMissDefersDecodeAndPostsTheCompletedFrameWhileHidden() {
        doReturn("local:missing.image").`when`(store).wallpaperAt(1)
        clearInvocations(store, holder)
        invoke("handleScreenOff")
        assertEquals(1, store.index)
        verify(store, never()).wallpaperRenderFile(1, false)
        executor.runNext() // Superseded current render.
        shadowOf(Looper.getMainLooper()).idle()
        executor.runNext() // Latest current render.
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(1, ReflectionHelpers.getField<Int>(engine, "currentFrameIndex"))
        verify(holder, atLeastOnce()).unlockCanvasAndPost(any(Canvas::class.java))
    }

    @Test fun preparedScreenOffStillSwitchesOnceWithoutWaitingForAWorker() {
        executor.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        executor.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        val prepared = ReflectionHelpers.getField<Bitmap>(engine, "preparedBitmap")
        invoke("handleScreenOff")
        invoke("handleScreenOff")
        assertEquals(1, store.index)
        assertSame(prepared, ReflectionHelpers.getField<Bitmap>(engine, "currentFrameBitmap"))
    }

    @Test fun resizedSurfaceRejectsTheOldInFlightCurrentFrame() {
        executor.runNext()
        holder.surfaceFrame.set(0, 0, 200, 100)
        engine.onSurfaceChanged(holder, 0, 200, 100)
        shadowOf(Looper.getMainLooper()).idle()
        val retained = ReflectionHelpers.getField<Bitmap?>(engine, "currentFrameBitmap")
        assertTrue(retained == null || (retained.width == 200 && retained.height == 100))
    }

    @Test fun destroyedSurfaceDropsLateWorkAndDoesNotRotate() {
        engine.onSurfaceDestroyed(holder)
        invoke("handleScreenOff")
        executor.runNext()
        shadowOf(Looper.getMainLooper()).idle()
        assertEquals(0, store.index)
        assertNull(ReflectionHelpers.getField<Bitmap?>(engine, "currentFrameBitmap"))
        assertTrue(executor.tasks.isEmpty())
    }

    private fun invoke(name: String) = ReflectionHelpers.callInstanceMethod<Unit>(engine, name)

    private class ManualExecutor : AbstractExecutorService() {
        val tasks = ArrayDeque<Runnable>()
        private var stopped = false
        fun runNext() = tasks.removeFirst().run()
        override fun execute(command: Runnable) { tasks.addLast(command) }
        override fun shutdown() { stopped = true }
        override fun shutdownNow(): MutableList<Runnable> { stopped = true; return mutableListOf() }
        override fun isShutdown() = stopped
        override fun isTerminated() = stopped && tasks.isEmpty()
        override fun awaitTermination(timeout: Long, unit: TimeUnit) = isTerminated
    }
}
