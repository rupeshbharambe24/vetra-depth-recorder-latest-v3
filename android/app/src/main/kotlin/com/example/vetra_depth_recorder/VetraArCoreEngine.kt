package com.example.vetra_depth_recorder

import android.app.Activity
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.os.Environment
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import com.google.ar.core.*
import com.google.ar.core.exceptions.*
import com.example.vetra_depth_recorder.rendering.BackgroundRenderer
import java.io.*
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

data class DepthInfo(
    val width: Int,
    val height: Int,
    val dtype: String,
    val units: String,
    val alignedToColor: Boolean
)

class VetraArCoreEngine(private val activity: Activity) : GLSurfaceView.Renderer {
    private var session: Session? = null
    private var depthSupported = false
    private var frameCounter = 0
    private var surfaceView: GLSurfaceView? = null
    private val backgroundRenderer = BackgroundRenderer()
    private var isSessionPaused = true

    // To handle capture requests from the UI thread
    private var pendingCapture: ((MethodChannel.Result) -> Unit)? = null
    private var pendingSessionId: String? = null
    private var pendingViewLabel: String? = null

    fun setSurfaceView(view: GLSurfaceView) {
        surfaceView = view
        view.preserveEGLContextOnPause = true
        view.setEGLContextClientVersion(2)
        view.setEGLConfigChooser(8, 8, 8, 8, 16, 0)
        view.setRenderer(this)
        view.renderMode = GLSurfaceView.RENDERMODE_CONTINUOUSLY
        view.onResume()
        
        // Resume session if it was created before the view was ready
        if (session != null && isSessionPaused) {
            try {
                session!!.resume()
                isSessionPaused = false
            } catch (e: Exception) {
                Log.e("VetraArCore", "Error resuming session in setSurfaceView", e)
            }
        }
    }

    /** Check ARCore and Depth support. */
    fun checkSupport(result: MethodChannel.Result) {
        try {
            val availability = ArCoreApk.getInstance().checkAvailability(activity)
            val arcoreAvailable = (availability == ArCoreApk.Availability.SUPPORTED_INSTALLED)
            var depthSupportMsg = ""
            depthSupported = false
            if (arcoreAvailable) {
                // Try creating a session to check depth support
                // Note: We can't create a session here if one is already active/paused in the background
                // But for the check step, typically no session is running yet.
                if (session == null) {
                    session = Session(activity)
                }
                val isDepthSupported = session?.isDepthModeSupported(Config.DepthMode.AUTOMATIC) == true
                depthSupported = isDepthSupported
                if (!isDepthSupported) depthSupportMsg = "Depth API not supported on this device."
                
                // Don't close session here if we want to reuse it, but typically we close and recreate for the actual session
                session?.close()
                session = null
            } else {
                depthSupportMsg = "ARCore not available: $availability"
            }
            result.success(mapOf(
                "arcoreAvailable" to arcoreAvailable,
                "depthSupported" to depthSupported,
                "message" to depthSupportMsg
            ))
        } catch (e: Exception) {
            result.success(mapOf(
                "arcoreAvailable" to false,
                "depthSupported" to false,
                "message" to "Error checking support: ${e.message}"
            ))
        }
    }

    /** Start ARCore session. */
    fun startSession(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val sessionId = call.argument<String>("sessionId") ?: "unknown"
        val enableDepth = call.argument<Boolean>("enableDepth") ?: true
        
        try {
            if (session == null) {
                session = Session(activity)
            }
            val config = session!!.config
            
            val isDepthSupportedByDevice = session!!.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
            
            if (enableDepth && isDepthSupportedByDevice) {
                config.depthMode = Config.DepthMode.AUTOMATIC
                this.depthSupported = true
            } else {
                config.depthMode = Config.DepthMode.DISABLED
                this.depthSupported = false
            }
            config.focusMode = Config.FocusMode.AUTO
            session!!.configure(config)
            
            Log.d("VETRA", "Configured ARCore session: deviceSupport=$isDepthSupportedByDevice, requested=$enableDepth, actualMode=${config.depthMode}, engineFlag=${this.depthSupported}")
            
            // Create directory for session data
            val baseDir = File(activity.getExternalFilesDir(null), "VETRA_DATA/session_$sessionId")
            if (!baseDir.exists()) baseDir.mkdirs()
            frameCounter = 0
            
            // Resume session if surface is ready
            if (surfaceView != null) {
                session!!.resume()
                isSessionPaused = false
            }
            
            result.success(true)
        } catch (e: Exception) {
            Log.e("VetraArCore", "Error starting session", e)
            result.success(false)
        }
    }

