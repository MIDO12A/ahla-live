import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../config/supabase_config.dart';
import '../../providers/user_provider.dart';
import '../../services/safe_http.dart';
import '../../services/session_token_store.dart';
import '../../services/supabase_data_service.dart';
import '../../services/global_banner_service.dart';
import 'package:uuid/uuid.dart';
import '../wallet/wallet_main_screen.dart';
import 'package:zero/core/dtext.dart';

/// لعبة ألفا (Alfa Lucky 777) — لعبة H5 مستضافة على Vercel
/// تُفتح داخل WebView مع تمرير بيانات المستخدم كـ query params:
/// user_id, nickname, coins, avatar, win_rate, chips
class AlfaGameScreen extends StatefulWidget {
  const AlfaGameScreen({
    super.key,
    this.gameId = 'fe-game-lucky777',
    this.host = _defaultHost,
    this.appKey = _defaultAppKey,
    this.poolId,
    this.title,
    this.roomId,
    this.viewMode,
    this.urlTemplate,
    this.onGameRatio,
    this.onRequestClose,
    this.iconAsset,
  });

  /// معرّف اللعبة على منصة Alfa (fe-game-lucky777, fe-game-super77, ...)
  final String gameId;

  /// مضيف المنصة — الافتراضي alfa-game-rosy.vercel.app،
  /// وألعاب UTD/Alfa الجديدة على alfanexso.tech
  final String host;

  /// مفتاح التطبيق/التاجر على المنصة (app_key في رابط /play/)
  final String appKey;

  /// معرّف داخلي منفصل للـ pool/records — عندما تكون gameId
  /// مشتركة بين منصتين (مثل fe-game-super77 على alfanexso)
  final String? poolId;

  /// عنوان مخصص لشريط اللعبة — يُستخدم بدل «لعبة الحظ 777»
  final String? title;

  /// معرف الغرفة — يُرسل كـ roomId في رابط تشغيل اللعبة (بروتوكول StyeParty)
  final String? roomId;

  /// وضع عرض اللعبة — 'full' تملأ الشاشة، 'half' نصف الشاشة.
  /// يختلف حسب اللعبة حسب مواصفات مزوّد الألعاب.
  final String? viewMode;

  /// يُستدعى بمجرد ما الـ JS يقيس نسبة أبعاد canvas بتاع اللعبة،
  /// عشان الصندوق يتحجم تلقائياً على شكل اللعبة بدون ما نعرف قيم view_mode.
  final ValueChanged<double>? onGameRatio;

  /// يُستدعى لما اللعبة/النظام يطلب إغلاقها — الـ host (overlay)
  /// بيعرض دايالوج «تصغير ولا إغلاق». لو null بنعمل pop عادي.
  final VoidCallback? onRequestClose;

  /// أيقونة اللعبة للفقاعة المصغّرة ( assets/images/... ).
  final String? iconAsset;

  /// رابط تشغيل كامل بقالب من لوحة التحكم (game_links.url_template) —
  /// يدعم المتغيرات: {STYEPARTY_USER_ID} {PLAYER_TOKEN} {ROOM_ID}
  /// {GAME_ID} {APP_KEY} {UID} {TOKEN}. لو موجود يُستخدم بدل بناء
  /// الرابط الافتراضي /play/{appKey}/{gameId}.
  final String? urlTemplate;

  static const String _defaultHost = 'alfanexso.tech';
  static const String _defaultAppKey = 'alfa_key_app_ahal_377';
  static const double _defaultWinRate = 75.0;

  static const List<String> _chips = [
    '1000',
    '5000',
    '10000',
    '50000',
    '500000',
  ];

