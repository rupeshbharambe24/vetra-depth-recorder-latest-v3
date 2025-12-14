package com.example.vetra_depth_recorder

import android.content.Context
import android.view.View
import io.flutter.plugin.platform.PlatformView
import android.opengl.GLSurfaceView

class NativeArView(
    context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?,
    private val arEngine: VetraArCoreEngine
) : PlatformView {

    private val surfaceView: GLSurfaceView = GLSurfaceView(context)

    init {
        // We need to pass this surface view to the engine so it can set up the renderer
        arEngine.setSurfaceView(surfaceView)
    }

    override fun getView(): View {
        return surfaceView
    }

    override fun dispose() {
        // Cleanup handled by engine or activity lifecycle
    }
}
