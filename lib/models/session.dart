import 'frame_capture.dart';

class Session {
  final String id; // e.g. "session_20251203_153045"
  final String? animalId;
  final String? notes;
  final DateTime createdAt;
  final bool enableDepth;
  final List<FrameCapture> frames;

  Session({
    required this.id,
    this.animalId,
    this.notes,
    required this.createdAt,
    this.enableDepth = true,
    List<FrameCapture>? frames,
  }) : frames = frames ?? [];

  Session copyWith({
    String? id,
    String? animalId,
    String? notes,
    DateTime? createdAt,
    bool? enableDepth,
    List<FrameCapture>? frames,
  }) {
    return Session(
      id: id ?? this.id,
      animalId: animalId ?? this.animalId,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      enableDepth: enableDepth ?? this.enableDepth,
      frames: frames ?? this.frames,
    );
  }
  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: json['sessionId'] as String,
      animalId: json['animalId'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      enableDepth: json['enableDepth'] as bool? ?? true,
      frames: (json['frames'] as List<dynamic>?)
              ?.map((e) => FrameCapture.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
