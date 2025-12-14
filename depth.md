# ARCore Depth API Implementation Guide

This document provides a detailed technical overview of how the ARCore Depth API is integrated into the Vetra Depth Recorder project. It is designed to assist other agents or developers in understanding and implementing similar functionality.

## 1. Architecture Overview

The project uses a hybrid architecture:
- **Flutter (UI Layer)**: Handles user interaction, session management, and visualizing real-time data overlays.
- **Native Android (Kotlin)**: Manages the ARCore session, accesses raw camera streams, and performs high-performance depth data extraction.
- **MethodChannel**: Facilitates communication between Flutter and Native Android.

## 2. Session Configuration

The core logic resides in `VetraArCoreEngine.kt`.

### Enabling Depth
To enable the Depth API, the ARCore `Session` must be configured with `Config.DepthMode.AUTOMATIC`.

```kotlin
// VetraArCoreEngine.kt -> startSession()

// 1. Check if the device hardware supports depth
val isDepthSupportedByDevice = session!!.isDepthModeSupported(Config.DepthMode.AUTOMATIC)

// 2. Configure the session based on support AND user preference
if (enableDepth && isDepthSupportedByDevice) {
    config.depthMode = Config.DepthMode.AUTOMATIC
    this.depthSupported = true // Critical: Update internal state flag
} else {
    config.depthMode = Config.DepthMode.DISABLED
    this.depthSupported = false
}

session!!.configure(config)
```

**Key Takeaway**: Always verify `isDepthModeSupported` before enabling it. Maintain a local `depthSupported` flag to gate subsequent depth operations (like image acquisition) to prevent crashes.

## 3. Depth Data Acquisition

ARCore provides depth data as an `Image` object with format `ImageFormat.DEPTH16`.

### Acquiring the Image
We acquire the depth image from the current frame. This is a potentially expensive operation and requires the image to be closed explicitly to prevent memory leaks.

```kotlin
// Inside onDrawFrame() or capture logic
try {
    val depthImage = frame.acquireDepthImage16Bits() // Returns 16-bit depth image
    if (depthImage != null) {
        // Process data...
        depthImage.close() // MUST CLOSE
    }
} catch (e: NotYetAvailableException) {
    // Depth data might not be ready in the first few frames
}
```

### Data Format
- **Format**: `ImageFormat.DEPTH16`
- **Data Type**: 16-bit unsigned integer (`uint16`).
- **Unit**: Millimeters (mm).
- **Endianness**: Little-endian.
- **Structure**: The image is a flat byte buffer. To access pixel `(x, y)`, you must calculate the offset using the plane's `rowStride` and `pixelStride`.

## 4. Real-time Depth Sampling

For the UI overlay, we sample the depth at the center of the screen.

### Logic (Native)
We perform this check periodically (throttled) inside `onDrawFrame` to avoid impacting the render loop performance.

```kotlin
private fun sampleCenterDepth(frame: Frame) {
    // 1. Throttle updates (e.g., max 5Hz)
    val now = System.currentTimeMillis()
    if (now - lastDepthUpdateTimestamp < 200) return 
    
    // ... acquire depth image ...

    // 2. Calculate Center Coordinates
    val cx = depthImage.width / 2
    val cy = depthImage.height / 2

    // 3. Access Pixel Data
    val plane = depthImage.planes[0]
    val buffer = plane.buffer
    // Use strides to find exact byte index
    val offset = (cy * plane.rowStride) + (cx * plane.pixelStride)

    // 4. Extract 16-bit value
    val low = buffer.get(offset).toInt() and 0xFF
    val high = buffer.get(offset + 1).toInt() and 0xFF
    val depthMm = (high shl 8) or low

    // 5. Convert to Meters
    this.lastCenterDepth = depthMm / 1000.0f
}
```

## 5. Saving Depth to File (`depth.bin`)

When capturing a frame, we save the full raw depth buffer.

### Robust Write Method
We extract the byte buffer and write it directly to a file. This ensures we capture the exact raw data provided by ARCore.

```kotlin
private fun writeDepthToBin(depthImage: Image, outFile: File): DepthInfo {
    val width = depthImage.width
    val height = depthImage.height
    val plane = depthImage.planes[0]
    val buffer = plane.buffer
    val rowStride = plane.rowStride
    val pixelStride = plane.pixelStride 

    // Prepare output array (H * W * 2 bytes)
    val out = ByteArray(width * height * 2)
    
    // Iterate rows because direct buffer might include padding bytes at end of rows
    buffer.rewind()
    var dst = 0
    val rowBuffer = ByteArray(rowStride)

    for (y in 0 until height) {
        buffer.get(rowBuffer, 0, rowStride) // Read full row with stride
        var src = 0
        for (x in 0 until width) {
            // Copy valid pixel bytes only
            out[dst++] = rowBuffer[src]
            out[dst++] = rowBuffer[src + 1]
            src += pixelStride
        }
    }

    FileOutputStream(outFile).use { fos ->
        fos.write(out)
    }

    return DepthInfo(width, height, "uint16", "millimeters", false)
}
```
**Important**: Do not simply dump `buffer.array()` because `rowStride` may introduce padding bytes between rows which are not part of the image data. Always copy row-by-row.

## 6. Depth Intrinsics

The depth map often has a different resolution and aspect ratio than the CPU color image. We must calculate the depth intrinsics based on the Color camera intrinsics.

```kotlin
// Calculate scale factors
val scaleX = depthWidth.toFloat() / colorWidth.toFloat()
val scaleY = depthHeight.toFloat() / colorHeight.toFloat()

// Scale intrinsics
val fxDepth = fxColor * scaleX
val fyDepth = fyColor * scaleY
val cxDepth = cxColor * scaleX
val cyDepth = cyColor * scaleY
```

This ensures that the 3D points back-projected from the depth map align correctly with the 3D world.

## Summary Checklist for Implementation
1.  [ ] **Check Support**: Use `ArCoreApk.checkAvailability()`.
2.  [ ] **Configure Session**: Set `Config.DepthMode.AUTOMATIC`.
3.  [ ] **Acquire Image**: Use `frame.acquireDepthImage16Bits()`.
4.  [ ] **Handle Strides**: Always use `rowStride` and `pixelStride` when reading the buffer.
5.  [ ] **Close Image**: Must call `depthImage.close()` in a `finally` block.
6.  [ ] **Thread Safety**: ARCore frame updates happen on the GL thread; ensure UI updates (MethodChannel results) are posted to the main thread.
