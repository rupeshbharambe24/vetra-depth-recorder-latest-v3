import 'dart:async';
import 'package:flutter/material.dart';

import '../../models/frame_capture.dart';
import '../../models/session.dart';
import '../../models/frame_capture.dart';
import '../../models/session.dart';
import '../../services/arcore_service.dart';
import 'ar_core_view.dart';

class CaptureScreen extends StatefulWidget {
  const CaptureScreen({super.key});

  @override
  State<CaptureScreen> createState() => _CaptureScreenState();
}

class _CaptureScreenState extends State<CaptureScreen> {
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

  Timer? _depthTimer;
  double _currentDepth = 0.0;

  @override
  void initState() {
    super.initState();
    // Poll depth every 300ms
    _depthTimer = Timer.periodic(const Duration(milliseconds: 300), (_) {
      _updateDepth();
    });
  }

  Future<void> _updateDepth() async {
    if (!mounted || _arCoreService == null) return;
    try {
      final depth = await _arCoreService.getDepthAtCenter();
      if (mounted) {
        setState(() {
          _currentDepth = depth;
        });
      }
    } catch (e) {
      // Ignore errors (e.g. session paused)
    }
  }

  @override
  void dispose() {
    _depthTimer?.cancel();
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
        SnackBar(content: Text('Captured ${result.frameId}')),
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
        title: const Text('Capture'),
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
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                   const ArCoreView(),
                   // Crosshair
                   Center(
                     child: Icon(Icons.add, color: Colors.white.withOpacity(0.5), size: 48),
                   ),
                   // Depth Value
                   Positioned(
                     top: 16,
                     left: 0,
                     right: 0,
                     child: Center(
                       child: Container(
                         padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                         decoration: BoxDecoration(
                           color: Colors.black54,
                           borderRadius: BorderRadius.circular(20),
                         ),
                         child: Text(
                           session.enableDepth 
                             ? 'Depth: ${_currentDepth > 0 ? "${_currentDepth.toStringAsFixed(2)} m" : "Scanning..."}'
                             : 'Depth: N/A (RGB Only)',
                           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                         ),
                       ),
                     ),
                   ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: _viewLabels
                  .map(
                    (label) => ChoiceChip(
                      label: Text(label),
                      selected: _selectedViewLabel == label,
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
              'Frames captured: ${session.frames.length}',
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
            child: _capturing
                ? const CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  )
                : const Text('Capture'),
          ),
        ),
      ),
    );
  }
}
