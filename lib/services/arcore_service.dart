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
  final String metaPath;
  final Intrinsics colorIntrinsics;
  final Intrinsics? depthIntrinsics;
  final PoseData pose;
  final String depthFormat;
  ArFrameResult({
    required this.frameId,
    required this.timestampNs,
    required this.viewLabel,
    required this.imagePath,
    this.depthPath,
    required this.metaPath,
    required this.colorIntrinsics,
    this.depthIntrinsics,
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
      metaPath: json['metaPath'] as String? ?? '',
      colorIntrinsics: Intrinsics.fromJson(Map<String, dynamic>.from(json['colorIntrinsics'])),
      depthIntrinsics: json['depthIntrinsics'] == null
          ? null
          : Intrinsics.fromJson(Map<String, dynamic>.from(json['depthIntrinsics'])),
      pose: PoseData.fromJson(Map<String, dynamic>.from(json['pose'])),
      depthFormat: json['depthFormat'] as String,
    );
  }
}

class Intrinsics {
  final double fx, fy, cx, cy;
  final int width, height;
  Intrinsics(this.fx, this.fy, this.cx, this.cy, this.width, this.height);
  factory Intrinsics.fromJson(Map<String, dynamic> json) {
    return Intrinsics(
      (json['fx'] as num).toDouble(),
      (json['fy'] as num).toDouble(),
      (json['cx'] as num).toDouble(),
      (json['cy'] as num).toDouble(),
      json['width'] as int,
      json['height'] as int,
    );
  }
}

class PoseData {
  final List<double> matrix;    // 16 floats (row-major 4x4 matrix)
  final List<double> quaternion; // 4 floats (x, y, z, w)
  final List<double> translation; // 3 floats (meters)
  final String convention;
  PoseData(this.matrix, this.quaternion, this.translation, this.convention);
  factory PoseData.fromJson(Map<String, dynamic> json) {
    return PoseData(
      List<double>.from(json['matrix_4x4_row_major'].map((v) => v.toDouble())),
      List<double>.from(json['quaternion_xyzw'].map((v) => v.toDouble())),
      List<double>.from(json['translation_m'].map((v) => v.toDouble())),
      json['convention'] as String? ?? 'camera_to_world',
    );
  }
}

class ArCoreService {
  static const _channel = MethodChannel('vetra_depth_recorder/arcore');

  /// Check device support for ARCore & Depth
  Future<ArCoreSupportInfo> checkSupport() async {
    final result = await _channel.invokeMethod<Map>('checkSupport');
    if (result == null) {
      throw Exception('Failed to get support info');
    }
    return ArCoreSupportInfo.fromJson(Map<String, dynamic>.from(result));
  }

  /// Start a new ARCore session with given sessionId
  Future<bool> startSession(String sessionId, {bool enableDepth = true}) async {
    return await _channel.invokeMethod<bool>(
      'startSession', {
        'sessionId': sessionId,
        'enableDepth': enableDepth,
      }) ?? false;
  }

  /// Capture one frame from ARCore, with a label for the view
  Future<ArFrameResult> captureFrame(String sessionId, String viewLabel) async {
    final result = await _channel.invokeMethod<Map>(
      'captureFrame', {'sessionId': sessionId, 'viewLabel': viewLabel});
    if (result == null) throw Exception('Failed to capture frame');
    return ArFrameResult.fromJson(Map<String, dynamic>.from(result));
  }

  /// End the current ARCore session
  Future<void> endSession() async {
    await _channel.invokeMethod('endSession');
  }
  /// Get the latest depth value at the center of the frame (in meters)
  Future<double> getDepthAtCenter() async {
    final result = await _channel.invokeMethod<double>('getCenterDepth');
    return result ?? 0.0;
  }
}
