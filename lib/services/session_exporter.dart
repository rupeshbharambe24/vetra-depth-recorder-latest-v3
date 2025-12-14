import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/session.dart';

class SessionExporter {
  Future<void> shareSession(Session session) async {
    final zipFile = await _zipSession(session);
    if (zipFile != null) {
      await Share.shareXFiles(
        [XFile(zipFile.path)],
        text: 'Vetra Session: ${session.id}',
      );
    }
  }

  Future<void> shareSessions(List<Session> sessions) async {
    if (sessions.isEmpty) return;
    if (sessions.length == 1) {
      await shareSession(sessions.first);
      return;
    }

    final zipFile = await _zipSessions(sessions);
    if (zipFile != null) {
      await Share.shareXFiles(
        [XFile(zipFile.path)],
        text: 'Vetra Batch Export (${sessions.length} sessions)',
      );
    }
  }

  Future<File?> _zipSessions(List<Session> sessions) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;

      final encoder = ZipFileEncoder();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final zipPath = '${dir.path}/VETRA_DATA/batch_export_$timestamp.zip';
      
      encoder.create(zipPath);

      for (var session in sessions) {
        final sessionDir = Directory('${dir.path}/VETRA_DATA/session_${session.id}');
        if (await sessionDir.exists()) {
           // Add session folder to zip
           // We want the folder structure inside the zip to be session_ID/...
           await _addDirectoryToZip(encoder, sessionDir, 'session_${session.id}/');
        }
      }
      
      encoder.close();
      return File(zipPath);
    } catch (e) {
      print('Error zipping batch sessions: $e');
      return null;
    }
  }

  Future<File?> _zipSession(Session session) async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return null;

      final sessionDir = Directory('${dir.path}/VETRA_DATA/session_${session.id}');
      if (!await sessionDir.exists()) return null;

      final encoder = ZipFileEncoder();
      final zipPath = '${dir.path}/VETRA_DATA/session_${session.id}.zip';
      
      // Create zip file
      encoder.create(zipPath);
      
      // Add all files in the session directory
      // We need to recursively add files
      await _addDirectoryToZip(encoder, sessionDir, '');
      
      encoder.close();
      
      return File(zipPath);
    } catch (e) {
      print('Error zipping session: $e');
      return null;
    }
  }
  
  Future<void> _addDirectoryToZip(ZipFileEncoder encoder, Directory dir, String relativePath) async {
    final entities = dir.listSync();
    for (var entity in entities) {
      final name = entity.path.split('/').last; // or Platform.pathSeparator
      if (entity is File) {
        encoder.addFile(entity, '$relativePath$name');
      } else if (entity is Directory) {
        // Recursive add not strictly needed if we structure it flat, but frames are in subfolders
        // archive package's addDirectory might be easier but let's be explicit or use addDirectory
        // encoder.addDirectory(entity); // This usually adds the dir itself
        
        // Let's try using the built-in recursive addDirectory if available or manual
        // The simple way:
         encoder.addDirectory(entity);
      }
    }
  }
}
