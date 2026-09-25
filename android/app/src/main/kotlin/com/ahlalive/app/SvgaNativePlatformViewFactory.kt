package com.ahlalive.app

import android.content.Context
import android.view.View
import com.opensource.svgaplayer.SVGAImageView
import com.opensource.svgaplayer.SVGAParser
import com.opensource.svgaplayer.SVGAVideoEntity
import com.opensource.svgaplayer.SVGADrawable
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File
import java.net.URL

// ═══════════════════════════════════════════════════════════════════════════
// SvgaNativePlatformViewFactory
// يُسجَّل في MainActivity تحت channel id: "svga_native_view"
// يُستخدم من Flutter عبر:  AndroidView(viewType: 'svga_native_view', ...)
// ═══════════════════════════════════════════════════════════════════════════
class SvgaNativePlatformViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        val params = args as? Map<*, *> ?: emptyMap<String, Any>()
        val url   = params["url"]   as? String  ?: ""
        val loops = params["loops"] as? Boolean ?: true
        return SvgaNativeView(context, viewId, messenger, url, loops)
    }
}

class SvgaNativeView(
    private val context: Context,
    viewId: Int,
    messenger: BinaryMessenger,
    private val url: String,
    private val loops: Boolean,
) : PlatformView {

    private val svgaView: SVGAImageView = SVGAImageView(context)
    private val channel = MethodChannel(messenger, "svga_native_view_$viewId")

    init {
        // loops=0 يعني لانهائي في مكتبة SVGAPlayer
        svgaView.loops = if (loops) 0 else 1
        svgaView.clearsAfterStop = false
        loadSvga()
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "play"  -> { svgaView.startAnimation(); result.success(null) }
                "stop"  -> { svgaView.stopAnimation();  result.success(null) }
                "clear" -> {
                    svgaView.stopAnimation()
                    svgaView.setImageDrawable(null)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun loadSvga() {
        if (url.isBlank()) return
        val parser = SVGAParser(context)
        val callback = object : SVGAParser.ParseCompletion {
            override fun onComplete(videoItem: SVGAVideoEntity) {
                svgaView.setImageDrawable(SVGADrawable(videoItem))
                svgaView.startAnimation()
                channel.invokeMethod("onReady", null)
            }
            override fun onError() {
                channel.invokeMethod("onError", null)
            }
        }
        when {
            url.startsWith("http://") || url.startsWith("https://") -> {
                // تحميل من الشبكة — SVGAParser يعمل على خيط خلفي تلقائياً
                parser.decodeFromURL(URL(url), callback)
            }
            else -> {
                val file = File(url)
                if (file.exists()) {
                    // ملف محلي (من MediaCacheService)
                    parser.decodeFromInputStream(file.inputStream(), url, callback)
                } else {
                    // assets
                    try {
                        context.assets.open(url).use { stream ->
                            parser.decodeFromInputStream(stream, url, callback)
                        }
                    } catch (e: Exception) {
                        channel.invokeMethod("onError", null)
                    }
                }
            }
        }
    }

    override fun getView(): View = svgaView

    override fun dispose() {
        svgaView.stopAnimation()
        svgaView.setImageDrawable(null)
        channel.setMethodCallHandler(null)
    }
}
