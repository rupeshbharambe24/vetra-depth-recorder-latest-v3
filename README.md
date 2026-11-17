# VETRA Depth Recorder

A Flutter + native Android app that captures **synchronized RGB + depth frames** using Google's **ARCore Depth API**, packages them into a per-session bundle, and exports them as a ZIP for downstream processing. Built as a depth-capture prototype for the VETRA cattle/buffalo type-classification pipeline.

## What it does

For each capture session:

1. Initializes an ARCore session and checks whether the device supports `Config.DepthMode.AUTOMATIC`.
2. Streams a throttled center-depth value (≤5 Hz) to the Flutter UI for an overlay readout.
3. On `captureFrame`, acquires:
   - `color.jpg` — the camera image.
   - `depth.bin` — raw 16-bit depth (`uint16` little-endian, `width * height * 2` bytes), copied from the `DEPTH16` plane with stride-correct row reads.
   - `meta.json` — per-frame timestamp, view label, intrinsics (focal length, principal point, image dimensions), and 4x4 camera pose.
4. Saves frames under `/Android/data/<package>/files/VETRA_DATA/session_<id>/frame_NNNN/`.
5. Exports the session as a ZIP via `share_plus`.

A sample session ([`dummy_session/`](dummy_session/)) shows the exported on-disk format (three frames with `color.jpg`, `depth.bin`, `meta.json`).

## Architecture

```
Flutter (UI Layer)
    │
    │  MethodChannel: vetra_depth_recorder/arcore
    │  Methods: checkSupport, startSession, captureFrame, endSession
    │  EventChannel: centerDepthStream
    │
    ▼
Native Android (Kotlin)
    ├── VetraArCoreEngine.kt     # ARCore session + depth acquisition
    ├── NativeArView.kt          # SurfaceView for camera preview
    ├── ArCoreViewFactory.kt     # PlatformView factory
    ├── MainActivity.kt          # MethodChannel + EventChannel registration
    └── rendering/
        └── BackgroundRenderer.kt
```

Key Kotlin specifics (also documented in `depth.md` and `steps/`):

- Always check `session.isDepthModeSupported(...)` before enabling depth.
- `frame.acquireDepthImage16Bits()` — must be `close()`d in a `finally`. Catch `NotYetAvailableException` for the first few frames.
- `DEPTH16` buffer reads must use `plane.rowStride` and `plane.pixelStride` — naïve linear copies will misalign rows.
- Depth intrinsics scaled to color-camera intrinsics for cross-modality alignment.

## Project Structure

```
vetra-depth-recorder/
├── lib/
│   ├── main.dart
│   ├── services/
│   │   ├── arcore_service.dart       # MethodChannel client
│   │   ├── session_storage.dart      # Session/frame persistence
│   │   └── session_exporter.dart     # ZIP export via share_plus
│   ├── features/                     # UI features (capture, sessions, etc.)
│   ├── models/, routes/, theme/
├── android/app/src/main/kotlin/com/example/vetra_depth_recorder/
│   ├── VetraArCoreEngine.kt
│   ├── NativeArView.kt
│   ├── ArCoreViewFactory.kt
│   ├── MainActivity.kt
│   └── rendering/BackgroundRenderer.kt
├── ios/, linux/, macos/, windows/, web/
├── steps/                            # Step-by-step integration notes
├── depth.md                          # Detailed ARCore Depth API technical guide
├── dummy_session/                    # Example session data for testing
├── pubspec.yaml
├── analysis_options.yaml
└── LICENSE
```

## Setup

```bash
git clone https://github.com/rupeshbharambe24/vetra-depth-recorder-latest-v3.git
cd vetra-depth-recorder-latest-v3

flutter pub get
flutter run                       # On an ARCore-supported Android device
```

ARCore must be installed/available on the test device. The list of supported devices is on the [ARCore supported devices page](https://developers.google.com/ar/devices).

## Stack

| Layer | Technology |
|-------|-----------|
| Framework | Flutter (SDK ^3.10) |
| Native | Kotlin, ARCore SDK |
| Permissions | `permission_handler` |
| Filesystem | `path_provider` |
| Export | `archive`, `share_plus` |

## Documentation

- [`depth.md`](depth.md) — full technical writeup of the ARCore Depth API integration (session config, image acquisition, stride-aware buffer reads, intrinsics scaling, sampling cadence, common pitfalls).
- [`steps/step-2.md`](steps/step-2.md) … [`steps/step-5.md`](steps/step-5.md) — incremental integration walkthrough.

## VETRA project map

VETRA (SIH 2025, Grand Finale Top 5) is split across several repositories. ML work evolved v1.1 → v2.0 → v2.2 → v3.0; the apps below consume or capture data for those models.

| Repository | What it is | Stack | Status |
|---|---|---|---|
| [VETRA-v1.1](https://github.com/rupeshbharambe24/VETRA-v1.1) | First ML experiment: 6-keypoint YOLO pose on cow images + regression models mapping keypoint distances to body measurements (cm) | Python, YOLOv8-pose, scikit-learn | Archived (ML) |
| [VETRA-v2.0](https://github.com/rupeshbharambe24/VETRA-v2.0) | Separate side- and back-view YOLOv8-pose keypoint models, focal-length scaling, measurement-extraction notebooks | Python, Ultralytics | Archived (ML) |
| [VETRA-v2.2-with-app](https://github.com/rupeshbharambe24/VETRA-v2.2-with-app) | v2 models wrapped in a first FastAPI backend + React UI (`/api/v1/process-image`) | Python, FastAPI, React | Archived (ML + app) |
| [VETRA-v3.0](https://github.com/rupeshbharambe24/VETRA-v3.0) | Final training: side (16 kp), back (10 kp) and udder-bottom (8 kp) YOLOv8n-pose models, ArUco scaling, dataset tooling | Python, Ultralytics, PyTorch | Final models |
| [VETRA---App](https://github.com/rupeshbharambe24/VETRA---App) | Final system: FastAPI backend serving the v3.0 pose models + udder U-Net/ResNet18, NDDB-style trait scoring, React web UI | FastAPI, PyTorch, React + Vite | Final (SIH 2025 finale) |
| [vetra-main-app-latest-v3](https://github.com/rupeshbharambe24/vetra-main-app-latest-v3) | Flutter field app: capture protocol, offline SQLite records, PDF reports (not yet wired to the analysis API) | Flutter, Riverpod, SQLite | Prototype |
| **[vetra-depth-recorder-latest-v3](https://github.com/rupeshbharambe24/vetra-depth-recorder-latest-v3)** (this repo) | RGB + ARCore depth capture with intrinsics, pose and ZIP export | Flutter, Kotlin, ARCore | Prototype |
| [VETRA---Depth-Recorder](https://github.com/rupeshbharambe24/VETRA---Depth-Recorder) | Earlier capture app: RGB frames + phone-sensor pose metadata (no real depth) | Expo / React Native, TypeScript | Superseded |
| [vetra-pashu-scan](https://github.com/rupeshbharambe24/vetra-pashu-scan) | Early Lovable-generated PWA UI; Supabase edge functions return mock measurements | Vite, React, Supabase | Superseded (UI prototype) |
| [pashudhan-ui](https://github.com/rupeshbharambe24/pashudhan-ui) | Fork of a teammate's Lovable UI prototype (landing page + mock prediction page) | Vite, React | Fork |

This repository supersedes the earlier Expo-based [VETRA---Depth-Recorder](https://github.com/rupeshbharambe24/VETRA---Depth-Recorder), which could not access real depth.

## License

[MIT](LICENSE) © 2025 Rupesh Bharambe