    /** Capture one AR frame. */
    fun captureFrame(sessionId: String, viewLabel: String, result: MethodChannel.Result) {
        // We need to capture on the GL thread to ensure frame consistency or just grab the latest frame
        // For simplicity, we'll set a pending capture and handle it in onDrawFrame
        synchronized(this) {
            pendingSessionId = sessionId
            pendingViewLabel = viewLabel
            pendingCapture = { res ->
                // This callback will be executed after capture is done
                // We need to make sure we call result.success/error on the UI thread if needed, 
                // but MethodChannel results can often be called from any thread (check Flutter docs, usually UI thread preferred).
                // Actually, result.success IS thread safe in newer Flutter versions, but let's be safe.
                activity.runOnUiThread {
                    res.success(result) // This is wrong, we need to pass the map to result.success
                }
            }
            // Wait? No, we can't block the UI thread. 
            // We'll actually just store the 'result' object and call it later.
        }
        
        // Revised approach: Store the result object directly
        synchronized(this) {
             pendingSessionId = sessionId
             pendingViewLabel = viewLabel
             // We'll use a separate variable for the result callback
             captureResultCallback = result
        }
    }
    
    private var captureResultCallback: MethodChannel.Result? = null

    /** End the ARCore session. */
    fun endSession() {
        synchronized(this) {
            if (session == null) return
            try {
                session?.pause()
                session?.close()
                session = null
                isSessionPaused = true
            } catch (e: Exception) {
                Log.e("VetraArCore", "Error ending session", e)
            }
        }
    }