  /// صندوق يتحجم تلقائياً من قياس الـ canvas، ويتكبر لحد **الشاشة الكاملة**،
  /// مع مقبض سحب لتعديل المقاس يدوياً. الخلفية شفافة بالكامل (بدون scrim).
  static Future<void> show(BuildContext context,
      {String gameId = 'fe-game-lucky777',
      String? host,
      String? appKey,
      String? poolId,
      String? title,
      String? roomId,
      String? viewMode,
      String? urlTemplate,
      String? iconAsset,
      bool fullScreen = false}) {
    // ✅ OverlayEntry بدل showModalBottomSheet — كده نقدر نصغّر اللعبة
    //    لفقاعة عائمة من غير ما الـ WebView/اللعبة يموتوا (النتيجة
    //    والفوز بيفضلوا شغالين في الخلفية).
    final completer = Completer<void>();
    // ✅ الارتفاع الابتدائي حسب view_mode — ألعاب full تبدأ بملء الشاشة (100%)،
    //    باقي الألعاب تبدأ بـ 88% من حجم الشاشة.
    final isFull = viewMode == 'full' || fullScreen;
    final initialRatio = isFull ? 1.0 : 0.88;
    final height = ValueNotifier<double>(
        MediaQuery.of(context).size.height * initialRatio);
    final hostKey = GlobalKey<_GameOverlayHostState>();
    final gameKey = GlobalKey<_AlfaGameScreenState>();

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _GameOverlayHost(
        key: hostKey,
        height: height,
        title: title ?? 'لعبة الحظ 777',
        iconAsset: iconAsset,
        fullScreen: isFull,
        gameKey: gameKey,
        onClosed: () {
          height.dispose();
          if (!completer.isCompleted) completer.complete();
          entry.remove();
        },
        game: AlfaGameScreen(
          key: gameKey,
          gameId: gameId,
          host: host ?? _defaultHost,
          appKey: appKey ?? _defaultAppKey,
          poolId: poolId,
          title: title,
          roomId: roomId,
          viewMode: viewMode,
          urlTemplate: urlTemplate,
          onGameRatio: (ratio) =>
              hostKey.currentState?.handleGameRatio(ratio),
          onRequestClose: () => hostKey.currentState?.requestClose(),
          iconAsset: iconAsset,
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(entry);
    return completer.future;
  }

  @override
  State<AlfaGameScreen> createState() => _AlfaGameScreenState();
}

/// هوست الـ overlay للعبة — بيدير: مقاس الصندوق، السحب للتكبير/التصغير،
/// دايالوج «تصغير ولا إغلاق»، والفقاعة العائمة وقت التصغير.
/// اللعبة (WebView) بتفضل mounted طول الوقت عشان ميفقدش الجولة/النتيجة.
class _GameOverlayHost extends StatefulWidget {
  final ValueNotifier<double> height;
  final String title;
  final String? iconAsset;
  final GlobalKey<_AlfaGameScreenState> gameKey;
  final VoidCallback onClosed;
  final Widget game;
  final bool fullScreen;

  const _GameOverlayHost({
    super.key,
    required this.height,
    required this.title,
    required this.iconAsset,
    required this.gameKey,
    required this.onClosed,
    required this.game,
    this.fullScreen = false,
  });

  @override
  State<_GameOverlayHost> createState() => _GameOverlayHostState();
}

class _GameOverlayHostState extends State<_GameOverlayHost>
    with WidgetsBindingObserver {
  bool _minimized = false;
  bool _userResized = false;
  bool _dialogOpen = false;
  double _dragStartH = 0;
  double _dimDragStartH = 0;
  Offset? _bubblePos;

  bool get _isFull => widget.fullScreen;

  double get _minH => MediaQuery.of(context).size.height * 0.35;
  double get _maxH => MediaQuery.of(context).size.height;

  @override
  void initState() {
    super.initState();
    // ✅ التقاط زرار الرجوع من النظام بدون BackButtonListener —
    //    التطبيق بيستخدم Navigator 1.0 (مفيش Router widget) والـ
    //    OverlayEntry بتاع اللعبة مش تحت Router → BackButtonListener
    //    كان بيرمي "Router operation requested".
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (!mounted) return false;
    if (_minimized) {
      _restore();
      return true;
    }
    requestClose();
    return true;
  }

  /// الـ JS بيقيس نسبة أبعاد canvas — بنضبط ارتفاع الصندوق تلقائياً.
  /// ✅ تُطبّق مرة واحدة فقط: إعادة القياس بعد كل resize كانت بتسبب
  ///    حلقة تصغير/تكبير لا نهائية (scrollHeight يتغير مع ارتفاع
  ///    الحاوية → ratio جديد → resize → ratio جديد...).
  bool _autoRatioApplied = false;
  void handleGameRatio(double ratio) {
    if (_minimized || _userResized || _autoRatioApplied || !mounted) return;
    final size = MediaQuery.of(context).size;
    final wanted = (size.width / ratio).clamp(_minH, _maxH).toDouble();
    if ((wanted - widget.height.value).abs() > 24) {
      _autoRatioApplied = true;
      widget.height.value = wanted;
    }
  }

  bool _closeDialogVisible = false;
  bool _roundOpenWarning = false;

  void requestClose() {
    if (!mounted || _dialogOpen) return;
    _dialogOpen = true;
    // ✅ في وضع ملء الشاشة: خروج مباشر بدون دايرلوج «تصغير ولا إغلاق»
    if (_isFull) {
      widget.onClosed();
      return;
    }
    _roundOpenWarning = widget.gameKey.currentState?.isRoundOpen ?? false;
    setState(() => _closeDialogVisible = true);
  }

  void _dismissCloseDialog() {
    if (!mounted) return;
    setState(() => _closeDialogVisible = false);
    _dialogOpen = false;
  }

  void _restore() => setState(() => _minimized = false);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final padding = MediaQuery.of(context).padding;

    return ValueListenableBuilder<double>(
        valueListenable: widget.height,
        builder: (context, h, _) {
          // موضع الفقاعة الافتراضي: أعلى يمين الشاشة
          _bubblePos ??= Offset(
            size.width - 76,
            padding.top + 70,
          );

          return Stack(
            children: [
              if (!_minimized && !_isFull)
                // خلفية بتلتقط اللمس بره اللعبة → طلب إغلاق
                // (لازم تكون تحت لوحة اللعبة في الـ Stack وإلا حتبLOCK اللمس)
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: requestClose,
                    // ✅ سحب إلى الأسفل على الشاشة الخارجية من اللعبة مُلغاة —
                    //    (السحب للتكبير/التصغير موجود عبر مقبض السحب).
                    // ✅ سحب فوق/تحت في المنطقة الفاضية = تكبير/تصغير
                    //    نفس مقبض السحب — أسهل بكتير من الـ 28px.
                    onVerticalDragStart: (_) {
                      _dimDragStartH = widget.height.value;
                    },
                    onVerticalDragUpdate: (d) {
                      widget.height.value =
                          (_dimDragStartH - d.delta.dy).clamp(_minH, _maxH);
                    },
                  ),
                ),

              // ✅ اللعبة بتفضل في الشجرة دايماً — وقت التصغير
              //    بتبقى Opacity(0)+IgnorePointer+نفس الارتفاع عشان
              //    الـ WebView يفضل شغال بالظبط (النتيجة/الفوز مبيضيعش)
              //    واللمس يعدي للتطبيق.
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                top: _isFull ? 0 : null,
                height: _isFull ? null : h,
                child: IgnorePointer(
                  ignoring: _minimized,
                  child: Opacity(
                    opacity: _minimized ? 0 : 1,
                    child: AnimatedContainer(
                      duration: _userResized
                          ? Duration.zero
                          : const Duration(milliseconds: 250),
                      curve: Curves.easeOut,
                      height: _isFull ? null : h,
                      decoration: null,
                      child: ClipRRect(
                        borderRadius: _isFull
                            ? BorderRadius.zero
                            : const BorderRadius.vertical(
                                top: Radius.circular(18)),
                        child: widget.game,
                      ),
                    ),
                  ),
                ),
              ),

              if (!_minimized && !_isFull) ...[
                // ✅ أزرار تحكم واضحة جداً (إغلاق وتصغير) فوق اللعبة
                Positioned(
                  top: (size.height - h - 42).clamp(padding.top + 4, size.height - 44),
                  left: 12,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // زر إغلاق X بارز وواضح جداً للمستخدم
                      GestureDetector(
                        onTap: requestClose,
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.close,
                              size: 20, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // زر تصغير
                      GestureDetector(
                        onTap: () => setState(() => _minimized = true),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.8),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.fullscreen_exit,
                              size: 20, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
                // مقبض سحب — للتكبير/التصغير ارتفاع اللعبة
                Positioned(
                  top: (size.height - h - 22).clamp(padding.top + 4, size.height - 24),
                  left: 0,
                  right: 0,
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onVerticalDragStart: (_) {
                      _dragStartH = widget.height.value;
                      _userResized = true;
                    },
                    onVerticalDragUpdate: (d) {
                      widget.height.value =
                          (_dragStartH - d.delta.dy).clamp(_minH, _maxH);
                    },
                    child: const SizedBox(
                      height: 44,
                      child: Center(
                        child: Opacity(
                          opacity: 0.22,
                          child: SizedBox(
                            width: 44,
                            height: 4,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(2)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ] else if (_isFull && !_minimized) ...[
                // ✅ أزرار تحكم عائمة شفافة لوضع ملء الشاشة (بدون شريط أسود وبدون اسم اللعبة)
                Positioned(
                  top: padding.top + 10,
                  left: 14,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // زر إغلاق X بارز وواضح جداً للمستخدم
                      GestureDetector(
                        onTap: requestClose,
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white,
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.close,
                              size: 24, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // زر تصغير اللعبة
                      GestureDetector(
                        onTap: () => setState(() => _minimized = true),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.8),
                              width: 1.8,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.fullscreen_exit,
                              size: 24, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                // ✅ الفقاعة العائمة — اللعبة شغالة في الخلفية.
                //    اسحبها لأي مكان، دوس عليها للرجوع، ✕ للإغلاق.
                Positioned(
                  left: _bubblePos!.dx,
                  top: _bubblePos!.dy,
                  child: GestureDetector(
                    onPanUpdate: (d) {
                      setState(() {
                        final nx = (_bubblePos!.dx + d.delta.dx)
                            .clamp(8.0, size.width - 76.0);
                        final ny = (_bubblePos!.dy + d.delta.dy).clamp(
                            padding.top + 8.0,
                            size.height - padding.bottom - 76.0);
                        _bubblePos = Offset(nx, ny);
                      });
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          onTap: _restore,
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFFFC525),
                                width: 2.2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  blurRadius: 8,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: widget.iconAsset != null &&
                                      widget.iconAsset!.isNotEmpty
                                  ? Image.asset(
                                      widget.iconAsset!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _bubbleFallback(),
                                    )
                                  : _bubbleFallback(),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -2,
                          right: -2,
                          child: GestureDetector(
                            onTap: requestClose,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 3,
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.close,
                                  color: Colors.white, size: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // ✅ دايالوج الإغلاق — آخر عنصر في الـ Stack عشان
              //    يظهر فوق الـ WebView والفقاعة.
              if (_closeDialogVisible) _buildCloseDialog(size),
            ],
          );
        },
      );
  }

  Widget _buildCloseDialog(Size size) {
    return Positioned.fill(
      child: Material(
        type: MaterialType.transparency,
        child: DefaultTextStyle(
          style: const TextStyle(
            decoration: TextDecoration.none,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissCloseDialog,
            child: Container(
              color: Colors.black.withValues(alpha: 0.6),
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () {},
                child: Container(
                  width: size.width * 0.82,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C22),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.6),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'خيارات اللعبة',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _roundOpenWarning
                            ? '⚠️ إنت لسه مراهن وفيه نتيجة ما ظهرتش. لو قفلت اللعبة دلوقتي الرهان ممكن يضيع. تصغّرها وكمّل من الفقاعة لو عايز تستنى النتيجة.'
                            : 'هل تريد تصغير اللعبة لمتابعة الجولة في الخلفية أم إغلاقها تماماً؟',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.5,
                          decoration: TextDecoration.none,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _dismissCloseDialog();
                                setState(() => _minimized = true);
                              },
                              icon: const Icon(Icons.fullscreen_exit, size: 18, color: Colors.black87),
                              label: const Text(
                                'تصغير',
                                style: TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFFFC525),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () {
                                _dismissCloseDialog();
                                widget.onClosed();
                              },
                              icon: const Icon(Icons.close, size: 18, color: Colors.white),
                              label: const Text(
                                'إغلاق',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  decoration: TextDecoration.none,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFEF4444),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _dismissCloseDialog,
                        child: const Text(
                          'إلغاء والعودة للعب',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bubbleFallback() {
    return Container(
      color: const Color(0xFF2A2A2A),
      child: const Icon(Icons.sports_esports,
          color: Color(0xFFFFC525), size: 26),
    );
  }
}

class _AlfaGameScreenState extends State<AlfaGameScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  double _winRate = AlfaGameScreen._defaultWinRate;
  int _lastBet = 0;
  int? _lastGameCoins;

  /// المضيف المسموح للتنقل — من قالب الرابط المخصص إن وُجد، وإلا widget.host.
  late String _allowedHost;

  /// تتبع الجولة المفتوحة: alfa_sync بيبعت الرصيد المطلق للعبة —
  /// فرق سالب = خصم رهان جديد (الجولة مفتوحة)، فرق موجب = فوز وصل
  /// (الجولة اتقفلت). لو المستخدم قفل اللعبة والجولة لسه مفتوحة
  /// بيظهرله تأكيد تحذير لأن النتيجة ممكن تضيع مع الـ WebView.
  int? _prevSyncCoins;
  bool _roundOpen = false;
  Timer? _roundOpenTimer;

  /// الـ host (overlay) بيقرأها عشان يحذّر «جولة مفتوحة» في دايالوج الإغلاق.
  bool get isRoundOpen => _roundOpen;

  /// كل مسارات الإغلاق (زرار اللعبة، رجوع، ضغط بره) بتمر من الـ host —
  /// اللي بيعرض دايالوج «تصغير ولا إغلاق».
  void _requestHostClose() {
    final cb = widget.onRequestClose;
    if (cb != null) {
      cb();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  /// آخر رصيد دفعناه للعبة — عشان ما نكتبش نفس القيمة كل ثانية فوق
  /// الرصيد الداخلي اللي اللعبة بتغيّره بنفسها بعد كل رهان/فوز.
  int? _lastPushedCoins;
  UserProvider? _userProvider;
  bool _isApplyingFromGame = false;

  /// معرفات الطلبات التي تم تسويتها محلياً لمنع التكرار (Idempotency)
  final Set<String> _processedOrders = <String>{};

  /// منع `alfa_sync` (كل ~300ms) من إطلاق reloadUser() في كل مرة — كان بيسبب
  /// تدفق طلبات Supabase وتأخير/تضارب في عرض الرصيد.
  Timer? _balanceRefreshDebounce;

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  @override
  void initState() {
    super.initState();
    // ✅ المضيف المسموح: قالب الرابط المخصص أولاً ثم widget.host
    final tplHost = widget.urlTemplate != null && widget.urlTemplate!.isNotEmpty
        ? Uri.tryParse(widget.urlTemplate!)?.host
        : null;
    _allowedHost = (tplHost != null && tplHost.isNotEmpty) ? tplHost : widget.host;
    // ✅ إنشاء الكنترولر بشكل متزامن — بدون هذا كان build الأول يرمي
    //    LateInitializationError لأن _init() غير متزامن ويُكمله لاحقاً.
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // ✅ خلفية شفافة للـ WebView عشان شكل اللعبة يظهر كما هو بدون خلفية سوداء
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
            _injectEarlyWsShim();
          },
          onPageFinished: (_) {
            if (mounted) {
              setState(() => _loading = false);
              _injectEarlyWsShim();
              _injectGameHooks();
              // ✅ نفرض رصيد التطبيق الحقيقي داخل اللعبة فور تحميلها
              _injectBalanceMirror();
              _pushTrueCoins(force: true);
              // ✅ نمرّر ترتيبنا الحقيقي للعبة عبر window.setLeaderboard.
              _pushLeaderboard();
            }
          },
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            // نسمح فقط بالتنقل داخل نطاق اللعبة الموثوق
            if (uri != null &&
                uri.scheme == 'https' &&
                uri.host == _allowedHost) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.prevent;
          },
        ),
      )
      ..addJavaScriptChannel(
        'FlutterBridge',
        onMessageReceived: _onJsMessage,
      )
      ..addJavaScriptChannel(
        'AlfaBridgeChannel',
        onMessageReceived: _onJsMessage,
      );

    // ✅ إعدادات Android WebView للأداء — بدونها ألعاب HTML5
    //    (Cocos/Unity web) بتعلّق أو تستهلك بطارية/ذاكرة زيادة.
    try {
      final platform = _controller.platform;
      if (platform is AndroidWebViewController) {
        unawaited(platform.setMediaPlaybackRequiresUserGesture(false));
        unawaited(platform.setVerticalScrollBarEnabled(false));
        unawaited(platform.setHorizontalScrollBarEnabled(false));
      }
    } catch (_) {}

    _init();
    // ✅ أي تغيير في رصيد التطبيق (تسوية لعبة، هدية، شحن...) يُدفع للعبة
    //    فوراً عبر window.__sugarGame.updateCoins — بدون bookkeeping دوري.
    _userProvider = Provider.of<UserProvider>(context, listen: false);
    _userProvider!.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    _balanceRefreshDebounce?.cancel();
    _roundOpenTimer?.cancel();
    _userProvider?.removeListener(_onUserChanged);
    final up = _userProvider;
    if (up != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        up.reloadUser();
      });
    }
    // تفريغ محرك WebView وألعاب HTML5 فوراً لتحرير موارد المعالج وكارت الشاشة
    try {
      _controller.loadRequest(Uri.parse('about:blank'));
    } catch (_) {}
    super.dispose();
  }

  void _onUserChanged() {
    if (_isApplyingFromGame) return;
    if (mounted) _pushTrueCoins();
  }

  Future<void> _init() async {
    _winRate = await _loadWinRate();
    if (!mounted) return;

    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final uid = user?.uid ?? '';
    final customId = user?.customId.trim() ?? '';
    // ✅ تحويل معرف اللاعب لرقم صحيح إلزامي لألعاب Cocos Creator وبروتوكول Protobuf:
    //    مخطط Protobuf يعرّف playerId كـ int32. لو تم تمرير UUID نصي،
    //    Number(u.userId) ينتج عنه NaN ويرمي الخطأ:
    //    ProtocolError("missing required 'playerId'").
    final numericPlayerId = int.tryParse(customId) ??
        int.tryParse(uid) ??
        (int.tryParse(uid.replaceAll(RegExp(r'\D'), '')) ??
            (uid.hashCode.abs() % 900000 + 100000));
    final playerIdStr = numericPlayerId.toString();

    final playerToken = SessionTokenStore.token ??
        'token_${playerIdStr}_${DateTime.now().millisecondsSinceEpoch}';
    final coins = (user?.coins ?? 0).toInt().toString();
    final nickname = (user?.name.isNotEmpty ?? false) ? user!.name : 'Player';
    final avatar = user?.photoUrl ?? '';
    final winRateStr = _winRate.toString();

    // ✅ قالب رابط مخصص من لوحة التحكم (game_links.url_template):
    //    نستبدل كل المتغيرات الرسمية بما فيها المتغيرات التي يعيدها سيرفر alfanexso
    final tpl = widget.urlTemplate;
    if (tpl != null && tpl.trim().isNotEmpty) {
      var url = tpl
          .replaceAll('{STYEPARTY_USER_ID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{PLAYER_TOKEN}', Uri.encodeComponent(playerToken))
          .replaceAll('{ROOM_ID}', Uri.encodeComponent(widget.roomId ?? ''))
          .replaceAll('{GAME_ID}', Uri.encodeComponent(widget.gameId))
          .replaceAll('{APP_KEY}', Uri.encodeComponent(widget.appKey))
          .replaceAll('{VIEW_MODE}', Uri.encodeComponent(widget.viewMode ?? 'full'))
          .replaceAll('{UID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{TOKEN}', Uri.encodeComponent(playerToken))
          .replaceAll('{COINS}', Uri.encodeComponent(coins))
          .replaceAll('{USER_COINS}', Uri.encodeComponent(coins))
          .replaceAll('{BALANCE}', Uri.encodeComponent(coins))
          .replaceAll('{USER_ID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{USERID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{PLAYER_ID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{PLAYERID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{CUSTOM_ID}', Uri.encodeComponent(playerIdStr))
          .replaceAll('{NICKNAME}', Uri.encodeComponent(nickname))
          .replaceAll('{USER_NAME}', Uri.encodeComponent(nickname))
          .replaceAll('{NAME}', Uri.encodeComponent(nickname))
          .replaceAll('{AVATAR}', Uri.encodeComponent(avatar))
          .replaceAll('{USER_AVATAR}', Uri.encodeComponent(avatar))
          .replaceAll('{WIN_RATE}', Uri.encodeComponent(winRateStr))
          .replaceAll('{WINRATE}', Uri.encodeComponent(winRateStr));

      // ✅ تأكيد وجود معاملات الحساب الأساسية في الرابط حتى لو نسيها الأدمن في القالب
      final parsed = Uri.parse(url);
      final qParams = Map<String, String>.from(parsed.queryParameters);
      qParams['coins'] = coins;
      qParams['uid'] = playerIdStr;
      qParams['user_id'] = playerIdStr;
      qParams['userId'] = playerIdStr;
      qParams['player_id'] = playerIdStr;
      qParams['playerId'] = playerIdStr;
      qParams['custom_id'] = playerIdStr;
      if (nickname.isNotEmpty &&
          (qParams['nickname'] == null || qParams['nickname']!.contains('{'))) {
        qParams['nickname'] = nickname;
      }
      if (avatar.isNotEmpty &&
          (qParams['avatar'] == null || qParams['avatar']!.contains('{'))) {
        qParams['avatar'] = avatar;
      }
      qParams.putIfAbsent('chips', () => AlfaGameScreen._chips.join(','));
      qParams.putIfAbsent('win_rate', () => winRateStr);
      qParams.putIfAbsent('token', () => playerToken);
      qParams.putIfAbsent('gameId', () => widget.gameId);
      qParams.putIfAbsent('app_key', () => widget.appKey);
      final finalUri = parsed.replace(queryParameters: qParams);
      _controller.loadRequest(finalUri);
      return;
    }

    // ✅ المسار الافتراضي بدون قالب:
    final params = <String, String>{
      // معاملات بروتوكول StyeParty الرسمية
      'gameId': widget.gameId,
      'uid': playerIdStr,
      'user_id': playerIdStr,
      'userId': playerIdStr,
      'player_id': playerIdStr,
      'playerId': playerIdStr,
      'custom_id': playerIdStr,
      'uuid': uid,
      'token': playerToken,
      'roomId': widget.roomId ?? '',
      'view_mode': widget.viewMode ?? 'full',
      'nickname': nickname,
      'coins': coins,
      'avatar': avatar,
      'win_rate': winRateStr,
      'chips': AlfaGameScreen._chips.join(','),
      'app_id': widget.appKey,
      'app_key': widget.appKey,
    };
    final url = Uri.parse(
            'https://${widget.host}/play/${widget.appKey}/${widget.gameId}')
        .replace(queryParameters: params)
        .toString();

    _controller.loadRequest(Uri.parse(url));
  }

  /// win_rate يُجلب من game_jackpot_pool إن وُجد صف للعبة،
  /// وإلا نستخدم القيمة الافتراضية.
  Future<double> _loadWinRate() async {
    try {
      final url = Uri.parse(
        '${SupabaseConfig.projectUrl}/rest/v1/game_jackpot_pool'
        '?select=win_rate&id=in.(alfa,lucky777)&limit=1',
      );
      final res = await SafeHttp.get(url, headers: _headers);
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          final wr = (list.first as Map<String, dynamic>)['win_rate'];
          if (wr is num) return wr.toDouble();
        }
      }
    } catch (_) {}
    return AlfaGameScreen._defaultWinRate;
  }

  /// ✅ يعترض WebSocket قبل تشغيل سكربتات اللعبة — يوجّه ألعاب alfanexso
  ///    (الأسد الجائع، فروتي بارتي، ملك القراصنة، 7 Up Down) فوراً إلى
  ///    محاكي البروتوكول المحلي بدلاً من محاولة الاتصال بسيرفر WebSocket
  ///    معطّل يرجع 405 ويجمّد اللعبة على splash إلى الأبد.
  void _injectEarlyWsShim() {
    const shimJs = '''
(function(){
  try {
    if (window.__alfaWsShimDone) return;
    var OrigWS = window.WebSocket;
    if (!OrigWS) return;
    function OfflineShimWS(url, protocols) {
      var u = String(url || '').toLowerCase();
      if (u.indexOf('greedylion-ws') !== -1 ||
          u.indexOf('fruitparty-ws') !== -1 ||
          u.indexOf('pirateking-ws') !== -1 ||
          u.indexOf('7updown-ws') !== -1) {
        throw new Error('OfflineMultiplayerServer: ' + u);
      }
      return new OrigWS(url, protocols);
    }
    OfflineShimWS.prototype = OrigWS.prototype;
    window.WebSocket = OfflineShimWS;
    window.__alfaWsShimDone = true;
  } catch(e) {}
})();
''';
    unawaited(_controller.runJavaScript(shimJs));
  }

  /// ✅ مزامنة الرصيد بالطريقة الرسمية اللي أكّدها المزوّد:
  ///    الرابط هو الحاكم عند الدخول (`coins=...`)، وداخل الجلسة نستخدم
  ///    `window.__sugarGame.updateCoins(n)` — نفس دالة Sugar Rush بالظبط.
  ///    كده الفوز/Zيادة والخسارة/النقصان بيحصلوا جوه اللعبة بشكل صحيح،
  ///    والسيرفر هو اللي بيحسم المبلغ النهائي عبر callback.
  ///    لا نعترض JSON.parse ولا نفرض الرصيد على saveUser — ده كان بيعطّل
  ///    خصم الرهان جوه اللعبة ويسبب تضارب مع التسوية.
  void _injectBalanceMirror() {
    final user = Provider.of<UserProvider>(context, listen: false).currentUser;
    final coins = user?.coins.toInt() ?? 0;
    final customId = user?.customId.trim() ?? '';
    final rawUid = user?.uid ?? '';
    final numericPlayerId = int.tryParse(customId) ??
        int.tryParse(rawUid) ??
        (int.tryParse(rawUid.replaceAll(RegExp(r'\D'), '')) ??
            (rawUid.hashCode.abs() % 900000 + 100000));
    final playerIdStr = numericPlayerId.toString();
    final nicknameJson = jsonEncode((user?.name.isNotEmpty ?? false) ? user!.name : 'Player');
    final avatarJson = jsonEncode(user?.photoUrl ?? '');

    final js = '''
(function(){
  var TRUTH = $coins;
  window.__alfaTruthCoins = TRUTH;
  window.__alfaSyncing = true;

  // ✅ تصحيح وتطهير بيانات المستخدم المخزنة في localStorage لمحرك Cocos
  //    حتى لا يقرأ بيانات تالفة قديمة أو معرّف NaN
  try {
    var k = 'alfa_gaming_user_data';
    var raw = localStorage.getItem(k);
    var uData = raw ? JSON.parse(raw) : {};
    uData.userId = $playerIdStr;
    uData.user_id = $playerIdStr;
    uData.playerId = $playerIdStr;
    uData.id = $playerIdStr;
    uData.uid = $playerIdStr;
    uData.coins = TRUTH;
    uData.coin = TRUTH;
    uData.gold = TRUTH;
    uData.diamond = TRUTH;
    var nick = $nicknameJson;
    if (nick && (!uData.nickname || uData.nickname.indexOf('{') !== -1)) {
      uData.nickname = nick;
      uData.name = nick;
    }
    var av = $avatarJson;
    if (av && (!uData.avatar || uData.avatar.indexOf('{') !== -1)) {
      uData.avatar = av;
    }
    localStorage.setItem(k, JSON.stringify(uData));

    // تصحيح كائن AlfaBridge أيضاً إذا كان مهيأ بالفعل
    if (window.AlfaBridge && typeof window.AlfaBridge.getUser === 'function') {
      var abUser = window.AlfaBridge.getUser();
      if (abUser) {
        abUser.userId = $playerIdStr;
        abUser.playerId = $playerIdStr;
        abUser.id = $playerIdStr;
        abUser.uid = $playerIdStr;
        abUser.coins = TRUTH;
      }
    }
  } catch(e) {}
  setTimeout(function(){ window.__alfaSyncing = false; }, 400);

  // ✅ المزوّد أكّد 3 مداخل متطابقة لتحديث الرصيد داخل الـ WebView —
  //    نستدعيها كلها بنفس القيمة المطلقة (idempotent) عشان أي إصدار
  //    من اللعبة يلتقط التحديث فوراً بدون إعادة تحميل الصفحة.
  function official(n){
    var ok = false;
    try{
      var g = window.__sugarGame;
      if (g && typeof g.updateCoins === 'function') { g.updateCoins(n); ok = true; }
    }catch(e){}
    try{
      if (typeof window.updateCoins === 'function') { window.updateCoins(n); ok = true; }
    }catch(e){}
    try{
      var ab = window.AlfaBridge;
      if (ab && typeof ab.setCoins === 'function') { ab.setCoins(n); ok = true; }
    }catch(e){}
    return ok;
  }
  // مسار قديم احتياطي لمنصات Alfa القديمة اللي ما عندهاش __sugarGame.
  function legacy(n){
    try{
      ['userInfo','gameUser','user','__user','playerInfo','userData'].forEach(function(k){
        var u = window[k];
        if (!u || typeof u !== 'object') return;
        ['coins','coin','gold','balance','money'].forEach(function(f){
          if (Object.prototype.hasOwnProperty.call(u, f)) u[f] = n;
        });
      });
      ['AlfaBridge','alfaBridge','gameBridge','GameBridge','JSBridge','NativeBridge'].forEach(function(b){
        var bridge = window[b];
        if (!bridge || typeof bridge !== 'object') return;
        ['getUser','getUserInfo','getPlayerInfo','getAccount','getUserData'].forEach(function(fn){
          if (typeof bridge[fn] === 'function' && !bridge['__alfaTruth_'+fn]){
            bridge['__alfaTruth_'+fn] = true;
            var orig = bridge[fn];
            bridge[fn] = function(){
              var u = orig.apply(this, arguments);
              if (u && typeof u === 'object'){
                ['coins','coin','gold','balance','money'].forEach(function(f){
                  if (Object.prototype.hasOwnProperty.call(u, f)) u[f] = n;
                });
              }
              return u;
            };
          }
        });
      });
    }catch(e){}
  }
  function apply(n){
    var v = Number(n);
    if (!isFinite(v) || v < 0) return;
    TRUTH = Math.round(v);
    window.__alfaTruthCoins = TRUTH;
    window.__alfaSyncing = true;
    if (typeof window.__alfaSetLastCoins === 'function') {
      window.__alfaSetLastCoins(TRUTH);
    }
    if (!official(TRUTH)) legacy(TRUTH);
    setTimeout(function(){ window.__alfaSyncing = false; }, 800);
  }
  window.__alfaSetTruthCoins = apply;
  apply(TRUTH);
  // الدالة الرسمية ممكن تتسجّل بعد حقننا (Cocos init متأخر) — نعيد المحاولة
  // لفترة قصيرة بدون أي setInterval دائم عشان ما نكتبش فوق رصيد اللعبة.
  var tries = 0;
  var retry = setInterval(function(){
    if (official(TRUTH) || ++tries > 20) clearInterval(retry);
  }, 300);
  window.__alfaMirrorReady = true;
})();
''';
    _controller.runJavaScript(js);
  }

  /// يدفع أي تغيير في رصيد التطبيق (بعد تسوية الخادم / هدية / شحن) للعبة.
  /// لا نرسل نفس القيمة مرتين عشان ما نقطعش رصيد اللعبة أثناء الجولة.
  void _pushTrueCoins({bool force = false}) {
    final coins =
        (Provider.of<UserProvider>(context, listen: false).currentUser?.coins ?? 0)
            .toInt();
    if (!force && (_roundOpen || _lastPushedCoins == coins)) return;
    _lastPushedCoins = coins;
    unawaited(_controller.runJavaScript(
      'window.__alfaSetTruthCoins && window.__alfaSetTruthCoins($coins);',
    ));
  }

  /// يمرّر ترتيب المتصدرين الحقيقي من تطبيقنا للعبة مباشرة.
  /// المزوّد أكّد دعم `window.setLeaderboard([...])` — نحقنه مع إعادة
  /// محاولة قصيرة لأن اللعبة قد تسجّل الدالة بعد اكتمال تهيئة Cocos.
  void _pushLeaderboard() {
    unawaited(_doPushLeaderboard());
  }

  Future<void> _doPushLeaderboard() async {
    try {
      final uri = Uri.parse(
        'https://ahla-live-api.vercel.app/api/v1/games/leaderboard',
      ).replace(queryParameters: {
        'game_id': widget.gameId,
        'limit': '10',
      });
      final res = await SafeHttp.get(uri, headers: _headers);
      if (res.statusCode != 200 || !mounted) return;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final rows = (body['rankings'] as List<dynamic>?) ?? const <dynamic>[];
      final list = rows.whereType<Map<String, dynamic>>().map((r) {
        return <String, dynamic>{
          'uid': r['user_id']?.toString() ?? '',
          'name': r['user_name']?.toString() ?? 'Player',
          'avatar': r['avatar']?.toString() ?? '',
          'score': (r['total'] as num?)?.toInt() ?? 0,
        };
      }).toList();
      if (list.isEmpty) return;
      final payload = jsonEncode(list);
      unawaited(_controller.runJavaScript('''
(function(){
  var data = $payload;
  var tries = 0;
  var timer = setInterval(function(){
    try{
      if (typeof window.setLeaderboard === 'function') {
        window.setLeaderboard(data);
        clearInterval(timer);
      } else if (++tries > 20) {
        clearInterval(timer);
      }
    }catch(e){ clearInterval(timer); }
  }, 300);
})();
'''));
    } catch (_) {}
  }

  /// نحقن خطافاً داخل صفحة H5 يلتقط خصم الرهان ومكافأة الفوز.
  /// الآلية الرئيسية: hook على AlfaBridge.saveUser + حساب فرق الرصيد —
  /// يلتقط أي تغيير كوينز (addCoins/deductCoins/حفظ مباشر) في كل ألعاب
  /// Alfa بما فيها roulette مثل super77 التي قد تتجاوز addCoins.
  /// window.__alfaSyncing يمنعFeedback loop عند مزامنة رصيدنا внутрاللعبة.
  void _injectGameHooks() {
    // ✅ الجاسوس (alfa_spy) بيبعت **كل** xhr/fetch للـ Dart — على
    //    الأجهزة الضعيفة كان بيسبب تعليق داخل اللعبة. مفعّل في
    //    الـ debug بس.
    // ✅ استخدام window.__ALFA_SPY_ENABLED بدل const لمنع SyntaxError عند إعادة الحقن
    final js = 'window.__ALFA_SPY_ENABLED = $kDebugMode;\n' r'''
(function(){
  function send(o){ try{ window.FlutterBridge.postMessage(JSON.stringify(o)); }catch(e){} }
  function hook(){
    try{
      // ✅ اعتراض رهانات وفوز FruitPartySocket (الأسد الجائع وفروتي بارتي) بشكل آمن ومباشر
      // بدون اعتراض localStorage لتجنب الحلقات التكرارية والزيادة العشوائية
      if (window.__activeFruitPartySocket && !window.__activeFruitPartySocket.__alfaHooked) {
        var sock = window.__activeFruitPartySocket;
        sock.__alfaHooked = true;

        var origSend = sock.send;
        sock.send = function(data) {
          try {
            var unp = sock.unpack(data);
            if (unp && unp.header === '.game.BetReq') {
              var P = window.protobuf && window.protobuf.roots && window.protobuf.roots.creator;
              if (P && P.game && P.game.BetReq) {
                var req = P.game.BetReq.decode(unp.payload);
                var bAmt = req && req.money ? Number(req.money) : 0;
                if (bAmt > 0) {
                  var u = (typeof getStoredUser === 'function') ? getStoredUser() : null;
                  var curC = u ? (u.coins || 0) : 0;
                  if (curC >= bAmt) {
                    send({
                      event: 'update_balance',
                      action: 'update_balance',
                      diff: -bAmt,
                      coins: Math.max(0, curC - bAmt),
                      reason: 'bet',
                      timestamp: Date.now()
                    });
                  }
                }
              }
            }
          } catch(e) {}
          return origSend.apply(sock, arguments);
        };

        var origSpin = sock.spinAndResult;
        sock.spinAndResult = function() {
          var uBefore = (typeof getStoredUser === 'function') ? getStoredUser() : null;
          var coinsBefore = uBefore ? (uBefore.coins || 0) : 0;
          var res = origSpin.apply(sock, arguments);
          try {
            var uAfter = (typeof getStoredUser === 'function') ? getStoredUser() : null;
            var coinsAfter = uAfter ? (uAfter.coins || 0) : 0;
            var winDiff = coinsAfter - coinsBefore;
            if (winDiff > 0) {
              send({
                event: 'update_balance',
                action: 'update_balance',
                diff: winDiff,
                coins: coinsAfter,
                reason: 'win',
                timestamp: Date.now()
              });
            }
          } catch(e) {}
          return res;
        };
      }

      // ✅ إخفاء شاشة التحميل (splash) للأسد الجائع تلقائياً
      if (!window.__alfaSplashTimer) {
        window.__alfaSplashTimer = true;
        var splashTries = 0;
        var splashInterval = setInterval(function() {
          try {
            splashTries++;
            var sp = document.getElementById('splash');
            if (sp && sp.style.display !== 'none') {
              if ((window.__activeFruitPartySocket && window.__activeFruitPartySocket.readyState === 1) || splashTries > 10) {
                sp.style.display = 'none';
                clearInterval(splashInterval);
              }
            } else if (!sp || splashTries > 30) {
              clearInterval(splashInterval);
            }
          } catch(e) { clearInterval(splashInterval); }
        }, 500);
      }

      // ✅ مراقبة رصيد اللعبة والتسوية المالية التلقائية (رهان وفوز) لجميع الألعاب
      if (!window.__alfaPollStarted){
        window.__alfaPollStarted = true;
        function coinsNow(){
          try{
            var k = 'alfa_gaming_user_data';
            var raw = localStorage.getItem(k);
            if (raw) {
              var ud = JSON.parse(raw);
              if (ud) {
                var cVal = ud.coins != null ? ud.coins : (ud.coin != null ? ud.coin : (ud.gold != null ? ud.gold : ud.diamond));
                if (cVal != null && isFinite(Number(cVal))) {
                  return Number(cVal);
                }
              }
            }
            if (window.AlfaBridge && typeof window.AlfaBridge.getUser === 'function') {
              var u = window.AlfaBridge.getUser();
              if (u) {
                var bVal = u.coins != null ? u.coins : (u.coin != null ? u.coin : (u.gold != null ? u.gold : u.diamond));
                if (bVal != null && isFinite(Number(bVal))) return Number(bVal);
              }
            }
            var gd = window.userData || window.userInfo || window.gameUser;
            if (gd) {
              var gVal = gd.coins != null ? gd.coins : (gd.coin != null ? gd.coin : (gd.gold != null ? gd.gold : gd.diamond));
              if (gVal != null && isFinite(Number(gVal))) return Number(gVal);
            }
            return null;
          }catch(e){ return null; }
        }

        var lastCoins = coinsNow();
        var winDebounceTimer = null;
        var pendingWinStartCoins = null;
        var candidateWinCoins = null;

        window.__alfaSetLastCoins = function(val){
          lastCoins = val;
          if (winDebounceTimer) {
            clearTimeout(winDebounceTimer);
            winDebounceTimer = null;
          }
          pendingWinStartCoins = null;
          candidateWinCoins = null;
        };

        // اعتراض addCoins و deductCoins لتسجيل آخر رصيد وتفادي التكرار
        function hookBridgeMethods(){
          try{
            var ab = window.AlfaBridge;
            if (ab && !ab.__alfaWrapped){
              ab.__alfaWrapped = true;
              var origAdd = ab.addCoins;
              if (typeof origAdd === 'function'){
                ab.addCoins = function(amt){
                  var res = origAdd.apply(ab, arguments);
                  var cur = coinsNow();
                  if (cur != null) window.__alfaSetLastCoins(cur);
                  return res;
                };
              }
              var origDeduct = ab.deductCoins;
              if (typeof origDeduct === 'function'){
                ab.deductCoins = function(amt){
                  var res = origDeduct.apply(ab, arguments);
                  var cur = coinsNow();
                  if (cur != null) window.__alfaSetLastCoins(cur);
                  return res;
                };
              }
            }
          }catch(e){}
        }
        hookBridgeMethods();

        send({action:'alfa_hook_ready'});

        setInterval(function(){
          try{
            hookBridgeMethods();
            if (window.__alfaSyncing) return;
            var c = coinsNow();
            if (c == null){ return; }
            if (lastCoins == null){ lastCoins = c; return; }
            if (c === lastCoins) return;

            // 1. خصم رهان (c < lastCoins) — فوري ومباشر
            if (c < lastCoins) {
              if (winDebounceTimer) {
                clearTimeout(winDebounceTimer);
                winDebounceTimer = null;
                pendingWinStartCoins = null;
                candidateWinCoins = null;
              }
              var betDiff = c - lastCoins; // قيمة سالبة
              lastCoins = c;
              send({
                event: 'update_balance',
                action: 'update_balance',
                diff: betDiff,
                coins: Math.round(c),
                reason: 'bet',
                timestamp: Date.now()
              });
              send({action:'alfa_sync', amount: Math.round(c)});
              return;
            }

            // 2. إضافة مكسب فوز (c > lastCoins)
            // في ألعاب السلوتس مثل Super 77 يتصاعد العداد بأنيميشن تدريجي (+100.. +500.. إلخ)
            // ننتظر 600ms بعد آخر زيادة حتى يستقر العداد تماماً ثم نرسل الفرق الإجمالي دفعة واحدة
            if (c > lastCoins) {
              if (pendingWinStartCoins == null) {
                pendingWinStartCoins = lastCoins;
              }
              candidateWinCoins = c;
              if (winDebounceTimer) clearTimeout(winDebounceTimer);
              winDebounceTimer = setTimeout(function(){
                try {
                  if (candidateWinCoins != null && pendingWinStartCoins != null && candidateWinCoins > pendingWinStartCoins) {
                    var winDiff = candidateWinCoins - pendingWinStartCoins;
                    lastCoins = candidateWinCoins;
                    send({
                      event: 'update_balance',
                      action: 'update_balance',
                      diff: winDiff,
                      coins: Math.round(candidateWinCoins),
                      reason: 'win',
                      timestamp: Date.now()
                    });
                    send({action:'alfa_sync', amount: Math.round(candidateWinCoins)});
                  }
                } finally {
                  winDebounceTimer = null;
                  pendingWinStartCoins = null;
                  candidateWinCoins = null;
                }
              }, 600);
            }
          }catch(e){}
        }, 200);
      }
      // ✅ إشعارات الرصيد الفورية من سيرفر اللعبة (update_balance وغيرها)
      //    — الرصيد المطلق يُرسل كـ alfa_sync ويُحسب الفرق في الـ Dart
      if (!window.__alfaMsgHook){
        window.__alfaMsgHook = true;
        window.addEventListener('message', function(ev){
          try{
            var d = ev && ev.data;
            if (d == null) return;
            var s = (typeof d === 'string') ? d : JSON.stringify(d);
            if (!/coin|balance|diamond|gold|update/i.test(s)) return;
            var o = (typeof d === 'string') ? JSON.parse(d) : d;
            if (o && (o.event === 'update_balance' || o.action === 'update_balance' || (o.diff != null && o.diff !== 0))) {
              send(o);
              return;
            }
            var coins = null;
            (function pick(x){
              if (!x || typeof x !== 'object' || coins != null) return;
              if (x.user && typeof x.user === 'object'){ pick(x.user); return; }
              var v = x.coins != null ? x.coins : (x.coin != null ? x.coin : (x.balance != null ? x.balance : (x.diamond != null ? x.diamond : (x.gold != null ? x.gold : null))));
              if (typeof v === 'number' && isFinite(v)) coins = Math.round(v);
            })(o);
            if (coins != null) send({action:'alfa_sync', amount: coins});
          }catch(e){}
        });
      }
      if (window.fun && !window.fun.__alfaHooked){
        var names = {
          openRecharge:'open_recharge', popUpBottomRecharge:'open_recharge',
          showRechargeDialog:'open_recharge',
          closeWebview:'close_game', closeCurWebView:'close_game',
          closeGameInRoomView:'close_game', closePage:'close_game'
        };
        for (var k in names){
          (function(key, act){
            var orig = window.fun[key];
            window.fun[key] = function(){
              send({action: act});
              try{ if (orig) return orig.apply(window.fun, arguments); }catch(e){}
            };
          })(k, names[k]);
        }
        window.fun.__alfaHooked = true;
      }
      // ✅ جاسوس debugging: نمرّر كل رسائل RTM وطلبات fetch/XHR
      //    للـ Dart لنرى كيف تتعامل اللعبة مع الرهان/الفوز فعلياً
      if (!window.__alfaNetSpy &&
          typeof __ALFA_SPY_ENABLED !== 'undefined' &&
          __ALFA_SPY_ENABLED){
        window.__alfaNetSpy = true;
        function spy(o){ try{ send({action:'alfa_spy', data: JSON.stringify(o).slice(0,500)}); }catch(e){} }
        ['RTMRequestMsg','RTMResponseMsg','requestMsg','requestMsgNew'].forEach(function(n){
          var orig = window[n];
          if (typeof orig === 'function'){
            window[n] = function(p){
              spy({fn:n, params: (typeof p==='string'?p.slice(0,400):p)});
              return orig.apply(window, arguments);
            };
          }
        });
        var of = window.fetch;
        if (of){
          window.fetch = function(u, opt){
            try{ spy({fn:'fetch', url:String(u).slice(0,200), body: opt && opt.body ? String(opt.body).slice(0,300) : ''}); }catch(e){}
            return of.apply(window, arguments);
          };
        }
        var oo = XMLHttpRequest.prototype.open, os = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.open = function(m,u){ this.__alfaUrl = m+' '+u; return oo.apply(this, arguments); };
        XMLHttpRequest.prototype.send = function(b){
          try{ spy({fn:'xhr', url:String(this.__alfaUrl||'').slice(0,200), body: b?String(b).slice(0,300):''}); }catch(e){}
          return os.apply(this, arguments);
        };
      }
      // ✅ قياس نسبة أبعاد اللعبة من داخل الـ WebView (canvas الداخلي)
      //    — الصندوق يتحجم تلقائياً على شكل اللعبة بدون قيم view_mode ثابتة.
      if (!window.__alfaSizeHook){
        window.__alfaSizeHook = true;
        function reportSize(){
          try{
            var c = document.querySelector('canvas');
            var w = 0, h = 0;
            if (c){
              w = c.width || 0; h = c.height || 0;           // دقة التصميم الداخلية
              if (!w || !h){ w = c.clientWidth || 0; h = c.clientHeight || 0; }
            }
            if (!w || !h){
              w = window.innerWidth || 0;
              h = document.documentElement.scrollHeight || window.innerHeight || 0;
            }
            if (w > 0 && h > 0){
              var ar = w / h;
              // تجاهل التغييرات الصغيرة عشان ما ندخلش حلقة resize ↔ measure
              if (!window.__alfaLastAr || Math.abs(ar - window.__alfaLastAr) > 0.02){
                window.__alfaLastAr = ar;
                send({action:'game_size', ratio: ar});
              }
            }
          }catch(e){}
        }
        window.addEventListener('resize', reportSize);
        setTimeout(reportSize, 400);
        setTimeout(reportSize, 1200);
        setInterval(reportSize, 5000);
      }
      return !!window.__alfaPollStarted;
    }catch(e){ return false; }
  }
  // ✅ إعادة حقن دورية كل ثانيتين — لو أعاد game-bridge تعريف AlfaBridge
  //    بعد الحقن الأول (Cocos init متأخر) تُفقد الـ hooks ونعود نلفّها
  //    بعد مهلة معقولة (10 محاولات = 20 ثانية)، نتوقف عن المحاولة ونرسل
  //    إشعاراً للـ Dart إذا لم يتوفر الجسر — ألعاب مستقبلية من game_links
  //    قد لا تعرض AlfaBridge، والصمت التام كان يخفي المشكلة.
  var __alfaRetryCount = 0;
  var __alfaMaxRetries = 10;
  var t = setInterval(function(){
    try{
      if (hook()){ clearInterval(t); }
      else if (++__alfaRetryCount >= __alfaMaxRetries){
        clearInterval(t);
        send({action:'alfa_bridge_missing'});
      }
    }catch(e){}
  }, 2000);
  if (!hook() && ++__alfaRetryCount >= __alfaMaxRetries){
    send({action:'alfa_bridge_missing'});
  }
})();
''';
    _controller.runJavaScript(js);
  }

  void _onJsMessage(JavaScriptMessage message) async {
    try {
      final data = jsonDecode(message.message) as Map<String, dynamic>;
      // ✅ قناة AlfaBridgeChannel الرسمية تبعت `event`، والقنوات القديمة
      //    (FlutterBridge) تبعت `action` — بنتعامل مع الاتنين بنفس المسار.
      final event = (data['event'] ?? data['action'] ?? '').toString();
      debugPrint('[AlfaGame] js event=$event amount=${data['amount']} coins=${data['coins']} spy=${data['data'] ?? ''}');
      switch (event) {
        case 'game_size':
          final ratio = (data['ratio'] as num?)?.toDouble();
          if (ratio != null && ratio > 0) widget.onGameRatio?.call(ratio);
          break;
        case 'closeWebView':
        case 'navigate_back':
        case 'close_game':
        case 'exit_game':
          _requestHostClose();
          break;
        case 'showLoading':
          if (mounted) setState(() => _loading = true);
          break;
        case 'closeLoading':
          if (mounted) setState(() => _loading = false);
          break;
        case 'open_recharge':
          _openRecharge();
          break;
        case 'alfa_bridge_missing':
          // ✅ الجسر لم يتوفر بعد المهلة — coin sync لن يعمل لهذه اللعبة.
          //    يتم تسجيل خطأ فقط بدون قطع التطبيق.
          debugPrint('[AlfaGame] ERROR: window.AlfaBridge not found after timeout — coin sync disabled for ${widget.gameId}');
          break;
        case 'update_balance':
        case 'coins_changed':
        case 'balance_update':
          // ✅ حدث التسوية الرسمي من AlfaBridgeChannel:
          //    coins  = الرصيد الإجمالي الجديد بعد الحركة
          //    diff   = الحركة بالسالب (bet) أو بالموجب (win)
          //    reason = 'bet' | 'win'
          //    styeParty = تفاصيل الطلب (orderId/roundId/type/coin/...)
          final rawCoins = data['coins'] ?? data['balance'];
          final coins = (rawCoins is num) ? rawCoins.toInt() : null;
          final diff = (data['diff'] as num?)?.toInt() ?? (data['change'] as num?)?.toInt();
          final sp = data['styeParty'] is Map ? (data['styeParty'] as Map) : null;
          final orderId = (data['orderId'] ?? sp?['orderId'])?.toString();
          debugPrint('[AlfaGame] update_balance coins=$coins diff=$diff orderId=$orderId reason=${data['reason']}');
          if (coins != null) {
            _lastGameCoins = coins;
          }

          if (orderId != null && orderId.isNotEmpty) {
            if (_processedOrders.contains(orderId)) {
              debugPrint('[AlfaGame] skip duplicate orderId: $orderId');
              break;
            }
            _processedOrders.add(orderId);
            if (_processedOrders.length > 200) {
              _processedOrders.remove(_processedOrders.first);
            }
          }

          if (diff != null && diff != 0) {
            if (diff < 0) {
              await _handleBet(-diff);
              if (orderId != null) {
                unawaited(_recordProviderOrder(
                  orderId: orderId,
                  gameId: widget.gameId,
                  roundId: sp?['roundId']?.toString(),
                  uid: sp?['uid']?.toString(),
                  coin: -diff,
                  type: '1',
                  direction: 'debit',
                ));
              }
            } else {
              await _handleWin(diff);
              if (orderId != null) {
                unawaited(_recordProviderOrder(
                  orderId: orderId,
                  gameId: widget.gameId,
                  roundId: sp?['roundId']?.toString(),
                  uid: sp?['uid']?.toString(),
                  coin: diff,
                  type: '2',
                  direction: 'credit',
                ));
              }
            }
          } else if (sp != null && sp['coin'] != null) {
            final spCoin = (sp['coin'] as num?)?.toInt() ?? 0;
            final spType = sp['type']?.toString();
            if (spType == '1' && spCoin > 0) {
              await _handleBet(spCoin);
              if (orderId != null) {
                unawaited(_recordProviderOrder(
                  orderId: orderId,
                  gameId: widget.gameId,
                  roundId: sp['roundId']?.toString(),
                  uid: sp['uid']?.toString(),
                  coin: spCoin,
                  type: '1',
                  direction: 'debit',
                ));
              }
            } else if (spType == '2' && spCoin > 0) {
              await _handleWin(spCoin);
              if (orderId != null) {
                unawaited(_recordProviderOrder(
                  orderId: orderId,
                  gameId: widget.gameId,
                  roundId: sp['roundId']?.toString(),
                  uid: sp['uid']?.toString(),
                  coin: spCoin,
                  type: '2',
                  direction: 'credit',
                ));
              }
            }
          } else if (coins != null) {
            _applyGameCoins(coins);
          }
          break;
        case 'alfa_bet':
          final amount = (data['amount'] as num?)?.toInt() ?? 0;
          if (amount > 0) await _handleBet(amount);
          break;
        case 'alfa_win':
          final amount = (data['amount'] as num?)?.toInt() ?? 0;
          if (amount > 0) await _handleWin(amount);
          break;
        case 'alfa_sync':
          final amount = (data['amount'] as num?)?.toInt();
          if (amount != null) {
            _trackRoundState(amount);
            // ✅ لا نستدعي _applyGameCoins هنا إطلاقاً:
            //    alfa_sync يُرسل دورياً كل 300ms لقراءة العداد على الشاشة،
            //    وفي ألعاب مثل Super77 العداد يتصاعد بأنيميشن تدريجي،
            //    مما كان يسبب احتساب كل قفزة في الأنيميشن كفوز حقيقي وتضخم الكوينز.
            //    التسوية المالية محصورة في update_balance أو alfa_bet/alfa_win.
          }
          break;
        default:
          break;
      }
    } catch (_) {}
  }

  /// يحدّث حالة الجولة المفتوحة من فرق رصيد اللعبة المطلق:
  /// سالب = رهان جديد اتخصم، موجب = فوز/إضافة وصلت (الجولة اتقفلت).
  void _trackRoundState(int? gameCoins) {
    if (gameCoins == null || gameCoins < 0) return;
    final prev = _prevSyncCoins;
    _prevSyncCoins = gameCoins;
    if (prev == null) return;
    final delta = gameCoins - prev;
    if (delta < 0) {
      // خصم رهان — الجولة مفتوحة لحد ما يوصل فرق موجب (الفوز)
      // أو تعدي مهلة أمان (الجولة اتخسرت/اتلغت).
      _roundOpen = true;
      _roundOpenTimer?.cancel();
      _roundOpenTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && _roundOpen) {
          setState(() => _roundOpen = false);
        }
      });
      if (mounted) setState(() {});
    } else if (delta > 0) {
      _roundOpen = false;
      _roundOpenTimer?.cancel();
      if (mounted) setState(() {});
    }
  }

  void _openRecharge() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const WalletMainScreen()),
    );
  }

  /// رصيد لعبة مطلق (من poll أو إشعار السيرفر) — نحسب الفرق فقط
  /// حتى لا يتكرر الخصم/الإضافة إذا وصل نفس التغيير عبر مسارين.
  void _applyGameCoins(int? gameCoins) {
    if (gameCoins == null || gameCoins < 0) return;
    final prev = _lastGameCoins;
    _lastGameCoins = gameCoins;
    if (prev == null) return; // أول قراءة = خط أساس، لا نطبّق الفارق التراكمي
    final delta = gameCoins - prev;
    if (delta < 0) {
      _handleBet(-delta);
    } else if (delta > 0) {
      _handleWin(delta);
    }
  }

  /// خصم الرهان من الرصيد الحقيقي — يعكس أي نقص في رصيد اللعبة.
  /// اللعبة تدير اقتصادها الافتراضي بنفسها؛ نحن نمرّر الفرق فقط.
  Future<void> _handleBet(int amount) async {
    if (amount <= 0) return;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    _lastBet = amount;
    _isApplyingFromGame = true;
    try {
      userProvider.deductCoinsLocally(amount);
      debugPrint('[AlfaGame] bet $amount (atomic RPC)');

      // ✅ RPC ذرّي مع fallback موثوق لتحديث Supabase
      final res = await SupabaseDataService().adjustUserWallet(user.uid, -amount, 0);
      debugPrint('[AlfaGame] bet $amount result: $res');
      if (res?['status'] == 'insufficient_coins') {
        userProvider.addCoinsLocally(amount);
        _pushTrueCoins(force: true);
        return;
      }
      _incrementPool(amount);
    } finally {
      Future.microtask(() => _isApplyingFromGame = false);
    }
  }

  /// إضافة مكافأة الفوز للرصيد الحقيقي + تسجيل النتيجة
  Future<void> _handleWin(int amount) async {
    if (amount <= 0) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    final bet = _lastBet;
    _lastBet = 0;

    _isApplyingFromGame = true;
    try {
      userProvider.addCoinsLocally(amount);
      debugPrint('[AlfaGame] win $amount (bet=$bet) (atomic RPC)');

      // ✅ الفوز مضروب بالفعل في المضاعف جوّه اللعبة — نضيفه كما هو
      final res = await SupabaseDataService().adjustUserWallet(user.uid, amount, 0);
      debugPrint('[AlfaGame] win $amount result: $res');
      _incrementPool(-amount);
      _recordBet(user, bet, amount);

      // 🏆 إطلاق شعار ولافتة الفوز الكبير في شريط الغرف للمنصة إذا كان الفوز كبيراً (>= 5,000 كوينز)
      if (amount >= 5000) {
        unawaited(() async {
          try {
            final gameName = (widget.title != null && widget.title!.isNotEmpty) ? widget.title! : widget.gameId;
            final contentText = '🏆 فاز بـ $amount كوينز في لعبة $gameName!';
            final broadcastId = const Uuid().v4();
            
            // 1. تسجيل البث في Supabase ليصل لكل مستخدمي التطبيق فوراً
            await SupabaseDataService().recordBroadcast(
              senderUid: user.uid,
              senderName: user.name,
              senderPhotoUrl: user.avatarUrl,
              roomId: widget.roomId ?? '',
              roomName: '',
              content: contentText,
              giftIcon: 'assets/images/common_gold_ic_8.webp',
              type: 'big_gift',
              broadcastId: broadcastId,
            );

            // 2. إظهار اللافتة فوراً على شاشة هذا الجهاز محلياً
            GlobalBannerService.instance.echoBroadcastLocally({
              'id': broadcastId,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'sender_uid': user.uid,
              'sender_name': user.name,
              'sender_photo_url': user.avatarUrl,
              'room_id': widget.roomId ?? '',
              'room_name': '',
              'content': contentText,
              'gift_icon': 'assets/images/common_gold_ic_8.webp',
              'gift_name': gameName,
              'type': 'big_gift',
              'value': amount,
              'count': 1,
              'total_cost': amount,
            });
          } catch (e) {
            debugPrint('[AlfaGame] broadcast win banner error: $e');
          }
        }());
      }
    } finally {
      Future.microtask(() => _isApplyingFromGame = false);
    }
  }

  /// معرّف اللعبة الداخلي للـ pool/records — fe-game-super77 → super77
  /// (أو poolId مخصص عندما تتشارك منصتان نفس gameId)
  String get _poolGameId =>
      widget.poolId ?? widget.gameId.replaceFirst('fe-game-', '');


  /// تسجيل الطلب في Supabase لمنع تكرار التسوية في حال أرسل المزوّد Callback S2S لاحقاً
  Future<void> _recordProviderOrder({
    required String orderId,
    required String gameId,
    String? roundId,
    String? uid,
    required int coin,
    required String type,
    required String direction,
  }) async {
    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final userId = uid ?? user?.uid ?? '';
      if (userId.isEmpty) return;
      final url = Uri.parse('${SupabaseConfig.projectUrl}/rest/v1/game_provider_orders');
      await SafeHttp.post(
        url,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=ignore-duplicates',
        },
        body: jsonEncode({
          'order_id': orderId,
          'game_id': gameId,
          'round_id': roundId ?? 'rnd_${DateTime.now().millisecondsSinceEpoch}',
          'uid': userId,
          'coin': coin,
          'type': type,
          'direction': direction,
          'makeup': false,
          'result': {'status': 'ok', 'client_settled': true},
        }),
      );
    } catch (_) {}
  }

  Future<void> _incrementPool(int amount) async {
    try {
      final rpcUrl = Uri.parse(
        '${SupabaseConfig.projectUrl}/rest/v1/rpc/increment_game_pool_balance',
      );
      await SafeHttp.post(
        rpcUrl,
        headers: _headers,
        body: jsonEncode({
          'p_game_id': _poolGameId,
          'p_amount': amount,
        }),
      );
    } catch (_) {}
  }

  Future<void> _recordBet(
    dynamic user,
    int betAmount,
    int winAmount,
  ) async {
    try {
      final recordUrl = Uri.parse(
        '${SupabaseConfig.projectUrl}/rest/v1/game_bet_records',
      );
      await SafeHttp.post(
        recordUrl,
        headers: {
          ..._headers,
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'game_id': _poolGameId,
          'user_id': user.uid,
          'user_name': (user.name.isNotEmpty) ? user.name : 'Player',
          'bet_amount': betAmount,
          'win_amount': winAmount,
          'net_result': winAmount - betAmount,
          'is_win': winAmount > 0,
          'created_at': DateTime.now().toIso8601String(),
        }),
      );
    } catch (_) {}
  }

