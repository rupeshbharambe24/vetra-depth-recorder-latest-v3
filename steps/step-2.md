VETRA Depth Recorder – ARCore Integration (Step 2)
To integrate ARCore depth capture via a Flutter plugin, we create a MethodChannel and native Kotlin engine. The Flutter service exposes methods (checkSupport, startSession, captureFrame, endSession) over channel vetra_depth_recorder/arcore. The Android code uses ARCore’s SDK: it checks ARCore availability (via ArCoreApk.checkAvailability) and depth support (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC))
developers.google.com
developers.google.com
. The startSession method initializes an ArCore Session, enabling depth if supported. Each captureFrame call does session.update(), then acquires the camera image (frame.acquireCameraImage()) and, if available, the 16-bit depth image (frame.acquireDepthImage16Bits())
developers.google.com
developers.google.com
. We then obtain the camera’s pose and intrinsics (focal length, principal point, image dimensions) from frame.getCamera()
developers.google.com
developers.google.com
, and write these plus file paths into meta.json. Finally, endSession closes the session. External files are saved under /Android/data/<package>/files/VETRA_DATA/session_<sessionId>/… using getExternalFilesDir(null).
Flutter: arcore_service.dart
MethodChannel setup: Define channel 'vetra_depth_recorder/arcore'.
Methods:
checkSupport(): invokes native checkSupport and returns an ArCoreSupportInfo (with flags arcoreAvailable, depthSupported, and a message).
startSession(sessionId): calls native to start an ARCore session (returns a bool).
captureFrame(sessionId, viewLabel): calls native to capture one frame (returns an ArFrameResult).
endSession(): ends the ARCore session.
Data classes:
ArCoreSupportInfo holds arcoreAvailable (bool), depthSupported (bool), and message (String).
ArFrameResult holds frame metadata (frameId, timestampNs, viewLabel, file paths, intrinsics, pose, etc).
// lib/services/arcore_service.dart

import 'dart:async';
import 'package:flutter/services.dart';

/// Support info: whether ARCore and Depth are supported
class ArCoreSupportInfo {
  final bool arcoreAvailable;
  final bool depthSupported;
  final String message;
  ArCoreSupportInfo({
    required this.arcoreAvailable,
    required this.depthSupported,
    required this.message,
  });
  factory ArCoreSupportInfo.fromJson(Map<String, dynamic> json) {
    return ArCoreSupportInfo(
      arcoreAvailable: json['arcoreAvailable'] as bool,
      depthSupported: json['depthSupported'] as bool,
      message: json['message'] as String,
    );
  }
}

/// Result from capturing an AR frame
class ArFrameResult {
  final int frameId;
  final int timestampNs;
  final String viewLabel;
  final String imagePath;
  final String? depthPath;
  final Intrinsics intrinsics;
  final PoseData pose;
  final String depthFormat;
  ArFrameResult({
    required this.frameId,
    required this.timestampNs,
    required this.viewLabel,
    required this.imagePath,
    this.depthPath,
    required this.intrinsics,
    required this.pose,
    required this.depthFormat,
  });
  factory ArFrameResult.fromJson(Map<String, dynamic> json) {
    return ArFrameResult(
      frameId: json['frameId'] as int,
      timestampNs: json['timestampNs'] as int,
      viewLabel: json['viewLabel'] as String,
      imagePath: json['imagePath'] as String,
      depthPath: json['depthPath'] as String?,
      intrinsics: Intrinsics.fromJson(json['intrinsics']),
      pose: PoseData.fromJson(json['pose']),
      depthFormat: json['depthFormat'] as String,
    );
  }
}

class Intrinsics {
  final double fx, fy, cx, cy;
  final int imageWidth, imageHeight;
  Intrinsics(this.fx, this.fy, this.cx, this.cy, this.imageWidth, this.imageHeight);
  factory Intrinsics.fromJson(Map<String, dynamic> json) {
    return Intrinsics(
      (json['fx'] as num).toDouble(),
      (json['fy'] as num).toDouble(),
      (json['cx'] as num).toDouble(),
      (json['cy'] as num).toDouble(),
      json['imageWidth'] as int,
      json['imageHeight'] as int,
    );
  }
}

class PoseData {
  final List<double> matrix;    // 16 floats (row-major 4x4 matrix)
  final List<double> quaternion; // 4 floats (x, y, z, w)
  final List<double> translation; // 3 floats (meters)
  PoseData(this.matrix, this.quaternion, this.translation);
  factory PoseData.fromJson(Map<String, dynamic> json) {
    return PoseData(
      List<double>.from(json['matrix_4x4_row_major'].map((v) => v.toDouble())),
      List<double>.from(json['quaternion_xyzw'].map((v) => v.toDouble())),
      List<double>.from(json['translation_m'].map((v) => v.toDouble())),
    );
  }
}