    // GLSurfaceView.Renderer implementation

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.1f, 0.1f, 0.1f, 1.0f)
        backgroundRenderer.createOnGlThread(activity)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        session?.setDisplayGeometry(0, width, height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)

        if (session == null) return
        if (isSessionPaused) return

        try {
            session!!.setCameraTextureName(backgroundRenderer.getTextureId())
            val frame = session!!.update()
            sampleCenterDepth(frame)
            
            backgroundRenderer.draw(frame)
            
            // Handle pending capture
            var currentCaptureResult: MethodChannel.Result? = null
            var currentSessionId = ""
            var currentViewLabel = ""
            
            synchronized(this) {
                if (captureResultCallback != null) {
                    currentCaptureResult = captureResultCallback
                    currentSessionId = pendingSessionId ?: ""
                    currentViewLabel = pendingViewLabel ?: ""
                    captureResultCallback = null
                    pendingSessionId = null
                    pendingViewLabel = null
                }
            }
            
            if (currentCaptureResult != null) {
                processCapture(frame, currentSessionId, currentViewLabel, currentCaptureResult!!)
            }

        } catch (e: Exception) {
            Log.e("VetraArCore", "Error in onDrawFrame", e)
        }
    }
    
    private fun processCapture(frame: Frame, sessionId: String, viewLabel: String, result: MethodChannel.Result) {
        try {
            val timestamp = frame.timestamp
            val camera = frame.camera

            // Acquire camera image (YUV_420_888)
            val image: Image? = try {
                frame.acquireCameraImage()
            } catch (e: NotYetAvailableException) {
                null 
            }
            
            // Acquire depth image (16-bit) if supported
            val depthImage: Image? = if (depthSupported) {
                try { frame.acquireDepthImage16Bits() } catch (e: Exception) { null }
            } else null

            // Prepare file paths
            val frameId = ++frameCounter
            val sessionDir = File(activity.getExternalFilesDir(null), "VETRA_DATA/session_$sessionId")
            val frameDir = File(sessionDir, String.format("frame_%04d", frameId))
            frameDir.mkdirs()
            val imgFile = File(frameDir, "color.jpg")
            val depthFile = depthImage?.let { File(frameDir, "depth.bin") }

            // Save RGB image
            image?.use { img ->
                val width = img.width; val height = img.height
                val yPlane = img.planes[0]; val uPlane = img.planes[1]; val vPlane = img.planes[2]
                val ySize = yPlane.buffer.remaining()
                val uSize = uPlane.buffer.remaining()
                val vSize = vPlane.buffer.remaining()
                val nv21 = ByteArray(ySize + uSize + vSize)
                yPlane.buffer.get(nv21, 0, ySize)
                vPlane.buffer.get(nv21, ySize, vSize)
                uPlane.buffer.get(nv21, ySize + vSize, uSize)
                val yuvImg = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                FileOutputStream(imgFile).use { fos ->
                    yuvImg.compressToJpeg(Rect(0, 0, width, height), 90, fos)
                }
            }
            
            // Save depth image using robust method
            var depthInfo: DepthInfo? = null
            
            if (depthImage != null && depthFile != null) {
                try {
                    depthInfo = writeDepthToBin(depthImage, depthFile)
                } catch (e: Exception) {
                    Log.e("VetraArCore", "Error writing depth bin", e)
                } finally {
                    depthImage.close()
                }
            } else {
                depthImage?.close()
            }

            val depthWidth = depthInfo?.width ?: 0
            val depthHeight = depthInfo?.height ?: 0

            // Get intrinsics
            val intrinsics = camera.imageIntrinsics
            val focal = intrinsics.focalLength 
            val principal = intrinsics.principalPoint 
            val dims = intrinsics.imageDimensions 
            val colorWidth = dims[0]
            val colorHeight = dims[1]

            // Calculate depth intrinsics
            val scaleX = if (colorWidth > 0 && depthWidth > 0) depthWidth.toFloat() / colorWidth.toFloat() else 0f
            val scaleY = if (colorHeight > 0 && depthHeight > 0) depthHeight.toFloat() / colorHeight.toFloat() else 0f
            
            val fxColor = focal[0]
            val fyColor = focal[1]
            val cxColor = principal[0]
            val cyColor = principal[1]

            // Only compute depth intrinsics if we actually have depth
            val hasDepth = (depthWidth > 0 && depthHeight > 0)
            
            val fxDepth = if (hasDepth) fxColor * scaleX else 0f
            val fyDepth = if (hasDepth) fyColor * scaleY else 0f
            val cxDepth = if (hasDepth) cxColor * scaleX else 0f
            val cyDepth = if (hasDepth) cyColor * scaleY else 0f
            
            // Log intrinsics for verification
            Log.d("VETRA", "Color intrinsics: fx=$fxColor, fy=$fyColor, cx=$cxColor, cy=$cyColor, size=${colorWidth}x${colorHeight}")
            if (hasDepth) {
                Log.d("VETRA", "Depth intrinsics: fx=$fxDepth, fy=$fyDepth, cx=$cxDepth, cy=$cyDepth, size=${depthWidth}x${depthHeight}")
            } else {
                Log.d("VETRA", "Depth intrinsics: None (RGB only)")
            }

            // Get pose
            val pose = camera.pose
            val mat4 = FloatArray(16).also { pose.toMatrix(it, 0) }
            val quat = pose.rotationQuaternion 
            val trans = pose.translation 

            // Write metadata JSON
            val meta = File(frameDir, "meta.json")
            val depthIntrinsicsJson = if (hasDepth) """
              "depthIntrinsics": {
                "fx": $fxDepth, "fy": $fyDepth,
                "cx": $cxDepth, "cy": $cyDepth,
                "width": $depthWidth, "height": $depthHeight
              },
            """.trimIndent() else "\"depthIntrinsics\": null,"

            val depthPathJson = if (depthFile != null && hasDepth) "\"${depthFile.absolutePath}\"" else "null"
            
            val json = """
            {
              "frameId": $frameId,
              "timestampNs": $timestamp,
              "viewLabel": "${viewLabel}",
              "imagePath": "${imgFile.absolutePath}",
              "depthPath": $depthPathJson,
              "colorIntrinsics": {
                "fx": $fxColor, "fy": $fyColor,
                "cx": $cxColor, "cy": $cyColor,
                "width": $colorWidth, "height": $colorHeight
              },
              $depthIntrinsicsJson
              "pose": {
                "matrix_4x4_row_major": [${mat4.joinToString(", ")}],
                "quaternion_xyzw": [${quat[0]}, ${quat[1]}, ${quat[2]}, ${quat[3]}],
                "translation_m": [${trans[0]}, ${trans[1]}, ${trans[2]}],
                "convention": "camera_to_world"
              },
              "depthFormat": "${if (hasDepth) "RAW16" else "NONE"}",
              "depthInfo": {
                "width": $depthWidth,
                "height": $depthHeight,
                "dtype": "uint16",
                "units": "millimeters",
                "alignedToColor": false
              }
            }
            """.trimIndent()
            meta.writeText(json)

            val resMap = mutableMapOf<String, Any?>(
                "frameId" to frameId,
                "timestampNs" to timestamp,
                "viewLabel" to viewLabel,
                "imagePath" to imgFile.absolutePath,
                "colorIntrinsics" to mapOf(
                    "fx" to fxColor, "fy" to fyColor,
                    "cx" to cxColor, "cy" to cyColor,
                    "width" to colorWidth, "height" to colorHeight
                ),
                "pose" to mapOf(
                    "matrix_4x4_row_major" to mat4.toList(),
                    "quaternion_xyzw" to listOf(quat[0], quat[1], quat[2], quat[3]),
                    "translation_m" to listOf(trans[0], trans[1], trans[2]),
                    "convention" to "camera_to_world"
                ),
                "depthFormat" to (if (hasDepth) "RAW16" else "NONE"),
                "depthPath" to (if (hasDepth && depthFile != null) depthFile.absolutePath else ""),
                "metaPath" to meta.absolutePath
            )
            
            if (hasDepth) {
                 resMap["depthIntrinsics"] = mapOf(
                    "fx" to fxDepth, "fy" to fyDepth,
                    "cx" to cxDepth, "cy" to cyDepth,
                    "width" to depthWidth, "height" to depthHeight
                )
            } else {
                resMap["depthIntrinsics"] = null
            }
            
            activity.runOnUiThread {
                result.success(resMap)
            }
            
        } catch (e: Exception) {
            activity.runOnUiThread {
                result.error("CaptureError", e.message, null)
            }
        }
    }

    private fun writeDepthToBin(depthImage: Image, outFile: File): DepthInfo {
        val width = depthImage.width
        val height = depthImage.height
        val plane = depthImage.planes[0]
        val buffer = plane.buffer
        val rowStride = plane.rowStride
        val pixelStride = plane.pixelStride 

        // Output: H x W x 2 bytes (uint16 little-endian)
        val out = ByteArray(width * height * 2)
        val row = ByteArray(rowStride)
        var dst = 0

        buffer.rewind()
        for (y in 0 until height) {
            buffer.get(row, 0, rowStride)
            var src = 0
            for (x in 0 until width) {
                // Copy 2 bytes for this pixel (little-endian)
                out[dst++] = row[src]
                out[dst++] = row[src + 1]
                src += pixelStride
            }
        }

        // Debug Logging: Check for non-zero values
        try {
            val shortBuf = java.nio.ByteBuffer.wrap(out)
                .order(java.nio.ByteOrder.LITTLE_ENDIAN)
                .asShortBuffer()

            val sampleCount = kotlin.math.min(shortBuf.limit(), 20)
            val samples = ShortArray(sampleCount)
            shortBuf.get(samples, 0, sampleCount)
            Log.d("VETRA", "Depth samples (first $sampleCount): ${samples.joinToString()}")
            
            // Check for all zeros
            var nonZeroCount = 0
            for (i in 0 until shortBuf.limit()) {
                if (shortBuf.get(i).toInt() != 0) {
                    nonZeroCount++
                }
            }
            if (nonZeroCount == 0) {
                Log.w("VETRA", "All sampled depth values are zero! (width=$width, height=$height)")
            } else {
                Log.d("VETRA", "Found $nonZeroCount non-zero depth values out of ${shortBuf.limit()}")
            }

        } catch (e: Exception) {
            Log.e("VETRA", "Error logging depth samples", e)
        }

        FileOutputStream(outFile).use { fos ->
            fos.write(out)
        }
        
        return DepthInfo(
            width = width,
            height = height,
            dtype = "uint16",
            units = "millimeters",
            alignedToColor = false
        )
    }

    private var lastCenterDepth: Float = 0.0f
    private var lastDepthUpdateTimestamp: Long = 0L

    fun getCenterDepth(result: MethodChannel.Result) {
        result.success(lastCenterDepth)
    }

    private fun sampleCenterDepth(frame: Frame) {
        val now = System.currentTimeMillis()
        if (now - lastDepthUpdateTimestamp < 200) return

        lastDepthUpdateTimestamp = now

        if (!depthSupported) {
             lastCenterDepth = 0.0f
             return
        }

        try {
            val depthImage = frame.acquireDepthImage16Bits()
            if (depthImage != null) {
                val width = depthImage.width
                val height = depthImage.height
                
                // Center coordinates
                val cx = width / 2
                val cy = height / 2
                
                val plane = depthImage.planes[0]
                val buffer = plane.buffer
                val rowStride = plane.rowStride
                val pixelStride = plane.pixelStride
                
                // Calculate offset
                val offset = (cy * rowStride) + (cx * pixelStride)
                
                if (offset + 1 < buffer.limit()) {
                    val low = buffer.get(offset).toInt() and 0xFF
                    val high = buffer.get(offset + 1).toInt() and 0xFF
                    val depthMm = (high shl 8) or low
                    lastCenterDepth = depthMm / 1000.0f // Convert to meters
                }
                
                depthImage.close()
            }
        } catch (e: NotYetAvailableException) {
            // Depth not available
        } catch (e: Exception) {
            Log.e("VetraArCore", "Error sampling center depth", e)
        }
    }
}
