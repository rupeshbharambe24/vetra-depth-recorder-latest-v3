import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../models/session.dart';
import '../../services/arcore_service.dart';
import '../../services/session_storage.dart';
import '../../services/session_exporter.dart';

class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final session = args is Session ? args : null;
    final arCoreService = ArCoreService();

    if (session == null) {
      return const Scaffold(
        body: Center(child: Text('No session to summarize')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Summary'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () {
              SessionExporter().shareSession(session);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Animal ID: ${session.animalId ?? 'N/A'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Created: ${session.createdAt}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Frames',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: session.frames.length,
                itemBuilder: (context, index) {
                  final frame = session.frames[index];
                  return ListTile(
                    leading: (frame.imagePath != null &&
                            frame.imagePath!.isNotEmpty &&
                            File(frame.imagePath!).existsSync())
                        ? Image.file(
                            File(frame.imagePath!),
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.image_not_supported),
                    title: Text('${frame.id} – ${frame.viewLabel}'),
                    subtitle: Text(frame.timestamp.toString()),
                  );
                },
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pushReplacementNamed(
                        context,
                        '/capture',
                        arguments: session,
                      );
                    },
                    child: const Text('Back to Capture'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await arCoreService.endSession();
                      try {
                        await SessionStorage().writeSessionIndexToDisk(session);
                      } catch (e) {
                        debugPrint('Error saving session: $e');
                        // Continue to finish even if save fails, or show error?
                        // For now just log it.
                      }
                      if (!context.mounted) return;
                      Navigator.popUntil(context, (route) => route.isFirst);
                    },
                    child: const Text('Finish Session'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
