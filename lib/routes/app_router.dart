import 'package:flutter/material.dart';

import 'package:flutter/material.dart';
import '../features/capture/capture_screen.dart';
import '../features/data_view/data_list_screen.dart';
import '../features/device_check/device_check_screen.dart';
import '../features/session/session_setup_screen.dart';
import '../features/session/session_summary_screen.dart';
import '../models/session.dart';
import '../features/capture/no_depth_capture_screen.dart';
import '../features/session/no_depth_session_setup_screen.dart';
import '../features/splash/splash_screen.dart';

class AppRouter {
  static const String initialRoute = '/';
  static const String deviceCheck = '/device_check';
  static const String sessionSetup = '/session_setup';
  static const String capture = '/capture';
  static const String sessionSummary = '/session_summary';
  static const String dataList = '/data_list';
  
  // New routes for independent pipeline
  static const String noDepthSessionSetup = '/no_depth_session_setup';
  static const String noDepthCapture = '/no_depth_capture';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    switch (settings.name) {
      case initialRoute:
        return MaterialPageRoute(
          builder: (_) => const SplashScreen(),
          settings: settings,
        );
      case deviceCheck:
        return MaterialPageRoute(
          builder: (_) => const DeviceCheckScreen(),
          settings: settings,
        );
      case sessionSetup:
        return MaterialPageRoute(
          builder: (_) => const SessionSetupScreen(),
          settings: settings,
        );
      case capture:
        return MaterialPageRoute(
          builder: (_) => const CaptureScreen(),
          settings: settings,
        );
      case noDepthSessionSetup:
        return MaterialPageRoute(
          builder: (_) => const NoDepthSessionSetupScreen(),
          settings: settings,
        );
      case noDepthCapture:
        return MaterialPageRoute(
          builder: (_) => const NoDepthCaptureScreen(),
          settings: settings,
        );
      case sessionSummary:
        final session = settings.arguments as Session?;
        return MaterialPageRoute(
          builder: (_) => SessionSummaryScreen(
            key: ValueKey(session?.id ?? 'session_summary'),
          ),
          settings: settings,
        );
      case dataList:
        return MaterialPageRoute(
          builder: (_) => const DataListScreen(),
          settings: settings,
        );
      default:
        return MaterialPageRoute(
          builder: (_) => const Scaffold(
            body: Center(child: Text('Route not found')),
          ),
          settings: settings,
        );
    }
  }
}
