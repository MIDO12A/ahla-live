import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../config/supabase_config.dart';
import '../../core/dtext.dart';
import '../../providers/locale_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/dynamic_config_service.dart';

/// شاشة كود الدعوة — تعمل بنظام WebView مباشر متصل بالسحابة (Vercel)
/// ومرتبط مباشرة بقاعدة بيانات Supabase (pxyqgeitjdsilgfftnyd)
/// تسحب بيانات المستخدم، الداعي، المكافآت، وقوائم الأصدقاء لحظياً.
class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String _pageTitle = 'كود الدعوة';
  String _targetUrl = '';

  @override
  void initState() {
    super.initState();
    _initWebView();
  }

  Future<void> _initWebView() async {
    final cfg = DynamicConfigService();
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;

    final uid = user?.uid ?? '';
    final customId = user?.customId.trim() ?? '';
    final nickname = user?.name.trim() ?? '';
    final avatar = user?.photoUrl.trim() ?? '';

    final localeProvider = Provider.of<LocaleProvider>(context, listen: false);
    final lang = localeProvider.locale?.languageCode ?? 'ar';

    final token = await _getSessionToken();

    final base = cfg.inviteWebUrl.isNotEmpty
        ? cfg.inviteWebUrl
        : 'https://zero-invite.vercel.app/#/invite-register';

    final uri = Uri.parse(base);
    final queryParams = Map<String, String>.from(uri.queryParameters);
    queryParams['userId'] = uid;
    queryParams['account'] = customId.isNotEmpty ? customId : uid;
    queryParams['nickname'] = nickname;
    queryParams['avatar'] = avatar;
    queryParams['token'] = token;
    queryParams['lang'] = lang;
    queryParams['client'] = 'Android';
    queryParams['origin'] = 'ZERO_APP';

    final fullUri = uri.replace(queryParameters: queryParams);
    _targetUrl = fullUri.toString();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF140D2F))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            _injectBridge(uid, customId, nickname, avatar, token, lang);
          },
          onPageFinished: (_) {
            _injectBridge(uid, customId, nickname, avatar, token, lang);
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            debugPrint('[InviteWebView] Resource error: ' + error.description);
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _handleJsMessage,
      )
      ..loadRequest(Uri.parse(_targetUrl));
  }

  Future<String> _getSessionToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('supabase_auth_token') ?? SupabaseConfig.anonKey;
    } catch (_) {
      return SupabaseConfig.anonKey;
    }
  }

  Future<void> _injectBridge(
    String uid,
    String customId,
    String nickname,
    String avatar,
    String token,
    String lang,
  ) async {
    final account = customId.isNotEmpty ? customId : uid;
    final authData = jsonEncode({
      'userId': uid,
      'account': account,
      'nickname': nickname,
      'avatar': avatar,
      'Authorization': 'Bearer ' + token,
      'Req-Lang': lang,
      'Req-Client': 'Android',
      'Origin-Platform': 'ZERO_APP',
    });

    final js = '''
      try {
        window.__CURRENT_AUTH__ = $authData;
        window.__API_BASE_URL__ = "/api/";

        if (!window.app) {
          window.app = {};
        }
        window.app.getAccessOrigin = function() {
          return JSON.stringify(window.__CURRENT_AUTH__);
        };
        window.app.closeView = function() {
          if (window.FlutterBridge) {
            window.FlutterBridge.postMessage(JSON.stringify({action: "closeView"}));
          }
        };
        window.app.onCopyText = function(text) {
          if (window.FlutterBridge) {
            window.FlutterBridge.postMessage(JSON.stringify({action: "onCopyText", text: text}));
          }
        };
        window.app.shareInvite = function(text) {
          if (window.FlutterBridge) {
            window.FlutterBridge.postMessage(JSON.stringify({action: "shareInvite", text: text}));
          }
        };
      } catch (e) {
        console.error("Bridge injection error:", e);
      }
    ''';
    await _controller.runJavaScript(js);
  }

  void _handleJsMessage(JavaScriptMessage message) {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      final action = data['action'] as String?;

      switch (action) {
        case 'closeView':
          if (mounted) Navigator.pop(context);
          break;

        case 'onCopyText':
          final text = data['text']?.toString() ?? '';
          if (text.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: text));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: DText('تم نسخ كود الدعوة بنجاح'),
                duration: Duration(seconds: 2),
                backgroundColor: Color(0xFF6C27DF),
              ),
            );
          }
          break;

        case 'shareInvite':
          final text = data['text']?.toString() ?? '';
          if (text.isNotEmpty) {
            SharePlus.instance.share(ShareParams(
              text: text,
              subject: 'دعوة للانضمام',
            ));
          }
          break;

        case 'setTitle':
          final title = data['title']?.toString() ?? '';
          if (title.isNotEmpty && mounted) {
            setState(() => _pageTitle = title);
          }
          break;
      }
    } catch (e) {
      debugPrint('[InviteWebView] Message handling error: ' + e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          _controller.goBack();
        } else {
          if (mounted) Navigator.pop(context);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF140D2F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF140D2F),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () async {
              if (await _controller.canGoBack()) {
                _controller.goBack();
              } else {
                if (mounted) Navigator.pop(context);
              }
            },
          ),
          title: DText(
            _pageTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 22),
              tooltip: 'تحديث',
              onPressed: () {
                setState(() => _loading = true);
                _controller.reload();
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_loading)
              Container(
                color: const Color(0xFF140D2F),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
