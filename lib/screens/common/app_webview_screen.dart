import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/dtext.dart';

/// شاشة متصفح الويب المدمج داخل التطبيق (In-App Web Viewer)
/// تعرض صفحات الويب وروابط الإعلانات والإشعارات بسلاسة وتتيح فتحها في متصفح خارجي
class AppWebViewScreen extends StatefulWidget {
  final String url;
  final String? title;

  const AppWebViewScreen({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<AppWebViewScreen> createState() => _AppWebViewScreenState();
}

class _AppWebViewScreenState extends State<AppWebViewScreen> {
  late final WebViewController _controller;
  int _progress = 0;
  bool _hasError = false;
  String _pageTitle = '';

  @override
  void initState() {
    super.initState();
    _pageTitle = widget.title ?? 'صفحة الويب';
    _initController();
  }

  void _initController() {
    _hasError = false;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF16151A))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _hasError = false;
                _progress = 10;
              });
            }
          },
          onPageFinished: (_) async {
            if (mounted) {
              setState(() => _progress = 100);
              try {
                final title = await _controller.getTitle();
                if (title != null && title.isNotEmpty && (widget.title == null || widget.title!.isEmpty)) {
                  setState(() => _pageTitle = title);
                }
              } catch (_) {}
            }
          },
          onWebResourceError: (error) {
            debugPrint('[AppWebView] Error: ${error.description}');
            if (mounted) setState(() => _hasError = true);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.startsWith('http://') || url.startsWith('https://')) {
              return NavigationDecision.navigate;
            }
            // فتح الروابط المخصصة في تطبيقاتها الخارجية (مثل تلغرام، واتساب، الخ)
            try {
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            } catch (_) {}
            return NavigationDecision.prevent;
          },
        ),
      );

    final cleanUrl = widget.url.trim();
    if (cleanUrl.isNotEmpty) {
      _controller.loadRequest(Uri.parse(cleanUrl));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16151A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1528),
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            DText(
              _pageTitle.isNotEmpty ? _pageTitle : 'متصفح التطبيق',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            DText(
              widget.url,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 22),
            tooltip: 'إعادة تحميل',
            onPressed: () => _controller.reload(),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser_rounded, color: Color(0xFFFFD700), size: 22),
            tooltip: 'فتح في المتصفح الخارجي',
            onPressed: () async {
              final uri = Uri.tryParse(widget.url);
              if (uri != null) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(2.5),
                child: LinearProgressIndicator(
                  value: _progress / 100.0,
                  backgroundColor: Colors.transparent,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                  minHeight: 2.5,
                ),
              )
            : null,
      ),
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 64, color: Colors.white38),
                    const SizedBox(height: 16),
                    const DText(
                      'تعذر تحميل الصفحة المطلوبة',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DText(
                      widget.url,
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFD700),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      onPressed: _initController,
                      icon: const Icon(Icons.refresh),
                      label: const DText('إعادة المحاولة', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            )
          : WebViewWidget(controller: _controller),
    );
  }
}
