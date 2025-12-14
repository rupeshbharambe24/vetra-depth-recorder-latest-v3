import 'package:flutter/material.dart';

import 'package:permission_handler/permission_handler.dart';

import '../../services/arcore_service.dart';

class DeviceCheckScreen extends StatefulWidget {
  const DeviceCheckScreen({super.key});

  @override
  State<DeviceCheckScreen> createState() => _DeviceCheckScreenState();
}

class _DeviceCheckScreenState extends State<DeviceCheckScreen> {
  final ArCoreService _arCoreService = ArCoreService();
  ArCoreSupportInfo? _supportInfo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadSupport();
  }

  Future<void> _loadSupport() async {
    // Request camera permission first
    final status = await Permission.camera.request();
    
    if (status.isGranted) {
      final info = await _arCoreService.checkSupport();
      if (!mounted) return;
      setState(() {
        _supportInfo = info;
        _loading = false;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _supportInfo = ArCoreSupportInfo(
          arcoreAvailable: false,
          depthSupported: false,
          message: 'Camera permission is required for AR features',
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final support = _supportInfo;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VETRA Depth Recorder'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo
            Image.asset(
              'assets/images/logo.png',
              height: 120,
            ),
            const SizedBox(height: 32),
            if (_loading)
              const CircularProgressIndicator()
            else ...[
              Text("ARCore support: ${support?.arcoreAvailable == true ? 'Yes' : 'No'}"),
              Text("Depth API support: ${support?.depthSupported == true ? 'Yes' : 'No'}"),
              if (support?.arcoreAvailable != true)
                const Text(
                  "ARCore is not supported on this device!",
                  style: TextStyle(color: Colors.red),
                )
              else if (support?.depthSupported != true)
                const Text(
                  "RGB Only Mode - Depth features disabled",
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
            ],
            const SizedBox(height: 48), // Space between status and buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_loading || support?.arcoreAvailable != true)
                          ? null
                          : () => Navigator.pushNamed(context, '/session_setup', arguments: {'enableDepth': true}),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('Continue (With Depth)', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                  if (support?.depthSupported == true) ...[
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: (_loading || support?.arcoreAvailable != true)
                            ? null
                            : () => Navigator.pushNamed(context, '/no_depth_session_setup'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.orange,
                          side: const BorderSide(color: Colors.orange),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Continue without Depth API', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pushNamed(context, '/data_list'),
                      style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: const Text('View Saved Data', style: TextStyle(fontSize: 16)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
