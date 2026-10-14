import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../providers/user_provider.dart';
import '../../providers/locale_provider.dart';
import '../../services/dynamic_config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/supabase_config.dart';


class CpWebViewScreen extends StatefulWidget {
  const CpWebViewScreen({super.key});

  @override
  State<CpWebViewScreen> createState() => _CpWebViewScreenState();
}

class _CpWebViewScreenState extends State<CpWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String _uid = '';
  String _token = '';
  String _lang = 'en';
  final String _roomId = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final cfg = DynamicConfigService();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;

    final baseUrl = cfg.cpWebUrl.isNotEmpty
        ? cfg.cpWebUrl
        : 'https://app.ayomet.com/cp.html';

    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    _uid = user?.uid ?? '';
    _lang = localeProvider.locale?.languageCode ?? 'en';
    final session = await _getSessionToken();
    _token = session ?? '';
    // نسمح فقط بالتنقل ضمن النطاق الموثوق المُهيأ من اللوحة، ونمنع إعادة
    // التوجيه إلى أي نطاق آخر (يمنع التصيد/حقن النصوص الخبيثة في WebView).
    final allowedHost = Uri.tryParse(baseUrl)?.host ?? '';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _injectEarly();
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: (request) {
            final url = request.url;
            final uri = Uri.tryParse(url);
            final schemeAllowed = uri?.scheme == 'https';
            final hostAllowed = uri?.host == allowedHost;
            if (allowedHost.isEmpty || (schemeAllowed && hostAllowed)) {
              return NavigationDecision.navigate;
            }
            if (!schemeAllowed) {
              // ترقية http إلى https إذا كان نفس النطاق
              final upgraded = uri != null && uri.host == allowedHost
                  ? url.replaceFirst('http://', 'https://')
                  : url;
              if (upgraded != url) {
                _controller.loadRequest(Uri.parse(upgraded));
                return NavigationDecision.prevent;
              }
            }
            print('[cp-webview] blocking navigation to: $url (allowed: $allowedHost)');
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onJsMessage,
      )
      ..loadRequest(Uri.parse(baseUrl));
  }

  Future<void> _injectEarly() async {
    if (_uid.isEmpty) return;
    final js = '''
      try {
        sessionStorage.setItem('uid', '$_uid');
        sessionStorage.setItem('ticket', '$_token');
        sessionStorage.setItem('language', '$_lang');
        sessionStorage.setItem('roomId', '$_roomId');
        if (!window.flutter_inappwebview) {
          var cbMap = {getUid:'uid', getTicket:'ticket', getLanguage:'lang', getRoomId:'roomId'};
          window.flutter_inappwebview = {
            callHandler: function(action, data) {
              var cbName = cbMap[action] || action;
              setTimeout(function() {
                if (window.native && typeof window.native[cbName] === 'function')
                  window.native[cbName]('');
              }, 200);
              return Promise.resolve('');
            }
          };
        }
      } catch(e) {}
    ''';
    await _controller.runJavaScript(js);
  }

  Future<String?> _getSessionToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('supabase_auth_token') ?? SupabaseConfig.anonKey;
    } catch (_) {
      return SupabaseConfig.anonKey;
    }
  }

  void _onJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final action = data['action'] as String?;
      final callback = data['callback'] as String?;

      switch (action) {
        case 'getUid':
          _jsReply(callback, _uid);
          break;
        case 'getTicket':
          _jsReply(callback, _token);
          break;
        case 'getLanguage':
          _jsReply(callback, _lang);
          break;
        case 'getRoomId':
          _jsReply(callback, _roomId);
          break;
        case 'closeWebView':
          if (mounted) Navigator.pop(context);
          break;
        case 'showLoading':
          if (mounted) setState(() => _loading = true);
          break;
        case 'closeLoading':
          if (mounted) setState(() => _loading = false);
          break;
        case 'openRechargePopup':
          _showToast('Recharge');
          break;
        case 'gift_sent':
          _showToast('تم إرسال الهدية بنجاح');
          break;
        case 'navigate_back':
          if (mounted) Navigator.pop(context);
          break;
        case 'error':
          _showToast(data['message'] as String? ?? 'حدث خطأ');
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  Future<void> _jsReply(String? callback, String value) async {
    if (callback == null || callback.isEmpty) return;
    final escaped = value.replaceAll("'", "\\'");
    await _controller.runJavaScript("$callback('$escaped')");
  }

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF806C9D),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFf9d5e8),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF806C9D)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'CP 💑',
          style: const TextStyle(
            color: Color(0xFFd63384),
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFd63384)),
            ),
        ],
      ),
    );
  }
}