  void _showGameRecords() {
    final uid = Provider.of<UserProvider>(context, listen: false)
        .currentUser
        ?.uid ??
        '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _GameRecordsSheet(uid: uid, gameId: _poolGameId),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ شفافية كاملة: لا scrim، لا خلفية سودا، لا اسم لعبة، لا كاس،
    //    ولا حتى دائرة داكنة للزر. الإغلاق بالرجوع / الضغط خارج الصندوق،
    //    والسجل بضغط مطوّل على منطقة غير مرئية أعلى اليمين.
    // ✅ مفيش زرار إغلاق ظاهر — زرار ✕ جوه اللعبة نفسها هو اللي بيقفل،
    //    وأي طلب إغلاق بيعدي على الـ host (دايالوج تصغير/إغلاق).
    //    منطقة غير مرئية فوق يمين للضغط المطوّل = سجل المباريات.
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(child: WebViewWidget(controller: _controller)),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(color: Color(0xFFFFC525)),
            ),
          Positioned(
            top: 30,
            right: 2,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onLongPress: _showGameRecords,
              child: const SizedBox(width: 40, height: 40),
            ),
          ),
        ],
      ),
    );
  }
}

/// سجل مباراة اللعبة + ترتيب المتصدرين — يقرأ من game_bet_records
class _GameRecordsSheet extends StatefulWidget {
  final String uid;
  final String gameId;
  const _GameRecordsSheet({required this.uid, required this.gameId});