class ArCoreService {
  static const _channel = MethodChannel('vetra_depth_recorder/arcore');

  /// Check device support for ARCore & Depth
  static Future<ArCoreSupportInfo> checkSupport() async {
    final result = await _channel.invokeMethod<Map>('checkSupport');
    if (result == null) {
      throw Exception('Failed to get support info');
    }
    return ArCoreSupportInfo.fromJson(result.cast());
  }

  /// Start a new ARCore session with given sessionId
  static Future<bool> startSession(String sessionId) async {
    return await _channel.invokeMethod<bool>(
      'startSession', {'sessionId': sessionId}) ?? false;
  }

  /// Capture one frame from ARCore, with a label for the view
  static Future<ArFrameResult> captureFrame(String sessionId, String viewLabel) async {
    final result = await _channel.invokeMethod<Map>(
      'captureFrame', {'sessionId': sessionId, 'viewLabel': viewLabel});
    if (result == null) throw Exception('Failed to capture frame');
    return ArFrameResult.fromJson(result.cast());
  }

  /// End the current ARCore session
  static Future<void> endSession() async {
    await _channel.invokeMethod('endSession');
  }
}
Android (Kotlin): VetraArCoreEngine
checkSupport(): Calls ArCoreApk.getInstance().checkAvailability(context) to ensure ARCore is installed
developers.google.com
. We interpret SUPPORTED_INSTALLED as available. It also initializes a temporary Session to check if Config.DepthMode.AUTOMATIC is supported
developers.google.com
. The method returns a Map with {arcoreAvailable, depthSupported, message} for Flutter.
startSession(sessionId): Creates a new ARCore Session, sets config.depthMode = AUTOMATIC if supported
developers.google.com
, and calls session.configure(config). It also creates directory /files/VETRA_DATA/session_<sessionId>/ for saving data.
captureFrame(sessionId, viewLabel): Calls session.update() to get the current Frame. It then attempts frame.acquireCameraImage()
developers.google.com
 (which yields an Image in YUV_420_888 format) and (if depth supported) frame.acquireDepthImage16Bits()
developers.google.com
. The camera image is converted to JPEG via YuvImage.compressToJpeg() for saving. The depth image (16-bit) is saved as a raw file or in a suitable image format. We retrieve camera pose (frame.camera.pose) and intrinsics (frame.camera.imageIntrinsics): focal lengths, principal point, image dims
developers.google.com
developers.google.com
. All metadata (frameId, timestamp, viewLabel, file paths, intrinsics, pose, depth format) is written to meta.json in the frame’s folder.
endSession(): Calls session.close() to release ARCore resources.
// android/app/src/main/kotlin/com/yourapp/VetraArCoreEngine.kt

package com.yourapp

import android.app.Activity
import android.content.Context
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
import android.os.Environment
import io.flutter.plugin.common.MethodChannel
import com.google.ar.core.*
import java.io.*

class VetraArCoreEngine(private val activity: Activity) {
    private var session: Session? = null
    private var depthSupported = false
    private var frameCounter = 0

