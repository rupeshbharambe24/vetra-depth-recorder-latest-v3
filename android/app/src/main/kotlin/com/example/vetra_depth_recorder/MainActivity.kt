package com.example.vetra_depth_recorder

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "vetra_depth_recorder/arcore"
    private lateinit var arEngine: VetraArCoreEngine

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Note: In newer Flutter versions, we might need to use configureFlutterEngine instead of onCreate for MethodChannel
        // But the user provided code uses onCreate with flutterEngine property which is available in FlutterActivity
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        arEngine = VetraArCoreEngine(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkSupport" -> arEngine.checkSupport(result)
                "startSession" -> {
                    arEngine.startSession(call, result)
                }
                "captureFrame" -> {
                    val sessionId = call.argument<String>("sessionId") ?: ""
                    val viewLabel = call.argument<String>("viewLabel") ?: ""
                    arEngine.captureFrame(sessionId, viewLabel, result)
                }
                "endSession" -> {
                    arEngine.endSession()
                    result.success(null)
                }
                "getCenterDepth" -> {
                    arEngine.getCenterDepth(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
        
        flutterEngine.platformViewsController.registry.registerViewFactory("vetra_depth_recorder/ar_view", ArCoreViewFactory(arEngine))
    }
}
