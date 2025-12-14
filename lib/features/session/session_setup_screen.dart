import 'package:flutter/material.dart';

import '../../models/session.dart';
import '../../services/arcore_service.dart';

class SessionSetupScreen extends StatefulWidget {
  const SessionSetupScreen({super.key});

  @override
  State<SessionSetupScreen> createState() => _SessionSetupScreenState();
}

class _SessionSetupScreenState extends State<SessionSetupScreen> {
  final TextEditingController _animalIdController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final ArCoreService _arCoreService = ArCoreService();
  bool _starting = false;
  bool _enableDepth = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) { // Check if map 
      if (args.containsKey('enableDepth')) {
        _enableDepth = args['enableDepth'] as bool;
      }
    }
  }

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
    return 'session_${datePart}_$timePart';
  }

  Future<void> _startCapture() async {
    if (_starting) return;
    setState(() {
      _starting = true;
    });

    final sessionId = _generateSessionId();
    // Pass user preference for depth
    final started = await _arCoreService.startSession(sessionId, enableDepth: _enableDepth);
    if (!mounted) return;
    if (!started) {
      setState(() {
        _starting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to start AR session')),
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

    Navigator.pushNamed(
      context,
      '/capture',
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
        title: const Text('New Session'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                    child: _starting
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Start Capture'),
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
