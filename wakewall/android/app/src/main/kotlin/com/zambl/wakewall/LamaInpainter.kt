package com.zambl.wakewall

import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.FloatBuffer

class LamaInpainter(context: Context) {
    private val appContext = context.applicationContext

    fun inpaint(imageBytes: ByteArray, maskBytes: ByteArray): ByteArray {
        val image = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size)
            ?: error("AI Fill could not read the generated wallpaper draft.")
        val mask = BitmapFactory.decodeByteArray(maskBytes, 0, maskBytes.size)
            ?: error("AI Fill could not read the generated mask.")
        if (image.width != mask.width || image.height != mask.height) {
            image.recycle()
            mask.recycle()
            error("AI Fill image and mask sizes did not match.")
        }

        val originalWidth = image.width
        val originalHeight = image.height
        val modelImage = Bitmap.createScaledBitmap(image, MODEL_SIZE, MODEL_SIZE, true)
        val modelMask = Bitmap.createScaledBitmap(mask, MODEL_SIZE, MODEL_SIZE, false)
        image.recycle()
        mask.recycle()

        val environment = OrtEnvironment.getEnvironment()
        val session = session(environment, appContext)
        val imageTensor = OnnxTensor.createTensor(
            environment,
            imageTensor(modelImage),
            longArrayOf(1, 3, MODEL_SIZE.toLong(), MODEL_SIZE.toLong()),
        )
        val maskTensor = OnnxTensor.createTensor(
            environment,
            maskTensor(modelMask),
            longArrayOf(1, 1, MODEL_SIZE.toLong(), MODEL_SIZE.toLong()),
        )
        modelImage.recycle()
        modelMask.recycle()

        imageTensor.use { imageInput ->
            maskTensor.use { maskInput ->
                session.run(mapOf("image" to imageInput, "mask" to maskInput)).use { result ->
                    val output = result.get(0) as OnnxTensor
                    val square = outputBitmap(output)
                    val resized = Bitmap.createScaledBitmap(square, originalWidth, originalHeight, true)
                    square.recycle()
                    return encodeJpeg(resized)
                }
            }
        }
    }

    private fun imageTensor(bitmap: Bitmap): FloatBuffer {
        val pixels = IntArray(MODEL_SIZE * MODEL_SIZE)
        bitmap.getPixels(pixels, 0, MODEL_SIZE, 0, 0, MODEL_SIZE, MODEL_SIZE)
        val buffer = FloatBuffer.allocate(MODEL_SIZE * MODEL_SIZE * 3)
        for (channel in 0 until 3) {
            val shift = when (channel) {
                0 -> 0
                1 -> 8
                else -> 16
            }
            for (pixel in pixels) {
                buffer.put(((pixel shr shift) and 0xff) * IMAGE_SCALE)
            }
        }
        buffer.rewind()
        return buffer
    }

    private fun maskTensor(bitmap: Bitmap): FloatBuffer {
        val pixels = IntArray(MODEL_SIZE * MODEL_SIZE)
        bitmap.getPixels(pixels, 0, MODEL_SIZE, 0, 0, MODEL_SIZE, MODEL_SIZE)
        val buffer = FloatBuffer.allocate(MODEL_SIZE * MODEL_SIZE)
        for (pixel in pixels) {
            val value = (Color.red(pixel) + Color.green(pixel) + Color.blue(pixel)) / 3
            buffer.put(if (value > 127) 0f else 1f)
        }
        buffer.rewind()
        return buffer
    }

    private fun outputBitmap(tensor: OnnxTensor): Bitmap {
        val data = tensor.floatBuffer
        val planeSize = MODEL_SIZE * MODEL_SIZE
        val pixels = IntArray(planeSize)
        for (index in 0 until planeSize) {
            val blue = pixel(data.get(index))
            val green = pixel(data.get(planeSize + index))
            val red = pixel(data.get(planeSize * 2 + index))
            pixels[index] = Color.rgb(red, green, blue)
        }
        return Bitmap.createBitmap(MODEL_SIZE, MODEL_SIZE, Bitmap.Config.ARGB_8888).apply {
            setPixels(pixels, 0, MODEL_SIZE, 0, 0, MODEL_SIZE, MODEL_SIZE)
        }
    }

    private fun pixel(value: Float): Int =
        value.coerceIn(0f, 255f).toInt()

    private fun encodeJpeg(bitmap: Bitmap): ByteArray {
        val output = ByteArrayOutputStream()
        bitmap.compress(Bitmap.CompressFormat.JPEG, 95, output)
        bitmap.recycle()
        return output.toByteArray()
    }

    companion object {
        private const val MODEL_ASSET = "inpainting_lama_2025jan.onnx"
        private const val MODEL_SIZE = 512
        private const val IMAGE_SCALE = 0.00392f
        private var cachedSession: OrtSession? = null

        @Synchronized
        private fun session(environment: OrtEnvironment, context: Context): OrtSession {
            cachedSession?.let { return it }
            File(context.noBackupFilesDir, "migan_pipeline_v2.onnx").delete()
            val modelFile = File(context.noBackupFilesDir, MODEL_ASSET)
            if (!modelFile.exists() || modelFile.length() == 0L) {
                context.assets.open(MODEL_ASSET).use { input ->
                    modelFile.outputStream().use(input::copyTo)
                }
            }
            val options = OrtSession.SessionOptions()
            return environment.createSession(modelFile.absolutePath, options).also {
                cachedSession = it
            }
        }
    }
}