  @override
  State<_GameRecordsSheet> createState() => _GameRecordsSheetState();
}

class _GameRecordsSheetState extends State<_GameRecordsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _myRecords = [];
  List<Map<String, dynamic>> _ranking = [];

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final base = SupabaseConfig.projectUrl;
      final results = await Future.wait([
        // سجلاتي الأخيرة
        SafeHttp.get(
          Uri.parse(
            '$base/rest/v1/game_bet_records'
            '?game_id=eq.${widget.gameId}&user_id=eq.${widget.uid}'
            '&select=bet_amount,win_amount,is_win,created_at'
            '&order=created_at.desc&limit=30',
          ),
          headers: _headers,
        ),
        // سجلات اللعبة الأخيرة لتجميع الترتيب
        SafeHttp.get(
          Uri.parse(
            '$base/rest/v1/game_bet_records'
            '?game_id=eq.${widget.gameId}'
            '&select=user_id,user_name,win_amount'
            '&order=created_at.desc&limit=2000',
          ),
          headers: _headers,
        ),
      ]);

      if (!mounted) return;
      final mine = jsonDecode(results[0].body);
      if (mine is List) {
        _myRecords = mine.whereType<Map<String, dynamic>>().toList();
      }

      final all = jsonDecode(results[1].body);
      if (all is List) {
        final totals = <String, Map<String, dynamic>>{};
        for (final row in all.whereType<Map<String, dynamic>>()) {
          final uid = row['user_id']?.toString() ?? '';
          if (uid.isEmpty) continue;
          final win = (row['win_amount'] as num?)?.toDouble() ?? 0;
          final entry = totals.putIfAbsent(uid, () => {
                'user_id': uid,
                'user_name': row['user_name']?.toString() ?? 'Player',
                'total': 0.0,
              });
          entry['total'] = (entry['total'] as double) + win;
        }
        final list = totals.values.toList()
          ..sort((a, b) =>
              (b['total'] as double).compareTo(a['total'] as double));
        _ranking = list.take(10).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF171226),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.emoji_events,
                    color: Color(0xFFFFC525), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: DText(
                    isAr ? 'سجل اللعبة والترتيب' : 'Game Records & Ranking',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          if (_loading)
            const Expanded(
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFFFFC525)),
              ),
            )
          else
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                children: [
                  _sectionTitle(isAr ? '🏆 المتصدرين' : '🏆 Top Players'),
                  if (_ranking.isEmpty)
                    _emptyText(isAr ? 'لا توجد نتائج بعد' : 'No results yet')
                  else
                    ..._ranking.asMap().entries.map(
                          (e) => _rankingTile(e.key + 1, e.value, isAr),
                        ),
                  const SizedBox(height: 16),
                  _sectionTitle(isAr ? '📜 آخر مبارياتي' : '📜 My Recent Games'),
                  if (_myRecords.isEmpty)
                    _emptyText(isAr ? 'لم تلعب بعد' : 'No games yet')
                  else
                    ..._myRecords.map((r) => _recordTile(r, isAr)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        child: DText(
          text,
          style: const TextStyle(
            color: Color(0xFFFFC525),
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );

  Widget _emptyText(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: DText(
          text,
          style: const TextStyle(color: Colors.white38, fontSize: 12),
          textAlign: TextAlign.center,
        ),
      );

  Widget _rankingTile(int rank, Map<String, dynamic> p, bool isAr) {
    final medal = rank == 1
        ? '🥇'
        : rank == 2
            ? '🥈'
            : rank == 3
                ? '🥉'
                : '$rank';
    final total = (p['total'] as num?)?.toInt() ?? 0;
    final name = p['user_name']?.toString() ?? 'Player';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: DText(
              medal,
              style: const TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: DText(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DText(
            '$total',
            style: const TextStyle(
              color: Color(0xFF00E676),
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordTile(Map<String, dynamic> r, bool isAr) {
    final bet = (r['bet_amount'] as num?)?.toInt() ?? 0;
    final win = (r['win_amount'] as num?)?.toInt() ?? 0;
    final isWin = r['is_win'] == true;
    final dt = DateTime.tryParse(r['created_at']?.toString() ?? '');
    final time = dt == null
        ? ''
        : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isWin ? Icons.emoji_events : Icons.close,
            color: isWin ? const Color(0xFFFFC525) : Colors.white38,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(
                  isAr
                      ? 'رهان: $bet  →  ربح: $win'
                      : 'Bet: $bet  →  Win: $win',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (time.isNotEmpty)
                  DText(
                    time,
                    style: const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
              ],
            ),
          ),
          DText(
            isWin ? '+$win' : '-$bet',
            style: TextStyle(
              color: isWin ? const Color(0xFF00E676) : Colors.redAccent,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
