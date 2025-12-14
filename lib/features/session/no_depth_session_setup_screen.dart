import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../services/arcore_service.dart';

class NoDepthSessionSetupScreen extends StatefulWidget {
  const NoDepthSessionSetupScreen({super.key});

  @override
  State<NoDepthSessionSetupScreen> createState() => _NoDepthSessionSetupScreenState();
}

class _NoDepthSessionSetupScreenState extends State<NoDepthSessionSetupScreen> {
  final TextEditingController _animalIdController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ArCoreService _arCoreService = ArCoreService();
  bool _starting = false;
  // This screen is exclusively for No-Depth flow
  final bool _enableDepth = false;

  @override
  void dispose() {
    _animalIdController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _generateSessionId() {
    final now = DateTime.now();
    final datePart =
        '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timePart =
        '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    // Distinct prefix for separate storage/filtering
    return 'session_rgb_${datePart}_$timePart';
  }

  Future<void> _startCapture() async {
    if (_starting) return;
    setState(() {
      _starting = true;
    });

    final sessionId = _generateSessionId();
    // Explicitly disable depth for this pipeline
    final started = await _arCoreService.startSession(sessionId, enableDepth: _enableDepth);
    if (!mounted) return;
    if (!started) {
      setState(() {
        _starting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start AR session (RGB Only)')),
      );
      return;
    }

    final session = Session(
      id: sessionId,
      animalId: _animalIdController.text.trim().isEmpty
          ? null
          : _animalIdController.text.trim(),
      notes:
          _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
      createdAt: DateTime.now(),
      enableDepth: _enableDepth,
    );

    // Navigate to the separate capture screen
    Navigator.pushNamed(
      context,
      '/no_depth_capture',
      arguments: session,
    );

    setState(() {
      _starting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Session (RGB Only)'),
        backgroundColor: Colors.orange.shade100, // Visual cue for different mode
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.orange.shade50,
              child: const Row(
                children: [
                   Icon(Icons.info_outline, color: Colors.orange),
                   SizedBox(width: 8),
                   Expanded(child: Text("Depth data will NOT be recorded for this session.")),
                ],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _animalIdController,
              decoration: const InputDecoration(
                labelText: 'Animal ID (optional)',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                alignLabelWithHint: true,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _starting ? null : _startCapture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange,
                      foregroundColor: Colors.white,
                    ),
                    child: _starting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text('Start RGB Capture'),
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
