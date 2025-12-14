import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/session.dart';

class SessionStorage {
  Future<void> writeSessionIndexToDisk(Session session) async {
    // Determine base directory (e.g. app documents directory)
    // Note: On Android, native code might save images to getExternalFilesDir(null).
    // In Flutter, getExternalStorageDirectory() corresponds to that.
    final dir = await getExternalStorageDirectory(); 
    if (dir == null) {
      throw Exception("External storage directory not found");
    }

    // The native code creates a subfolder "VETRA_DATA/session_<sessionId>"
    // note: if sessionId already contains "session_", this implies a nested naming redundancy 
    // but we match native behavior: File(..., "VETRA_DATA/session_$sessionId")
    
    final sessionDir = Directory('${dir.path}/VETRA_DATA/session_${session.id}');
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
      'enableDepth': session.enableDepth,
      'frames': session.frames.map((f) => {
        'id': f.id,
        'viewLabel': f.viewLabel,
        'timestamp': f.timestamp.toIso8601String(),
        'imagePath': f.imagePath,
        'metaPath': f.metaPath,
      }).toList(),
    };
    
    // Write JSON to file
    await file.writeAsString(jsonEncode(jsonData));
  }

  Future<void> deleteSession(String sessionId) async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return;
    
    final sessionDir = Directory('${dir.path}/VETRA_DATA/session_$sessionId');
    if (await sessionDir.exists()) {
      await sessionDir.delete(recursive: true);
    }
  }

  Future<List<Session>> loadSessions() async {
    final dir = await getExternalStorageDirectory();
    if (dir == null) return [];

    final dataDir = Directory('${dir.path}/VETRA_DATA');
    if (!await dataDir.exists()) return [];

    final List<Session> sessions = [];
    final entities = dataDir.listSync();

    for (var entity in entities) {
      if (entity is Directory && entity.path.contains('session_')) {
        try {
          final metaFile = File('${entity.path}/session_meta.json');
          if (await metaFile.exists()) {
            final jsonStr = await metaFile.readAsString();
            final json = jsonDecode(jsonStr);
            sessions.add(Session.fromJson(json));
          } else {
            // If no meta file, create a dummy session from folder name
            final folderName = entity.path.split('/').last;
            // Handle potentially double prefix if that happens, but standard assumes session_$id
            final sessionId = folderName.replaceFirst('session_', '');
            sessions.add(Session(
              id: sessionId,
              createdAt: DateTime.now(), // Unknown date
              frames: [],
              enableDepth: !sessionId.contains('rgb'), // Infer based on ID if meta missing
            ));
          }
        } catch (e) {
          debugPrint('Error loading session from ${entity.path}: $e');
        }
      }
    }
    
    // Sort by date descending
    sessions.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sessions;
  }
}
