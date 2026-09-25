package com.ahlalive.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import com.kurban.flutter_vap_plugin.FlutterVapViewFactory

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // ── VAP plugin (موجود مسبقاً) ──────────────────────────────
        try {
            flutterEngine.platformViewsController.registry.registerViewFactory(
                "flutter_vap_plugin",
                FlutterVapViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
        } catch (e: IllegalStateException) {
            // Already registered by GeneratedPluginRegistrant — ignore
        }
        // ── ✅ SVGA Native Plugin (جديد) ───────────────────────────
        // يُشغّل SVGAImageView الأصلي مباشرةً بدون Flutter Canvas
        try {
            flutterEngine.platformViewsController.registry.registerViewFactory(
                "svga_native_view",
                SvgaNativePlatformViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
        } catch (e: IllegalStateException) {
            // Already registered — ignore
        }
    }
}
