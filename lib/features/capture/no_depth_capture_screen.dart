import 'package:flutter/material.dart';

import '../../models/frame_capture.dart';
import '../../models/session.dart';
import '../../services/arcore_service.dart';
import '../capture/ar_core_view.dart';

class NoDepthCaptureScreen extends StatefulWidget {
  const NoDepthCaptureScreen({super.key});

  @override
  State<NoDepthCaptureScreen> createState() => _NoDepthCaptureScreenState();
}

class _NoDepthCaptureScreenState extends State<NoDepthCaptureScreen> {
  final List<String> _viewLabels = [
    'left_side',
    'right_side',
    'front',
    'rear',
    'other',
  ];

  late String _selectedViewLabel = _viewLabels.first;
  Session? _session;
  final ArCoreService _arCoreService = ArCoreService();
  bool _capturing = false;

  @override
  void dispose() {
    // Ensure session is ended when leaving the screen
    _arCoreService.endSession();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_session == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Session) {
        _session = args;
      }
    }
  }

  Future<void> _captureFrame() async {
    if (_capturing) return;

    final session = _session;
    if (session == null) return;

    setState(() {
      _capturing = true;
    });

    try {
      final result = await _arCoreService.captureFrame(
        session.id,
        _selectedViewLabel,
      );

      final frame = FrameCapture(
        id: result.frameId.toString(),
        viewLabel: _selectedViewLabel,
        timestamp: DateTime.now(),
        imagePath: result.imagePath.isEmpty ? null : result.imagePath,
        metaPath: result.metaPath.isEmpty ? null : result.metaPath,
      );

      setState(() {
        session.frames.add(frame);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Captured RGB Frame ${result.frameId}'),
          backgroundColor: Colors.orange,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _capturing = false;
        });
      }
    }
  }

  void _goToSummary() {
    final session = _session;
    if (session == null) return;
    Navigator.pushNamed(
      context,
      '/session_summary',
      arguments: session,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;

    if (session == null) {
      return const Scaffold(
        body: Center(child: Text('No session provided')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture (RGB Only)'),
        backgroundColor: Colors.orange.shade100,
        actions: [
          TextButton(
            onPressed: _goToSummary,
            child: const Text('Summary'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 400, 
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.orange, width: 2), // Visual differentiation
              ),
              clipBehavior: Clip.hardEdge,
              child: const ArCoreView(),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _viewLabels
                  .map(
                    (label) => ChoiceChip(
                      label: Text(label),
                      selected: _selectedViewLabel == label,
                      selectedColor: Colors.orange.shade200,
                      onSelected: (_) {
                        setState(() {
                          _selectedViewLabel = label;
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            Text(
              'Frames captured (RGB): ${session.frames.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SizedBox(
          width: 96,
          height: 96,
          child: FloatingActionButton.large(
            onPressed: _capturing ? null : _captureFrame,
            backgroundColor: Colors.orange, // Distinct color
            child: _capturing
                ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                : const Icon(Icons.camera, color: Colors.white),
          ),
        ),
      ),
    );
  }
}
