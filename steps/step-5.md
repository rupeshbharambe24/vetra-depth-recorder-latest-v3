Step 6 – Native Export Format Fixes (Manual Build Instructions)
🎯 Goals:

Save raw depth as depth.bin

Add depthInfo and poseConvention in meta.json

Ensure frameId = "frame_0001" style matches folder

Flutter model (FrameCapture) updated if needed

🔧 Android (Kotlin) Updates
📁 In VetraArCoreEngine.kt, update captureFrame():

Frame ID Format:
Replace:

val frameId = ++frameCounter


With:

val frameIdStr = String.format("frame_%04d", ++frameCounter)


Rename depth file:
Change from:

val depthFile = File(frameDir, "depth.png")


To:

val depthFile = File(frameDir, "depth.bin")


Update meta.json fields:
Add these keys into your meta.json string:

"frameId": "frame_0001",
...
"poseConvention": "camera_to_world",
"depthInfo": {
  "width": 120,
  "height": 120,
  "bytesPerPixel": 2,
  "dtype": "uint16",
  "units": "millimeters",
  "alignedToColor": true
}


You can inject it via Kotlin string templates:

val json = """
{
  "frameId": "$frameIdStr",
  "timestampNs": $timestamp,
  "viewLabel": "$viewLabel",
  "imagePath": "${imgFile.absolutePath}",
  "depthPath": "${depthFile?.absolutePath ?: ""}",
  "intrinsics": {
    "fx": $fx, "fy": $fy,
    "cx": $cx, "cy": $cy,
    "imageWidth": $width, "imageHeight": $height
  },
  "pose": {
    "matrix_4x4_row_major": [${mat4.joinToString(", ")}],
    "quaternion_xyzw": [${quat.joinToString(", ")}],
    "translation_m": [${trans.joinToString(", ")}]
  },
  "poseConvention": "camera_to_world",
  "depthInfo": {
    "width": $depthWidth,
    "height": $depthHeight,
    "bytesPerPixel": 2,
    "dtype": "uint16",
    "units": "millimeters",
    "alignedToColor": true
  },
  "depthFormat": "RAW16"
}
""".trimIndent()

📱 Flutter Model Adjustments (Optional)

In FrameCapture (in Dart), update the id to be a string matching "frame_0001":

class FrameCapture {
  final String id; // e.g. "frame_0001"
  ...
}


When you deserialize ArFrameResult, ensure frameId is handled as a string.

📁 Example Output: Final meta.json
{
  "frameId": "frame_0001",
  "timestampNs": 124113227113698,
  "viewLabel": "left_side",
  "imagePath": "/storage/emulated/0/.../frame_0001/color.jpg",
  "depthPath": "/storage/emulated/0/.../frame_0001/depth.bin",
  "intrinsics": {
    "fx": 474.2817,
    "fy": 474.24237,
    "cx": 319.65915,
    "cy": 236.24637,
    "imageWidth": 640,
    "imageHeight": 480
  },
  "pose": {
    "matrix_4x4_row_major": [...],
    "quaternion_xyzw": [...],
    "translation_m": [...]
  },
  "poseConvention": "camera_to_world",
  "depthInfo": {
    "width": 120,
    "height": 120,
    "bytesPerPixel": 2,
    "dtype": "uint16",
    "units": "millimeters",
    "alignedToColor": true
  },
  "depthFormat": "RAW16"
}
