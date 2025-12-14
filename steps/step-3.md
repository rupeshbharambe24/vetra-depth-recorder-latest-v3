Step 3: ARCore Integration & Session Handling

We update each screen per the requirements, calling into the ArCoreService platform channel and managing state. Below we describe the changes with example code.

DeviceCheckScreen

In DeviceCheckScreen’s initState, call ArCoreService.checkSupport() and store the results (ARCore support and Depth API support) in state. In the build() method, display these flags as text. If ARCore is not supported, show a red warning and disable the Continue button by setting onPressed: null. For example:

class DeviceCheckScreen extends StatefulWidget {
  // ...
}

class _DeviceCheckScreenState extends State<DeviceCheckScreen> {
  bool arCoreSupported = false;
  bool depthSupported = false;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    // Call ARCoreService.checkSupport() on init
    ArCoreService.checkSupport().then((support) {
      setState(() {
        arCoreSupported = support.arCoreSupported;
        depthSupported  = support.depthSupported;
        checking = false;
      });
    }).catchError((error) {
      setState(() {
        checking = false;
        arCoreSupported = false;
        depthSupported = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while checking support
    if (checking) {
      return Scaffold(
        appBar: AppBar(title: Text('Device Check')),
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text('Device Check')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            Text("ARCore support: ${arCoreSupported ? 'Yes' : 'No'}"),
            Text("Depth API support: ${depthSupported ? 'Yes' : 'No'}"),
            if (!arCoreSupported)
              Text("ARCore is not supported on this device!",
                   style: TextStyle(color: Colors.red)),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: (arCoreSupported && depthSupported)
                  ? () {
                      // Navigate to session setup
                      Navigator.push(context,
                        MaterialPageRoute(builder: (_) => SessionSetupScreen())
                      );
                    }
                  : null, // disable if not supported
              child: Text("Continue"),
            ),
          ],
        ),
      ),
    );
  }
}


Check support: The ArCoreService.checkSupport() should return an object (e.g. with arCoreSupported and depthSupported booleans). In Android’s native ARCore, depth support is usually checked with session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
developers.google.com
, so we assume the service wraps that logic.

UI flags: We show "Yes" or "No" based on those booleans. If unsupported, we display a warning (in red) and set the Continue button’s onPressed to null, which disables it.

SessionSetupScreen

On the Session Setup screen, when the user taps Start Capture, generate a new session ID, call ArCoreService.startSession(sessionId), and handle success or failure. We typically format the session ID with the current datetime, e.g. "session_YYYYMMDD_HHMMSS". For example:

void _onStartCapture() async {
  final now = DateTime.now();
  final sessionId = 'session_'
      '${now.year.toString().padLeft(4,'0')}'
      '${now.month.toString().padLeft(2,'0')}'
      '${now.day.toString().padLeft(2,'0')}_'
      '${now.hour.toString().padLeft(2,'0')}'
      '${now.minute.toString().padLeft(2,'0')}'
      '${now.second.toString().padLeft(2,'0')}';
  try {
    // Start ARCore session via the platform channel
    await ArCoreService.startSession(sessionId);
    // Create Session object (assumes a model with these fields)
    final session = Session(
      id: sessionId,
      animalId: selectedAnimalId,
      notes: notesController.text,
      createdAt: now,
      frames: [],
    );
    // Navigate to CaptureScreen, passing the session
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => CaptureScreen(session: session)));
  } catch (e) {
    // On failure, show error SnackBar
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Failed to start AR session: $e"))
    );
  }
}


Key points:

Session ID: We use DateTime.now() and padLeft to form session_YYYYMMDD_HHMMSS.

Start session: Call ArCoreService.startSession(sessionId) and await it. If it succeeds, we create a Session object (with id, animalId, notes, and createdAt = now). We then navigate to the CaptureScreen, passing this session.

Error handling: If startSession throws, we catch it and display a SnackBar with the error. Using ScaffoldMessenger.of(context).showSnackBar(...) is the recommended way to show feedback
docs.flutter.dev
.

Example widget code (simplified):

ElevatedButton(
  onPressed: _onStartCapture,
  child: Text("Start Capture"),
),


The _onStartCapture method above handles the logic described.

CaptureScreen

The CaptureScreen shows the camera view and a button for capturing frames. When the user taps Capture, we call ArCoreService.captureFrame(sessionId, viewLabel) and process the result. For example:

class CaptureScreen extends StatefulWidget {
  final Session session;
  CaptureScreen({required this.session});
  // ...
}

class _CaptureScreenState extends State<CaptureScreen> {
  bool isCapturing = false;

  Future<void> _onCaptureFrame() async {
    if (isCapturing) return;
    setState(() => isCapturing = true);

    try {
      final result = await ArCoreService.captureFrame(
        widget.session.id, viewLabel);
      // Convert timestamp from nanoseconds if provided
      final timestamp = result.timestampNs != null
          ? DateTime.fromMillisecondsSinceEpoch(result.timestampNs ~/ 1000000)
          : DateTime.now();
      // Build a FrameCapture object
      final frame = FrameCapture(
        id: result.frameId,
        timestamp: timestamp,
        viewLabel: viewLabel,
        imagePath: result.imagePath,
        metaPath: result.metaPath,
      );
      // Add to session frames
      setState(() {
        widget.session.frames.add(frame);
      });
      // Show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Captured frame ${frame.id}'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture failed: $e'))
      );
    } finally {
      setState(() => isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Capture (${widget.session.frames.length} frames)")),
      body: Column(
        children: [
          Expanded(
            child: /* AR camera preview widget goes here */,
          ),
          ElevatedButton(
            onPressed: isCapturing ? null : _onCaptureFrame,
            child: Text(isCapturing ? "Capturing..." : "Capture"),
          ),
        ],
      ),
    );
  }
}


Explanation:

Capture logic: The _onCaptureFrame() method sets isCapturing = true (to disable the button) and calls ArCoreService.captureFrame(sessionId, viewLabel). It expects a result with fields frameId, timestampNs (nanoseconds), imagePath, and metaPath.

Building FrameCapture: We convert timestampNs to a Dart DateTime (milliseconds since epoch). We then create a FrameCapture object (assuming such a model exists) and append it to session.frames.

UI update: After capturing, we call setState to update the frame count in the UI (shown in the AppBar title above) and possibly show a thumbnail preview. We also show a SnackBar via ScaffoldMessenger.of(context).showSnackBar(...)
docs.flutter.dev
 to inform the user.

Button disabling: While a capture is in progress, isCapturing is true and the button’s onPressed is set to null, disabling it. This prevents duplicate taps.

For thumbnail preview, you could add an Image.file(File(frame.imagePath)) widget. Flutter’s Image.file constructor displays an image from a file
api.flutter.dev
. For example, to show the most recent frame thumbnail:

if (widget.session.frames.isNotEmpty) ...[
  Padding(padding: EdgeInsets.symmetric(vertical: 8),
    child: Image.file(
      File(widget.session.frames.last.imagePath),
      height: 100, width: 100, fit: BoxFit.cover),
  ),
]


This uses File from dart:io and Image.file
api.flutter.dev
 to load the image.

SessionSummaryScreen

In SessionSummaryScreen, we display all captured frames and handle session completion.

Displaying frames: If session.frames is empty, show a message like "No frames captured yet". Otherwise, display thumbnails using Image.file(File(frame.imagePath)) for each frame. For example:

class SessionSummaryScreen extends StatelessWidget {
  final Session session;
  SessionSummaryScreen({required this.session});
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Session Summary")),
      body: session.frames.isEmpty
          ? Center(child: Text("No frames captured yet"))
          : GridView.builder(
              padding: EdgeInsets.all(16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: session.frames.length,
              itemBuilder: (context, index) {
                final frame = session.frames[index];
                return Image.file(
                  File(frame.imagePath),
                  fit: BoxFit.cover,
                );
              },
            ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.all(16),
        child: ElevatedButton(
          onPressed: () async {
            // Finish session
            await ArCoreService.endSession();
            await writeSessionIndexToDisk(session);
            // Return to home
            Navigator.of(context).popUntil((route) => route.isFirst);
          },
          child: Text("Finish Session"),
        ),
      ),
    );
  }
}


Key points:

Finish session: When the user taps Finish Session, we call ArCoreService.endSession() (to close the AR session) and then call writeSessionIndexToDisk(session) to save the metadata. Finally, we navigate back to the home screen (popping all intermediate routes).

Thumbnails: We use a GridView of Image.file(...) to show each frame’s image. The Image.file constructor is documented as creating a widget from a File
api.flutter.dev
.