    /** Check ARCore and Depth support. */
    fun checkSupport(result: MethodChannel.Result) {
        try {
            val availability = ArCoreApk.getInstance().checkAvailability(activity)
            val arcoreAvailable = (availability == ArCoreApk.Availability.SUPPORTED_INSTALLED)
            var depthSupportMsg = ""
            depthSupported = false
            if (arcoreAvailable) {
                // Try creating a session to check depth support
                session = Session(activity)
                val isDepthSupported = session?.isDepthModeSupported(Config.DepthMode.AUTOMATIC) == true
                depthSupported = isDepthSupported
                if (!isDepthSupported) depthSupportMsg = "Depth API not supported on this device."
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
        } catch (e: UnavailableException) {
            // ARCore not installed or supported
            result.success(mapOf(
                "arcoreAvailable" to false,
                "depthSupported" to false,
                "message" to "ARCore not supported: ${e.message}"
            ))
        }
    }

    /** Start ARCore session and prepare file directories. */
    fun startSession(sessionId: String, result: MethodChannel.Result) {
        try {
            // Initialize session
            session = Session(activity)
            val config = session!!.config
            // Enable depth if supported
            if (session!!.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                config.depthMode = Config.DepthMode.AUTOMATIC
            }
            session!!.configure(config)
            // Create directory for session data
            val baseDir = File(activity.getExternalFilesDir(null), "VETRA_DATA/session_$sessionId")
            if (!baseDir.exists()) baseDir.mkdirs()
            frameCounter = 0
            result.success(true)
        } catch (e: UnavailableException) {
            result.success(false)
        }
    }

    /** Capture one AR frame: images, pose, intrinsics, etc. */
    fun captureFrame(sessionId: String, viewLabel: String, result: MethodChannel.Result) {
        try {
            if (session == null) {
                result.error("NoSession", "ARCore session is not started", null)
                return
            }
            // Get current frame
            val frame = session!!.update()
            val timestamp = frame.timestamp
            val camera = frame.camera

            // Acquire camera image (YUV_420_888)
            val image: Image? = try {
                frame.acquireCameraImage()
            } catch (e: NotYetAvailableException) {
                null // skip if not ready
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
            val depthFile = depthImage?.let { File(frameDir, "depth.png") }

            // Save RGB image
            image?.use { img ->
                val width = img.width; val height = img.height
                // Convert YUV to NV21 byte array
                val yPlane = img.planes[0]; val uPlane = img.planes[1]; val vPlane = img.planes[2]
                val ySize = yPlane.buffer.remaining()
                val uSize = uPlane.buffer.remaining()
                val vSize = vPlane.buffer.remaining()
                val nv21 = ByteArray(ySize + uSize + vSize)
                yPlane.buffer.get(nv21, 0, ySize)
                vPlane.buffer.get(nv21, ySize, vSize)
                uPlane.buffer.get(nv21, ySize + vSize, uSize)
                // Create YuvImage and compress to JPEG
                val yuvImg = YuvImage(nv21, ImageFormat.NV21, width, height, null)
                FileOutputStream(imgFile).use { fos ->
                    yuvImg.compressToJpeg(Rect(0, 0, width, height), 90, fos)
                }
            }
            // Save depth image (if any) as PNG (16-bit depth map)
            depthImage?.use { dImg ->
                // Note: depthImage is single-plane 16-bit (depth in millimeters)
                val depthWidth = dImg.width; val depthHeight = dImg.height
                val depthPixels = ByteArray(depthWidth * depthHeight * 2)
                dImg.planes[0].buffer.get(depthPixels)
                // For simplicity, save raw buffer (or encode as needed)
                FileOutputStream(depthFile).use { fos ->
                    fos.write(depthPixels)
                }
            }

            // Get intrinsics
            val intrinsics = camera.imageIntrinsics
            val focal = intrinsics.focalLength // float[2] {fx, fy}
            val principal = intrinsics.principalPoint // float[2] {cx, cy}
            val dims = intrinsics.imageDimensions // int[2] {width, height}

            // Get pose
            val pose = camera.pose
            val mat4 = FloatArray(16).also { pose.toMatrix(it, 0) }
            val quat = pose.rotationQuaternion // [x,y,z,w]
            val trans = pose.translation // [x,y,z] in meters

            // Write metadata JSON
            val meta = File(frameDir, "meta.json")
            val json = """
            {
              "frameId": $frameId,
              "timestampNs": $timestamp,
              "viewLabel": "${viewLabel}",
              "imagePath": "${imgFile.absolutePath}",
              "depthPath": ${if (depthFile != null) "\"${depthFile.absolutePath}\"" else null},
              "intrinsics": {
                "fx": ${focal[0]}, "fy": ${focal[1]},
                "cx": ${principal[0]}, "cy": ${principal[1]},
                "imageWidth": ${dims[0]}, "imageHeight": ${dims[1]}
              },
              "pose": {
                "matrix_4x4_row_major": [${mat4.joinToString(", ")}],
                "quaternion_xyzw": [${quat[0]}, ${quat[1]}, ${quat[2]}, ${quat[3]}],
                "translation_m": [${trans[0]}, ${trans[1]}, ${trans[2]}]
              },
              "depthFormat": "PNG-16-bit"
            }
            """.trimIndent()
            meta.writeText(json)

            // Return result to Flutter
            val resMap = mutableMapOf<String, Any>(
                "frameId" to frameId,
                "timestampNs" to timestamp,
                "viewLabel" to viewLabel,
                "imagePath" to imgFile.absolutePath,
                "intrinsics" to mapOf(
                    "fx" to focal[0], "fy" to focal[1],
                    "cx" to principal[0], "cy" to principal[1],
                    "imageWidth" to dims[0], "imageHeight" to dims[1]
                ),
                "pose" to mapOf(
                    "matrix_4x4_row_major" to mat4.toList(),
                    "quaternion_xyzw" to listOf(quat[0], quat[1], quat[2], quat[3]),
                    "translation_m" to listOf(trans[0], trans[1], trans[2])
                ),
                "depthFormat" to "RAW16",
                "depthPath" to (depthFile?.absolutePath ?: "")
            )
            result.success(resMap)
        } catch (e: Exception) {
            result.error("CaptureError", e.message, null)
        }
    }

    /** End the ARCore session. */
    fun endSession() {
        session?.close()
        session = null
    }
}
(In the above Kotlin code, frame.acquireCameraImage() provides a YUV_420_888 Image
developers.google.com
. We convert it to JPEG using YuvImage.compressToJpeg(). The depth image (16-bit) is saved as raw bytes. We obtain intrinsics (intrinsics.focalLength, intrinsics.principalPoint, intrinsics.imageDimensions
developers.google.com
) and the camera pose (pose.toMatrix(), pose.getRotationQuaternion(), pose.getTranslation()
developers.google.com
developers.google.com
). Metadata is written into meta.json in the frame folder.)
Android MainActivity – MethodChannel
In android/app/src/main/kotlin/.../MainActivity.kt, we register the MethodChannel and route calls to our VetraArCoreEngine. For example:
// android/app/src/main/kotlin/com/yourapp/MainActivity.kt

package com.yourapp

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "vetra_depth_recorder/arcore"
    private lateinit var arEngine: VetraArCoreEngine

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        arEngine = VetraArCoreEngine(this)
        MethodChannel(flutterEngine?.dartExecutor?.binaryMessenger, CHANNEL).setMethodCallHandler {
            call, result ->
            when (call.method) {
                "checkSupport" -> {
                    arEngine.checkSupport(result)
                }
                "startSession" -> {
                    val sessionId = call.argument<String>("sessionId") ?: ""
                    arEngine.startSession(sessionId, result)
                }
                "captureFrame" -> {
                    val sessionId = call.argument<String>("sessionId") ?: ""
                    val viewLabel = call.argument<String>("viewLabel") ?: ""
                    arEngine.captureFrame(sessionId, viewLabel, result)
                }
                "endSession" -> {
                    arEngine.endSession()
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}
Android Permissions and Gradle
ARCore SDK: Add Google’s ARCore library to android/app/build.gradle (e.g. implementation 'com.google.ar:core:1.31.0')
stackoverflow.com
.
Permissions: In AndroidManifest.xml, declare camera permission and AR feature. For example:
<uses-permission android:name="android.permission.CAMERA"/>
<uses-feature android:name="android.hardware.camera.ar" android:required="false"/>
<meta-data android:name="com.google.ar.core" android:value="required"/>
The camera permission is needed for ARCore
developers.google.com
. (If restricting to depth-enabled devices, you can add <uses-feature android:name="com.google.ar.core.depth" />.)
Putting it together, the AndroidManifest might include:
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.yourapp">

    <uses-permission android:name="android.permission.CAMERA"/>
    <uses-feature android:name="android.hardware.camera.ar" android:required="false"/>

    <application
        android:name="io.flutter.app.FlutterApplication"
        android:label="vetra_depth_recorder"
        android:icon="@mipmap/ic_launcher">
        <!-- ARCore required if AR is core to the app -->
        <meta-data android:name="com.google.ar.core" android:value="required" />
        ...
    </application>
</manifest>
And in android/app/build.gradle:
dependencies {
    implementation 'com.google.ar:core:1.31.0'   // ARCore SDK
    // ... other dependencies ...
}
These additions ensure ARCore and camera use are properly declared
stackoverflow.com
developers.google.com
. References: We rely on the ARCore Android developer guide for setting up depth mode and acquiring images
developers.google.com
developers.google.com
, as well as ARCore’s API docs for camera and pose data
developers.google.com
developers.google.com
developers.google.com
. The ARCoreApk reference documents how to check and request ARCore availability
developers.google.com
, and official Flutter/Android docs outline MethodChannel usage.
Citations

Session  |  ARCore  |  Google for Developers

https://developers.google.com/ar/reference/java/com/google/ar/core/Session

Use Depth in your Android app  |  ARCore  |  Google for Developers

https://developers.google.com/ar/develop/java/depth/developer-guide

Use Depth in your Android app  |  ARCore  |  Google for Developers

https://developers.google.com/ar/develop/java/depth/developer-guide

Frame  |  ARCore  |  Google for Developers

https://developers.google.com/ar/reference/java/com/google/ar/core/Frame

CameraIntrinsics  |  ARCore  |  Google for Developers

https://developers.google.com/ar/reference/java/com/google/ar/core/CameraIntrinsics

Pose  |  ARCore  |  Google for Developers

https://developers.google.com/ar/reference/java/com/google/ar/core/Pose

Pose  |  ARCore  |  Google for Developers

https://developers.google.com/ar/reference/java/com/google/ar/core/Pose

unity game engine - How to add ARCore dependency type com.google.ar.core to AndroidManifest.xml in Android Studio - Stack Overflow

https://stackoverflow.com/questions/57940069/how-to-add-arcore-dependency-type-com-google-ar-core-to-androidmanifest-xml-in-a

Enable AR in your Android app  |  ARCore  |  Google for Developers

https://developers.google.com/ar/develop/java/enable-arcore
All Sources

developers.google
