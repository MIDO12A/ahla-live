import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../providers/user_provider.dart';
import '../../providers/locale_provider.dart';
import 'package:zero/core/dtext.dart';

class LudoGameScreen extends StatefulWidget {
  final String roomId;

  const LudoGameScreen({super.key, required this.roomId});

  @override
  State<LudoGameScreen> createState() => _LudoGameScreenState();
}

class _LudoGameScreenState extends State<LudoGameScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  String _buildUrl() {
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid ?? '';
    final lang = Provider.of<LocaleProvider>(context, listen: false).locale?.languageCode ?? 'ar';
    final userId = Uri.encodeComponent(uid);
    final roomId = Uri.encodeComponent(widget.roomId);
    return 'https://web-mobile-rust.vercel.app/index.html'
        '?appChannel=goview'
        '&isDataByUrl=true'
        '&userId=$userId'
        '&roomId=$roomId'
        '&appId=1001'
        '&appKey=app_key_c052suexgl68'
        '&gameMode=3'
        '&language=$lang'
        '&role=2';
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF120B17))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _loading = true; _failed = false; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == true && mounted) {
              setState(() { _loading = false; _failed = true; });
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (uri == null) return NavigationDecision.prevent;
            if (uri.scheme == 'https' || uri.scheme == 'http') {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..loadRequest(Uri.parse(_buildUrl()));
  }

  void _reload() {
    setState(() { _loading = true; _failed = false; });
    _controller.loadRequest(Uri.parse(_buildUrl()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF120B17),
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              const ColoredBox(
                color: Color(0xFF120B17),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFFFD700)),
                ),
              ),
            if (_failed)
              ColoredBox(
                color: const Color(0xFF120B17),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off_rounded, color: Colors.white38, size: 56),
                      const SizedBox(height: 12),
                      const DText(
                        'تعذر تحميل اللعبة',
                        style: TextStyle(color: Colors.white70, fontSize: 15),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _reload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFD700),
                          foregroundColor: Colors.black,
                        ),
                        child: const DText('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              top: 8,
              left: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