No frames: If session.frames is empty, we show a simple text message in the center.

Writing session_meta.json to Disk

We implement writeSessionIndexToDisk(session) using Dart’s I/O libraries. We typically use the path_provider plugin to locate a directory (e.g. the app’s documents directory)
docs.flutter.dev
. Then we build a JSON map and write it with File.writeAsString and jsonEncode
docs.flutter.dev
. For example:

import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';

Future<void> writeSessionIndexToDisk(Session session) async {
  // Determine base directory (e.g. app documents directory)
  final dir = await getApplicationDocumentsDirectory(); //:contentReference[oaicite:8]{index=8}
  // Optionally, create a subfolder for the session
  final sessionDir = Directory('${dir.path}/${session.id}');
  if (!await sessionDir.exists()) {
    await sessionDir.create(recursive: true);
  }
  final file = File('${sessionDir.path}/session_meta.json');
  
  // Build JSON structure
  final jsonData = {
    'sessionId': session.id,
    'animalId': session.animalId,
    'notes': session.notes,
    'createdAt': session.createdAt.toIso8601String(),
    'frames': session.frames.map((f) => {
      'id': f.id,
      'viewLabel': f.viewLabel,
      'timestamp': f.timestamp.toIso8601String(),
      'imagePath': f.imagePath,
      'metaPath': f.metaPath,
    }).toList(),
  };
  // Write JSON to file
  await file.writeAsString(jsonEncode(jsonData)); //:contentReference[oaicite:9]{index=9}
}


Notes on paths:

We used getApplicationDocumentsDirectory()
docs.flutter.dev
 as the base. On Android this maps to internal app storage. If the native ARCore code saved images under external storage (e.g. getExternalFilesDir(null)), you may want to align with that. For example, getExternalStorageDirectory() in Flutter corresponds to getExternalFilesDir(null) on Android
pub.dev
. Ensure that imagePath and metaPath returned by ArCoreService point to the same directory. You might need to create subfolders accordingly.

The session_meta.json file includes the session metadata and an array of frames. We use jsonEncode to convert our Dart map to a JSON string, then writeAsString to save it
docs.flutter.dev
.

Summary of Changes

DeviceCheckScreen: Calls ArCoreService.checkSupport() on init, displays ARCore/depth support flags, shows a warning if unsupported, and disables the Continue button accordingly.

SessionSetupScreen: Generates a timestamped session ID, calls ArCoreService.startSession(sessionId), and on success constructs a Session object and navigates to CaptureScreen; on failure shows a SnackBar with the error.

CaptureScreen: Implements a Capture button that calls ArCoreService.captureFrame(sessionId, viewLabel). Builds a FrameCapture with id, timestamp, viewLabel, imagePath, and metaPath from the result. Appends the frame to session.frames, updates the UI count and thumbnail, shows a SnackBar on success or failure, and disables the button while capturing.

SessionSummaryScreen: Shows thumbnails for each frame using Image.file(File(path))
api.flutter.dev
 (or a “No frames” message if empty). On finishing, calls ArCoreService.endSession(), then writeSessionIndexToDisk(session), and returns to the home screen.

writeSessionIndexToDisk: Uses path_provider to get a directory
docs.flutter.dev
, creates (or uses) a subfolder for the session, and writes a session_meta.json with all required fields (using jsonEncode and File.writeAsString
docs.flutter.dev
). Ensure the paths align with where the native code saved images – e.g. using getExternalStorageDirectory() on Flutter if native used getExternalFilesDir(null)
pub.dev
.

Each of these code snippets should integrate with your existing Step 1/Step 2 code. The key is to match the file paths (image and meta) between Flutter and native sides and to handle asynchronous calls to the platform channel correctly. For example, if the ARCoreService returns absolute paths for images, use the same paths to load the images (with Image.file) and to write the JSON. Flutter’s file I/O APIs (e.g. File and jsonEncode) are documented in the Flutter cookbook
docs.flutter.dev
docs.flutter.dev
, and standard Flutter widgets like SnackBar and Image.file can be used as shown above
docs.flutter.dev
api.flutter.dev
.

Sources: Flutter’s documentation on file I/O and SnackBars
docs.flutter.dev
docs.flutter.dev
docs.flutter.dev
, Flutter API docs for Image.file
api.flutter.dev
, and Google’s ARCore docs on checking depth support
developers.google.com
.