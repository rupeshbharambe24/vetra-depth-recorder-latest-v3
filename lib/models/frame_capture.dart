class FrameCapture {
  final String id; // e.g. "frame_0001"
  final String viewLabel; // e.g. "left_side", "rear"
  final DateTime timestamp;
  final String? imagePath; // will be filled later when ARCore saves RGB
  final String? metaPath; // will be filled later when ARCore saves meta.json

  FrameCapture({
    required this.id,
    required this.viewLabel,
    required this.timestamp,
    this.imagePath,
    this.metaPath,
  });

  FrameCapture copyWith({
    String? id,
    String? viewLabel,
    DateTime? timestamp,
    String? imagePath,
    String? metaPath,
  }) {
    return FrameCapture(
      id: id ?? this.id,
      viewLabel: viewLabel ?? this.viewLabel,
      timestamp: timestamp ?? this.timestamp,
      imagePath: imagePath ?? this.imagePath,
      metaPath: metaPath ?? this.metaPath,
    );
  }
  factory FrameCapture.fromJson(Map<String, dynamic> json) {
    return FrameCapture(
      id: json['id'] as String,
      viewLabel: json['viewLabel'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      imagePath: json['imagePath'] as String?,
      metaPath: json['metaPath'] as String?,
    );
  }
}
