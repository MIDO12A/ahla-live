// lib/features/host_agency/screens/agency_chat_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// قروب الوكالة — دردشة خاصة بأعضاء الوكالة فقط
// نص + صورة + صوت + view-once + حماية لقطة الشاشة
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
// record package removed — audio recording temporarily disabled
import '../../../core/supabase_compat.dart';

import '../../../core/auth/auth_service.dart';
import '../../../core/realtime/realtime_subscription.dart';
import '../../../core/realtime/throttled_update_buffer.dart';
import '../../../core/ui/in_app_toast.dart';
import '../../../core/ui/screenshot_guard.dart';
import '../../../core/widgets/smart_image.dart';
import '../data/agency_chat_models.dart';
import '../data/agency_chat_repository.dart';
import 'package:zero/core/dtext.dart';

// ── palette ──────────────────────────────────────────────────────────────────
const _bg      = Color(0xFF03030A);
const _bgCard  = Color(0x880A0820);
const _border  = Color(0x2D9C6BFF);
const _purple  = Color(0xFF9C6BFF);
const _gold    = Color(0xFFF6C453);
const _cyan    = Color(0xFF00D4FF);
const _red     = Color(0xFFFF4D6D);
const _textMain  = Color(0xFFE8E6FF);
const _textMuted = Color(0xFF8A88AA);

// ─────────────────────────────────────────────────────────────────────────────
class AgencyChatScreen extends StatefulWidget {
  const AgencyChatScreen({
    super.key,
    required this.agencyId,
    required this.agencyName,
    required this.myRole,
  });

  final String           agencyId;
  final String           agencyName;
  final AgencyMemberRole myRole;

  @override
  State<AgencyChatScreen> createState() => _AgencyChatScreenState();
}

class _AgencyChatScreenState extends State<AgencyChatScreen> {
  final List<AgencyChatMessage> _messages = [];
  final Map<String, AgencyChatUserMeta> _userCache = {};
  final Set<String> _fetching = {};
  final ScrollController _scroll = ScrollController();
  final TextEditingController _textCtrl = TextEditingController();

  RealtimeSubscription? _rt;
  late final ThrottledUpdateBuffer<AgencyChatMessage> _buffer;

  bool _loading   = true;
  bool _sending   = false;
  bool _isViewOnceMode = false;
  int  _viewOnceDuration = 10; // ثوانٍ (للنص والصورة)

  // كتم
  DateTime? _mutedUntil;

  // صوت
  bool _isRecording = false;
  int  _recordSeconds = 0;
  Timer? _recordTimer;

  bool get _canManage =>
      widget.myRole == AgencyMemberRole.owner ||
      widget.myRole == AgencyMemberRole.supervisor;

  @override
  void initState() {
    super.initState();
    // كشف لقطة الشاشة
    SystemChannels.lifecycle.setMessageHandler(_onLifecycle);

    _buffer = ThrottledUpdateBuffer<AgencyChatMessage>(
      onFlush: _appendMessages,
      isActive: () => mounted,
      interval: const Duration(milliseconds: 80),
      coalesce: false,
      maxPending: 300,
    );
    _load();
    _rt = AgencyChatRepository.subscribeInserts(
      agencyId: widget.agencyId,
      onMessage: (m) {
        _buffer.push(m);
        _ensureMeta(m.senderId);
      },
    );
    _checkMuteStatus();
  }

  Future<String?> _onLifecycle(String? msg) async {
    // كشف لقطة الشاشة على Android
    if (msg == 'AppLifecycleState.inactive' && Platform.isAndroid) {
      await AgencyChatRepository.reportScreenshot(widget.agencyId);
    }
    return null;
  }

  Future<void> _load() async {
    final msgs = await AgencyChatRepository.fetchHistory(agencyId: widget.agencyId);
    if (!mounted) return;
    setState(() { _messages.addAll(msgs); _loading = false; });
    _scrollBottom();
    final ids = msgs.map((m) => m.senderId).toSet().toList();
    await _fetchMetaBatch(ids);
  }

  Future<void> _checkMuteStatus() async {
    final until = await AgencyChatRepository.getMyMuteStatus(widget.agencyId);
    if (mounted) setState(() => _mutedUntil = until);
  }

  void _appendMessages(List<AgencyChatMessage> batch) {
    if (!mounted || batch.isEmpty) return;
    setState(() {
      _messages.addAll(batch);
      if (_messages.length > 300) _messages.removeRange(0, _messages.length - 300);
    });
    _scrollBottom();
  }

  Future<void> _fetchMetaBatch(List<String> ids) async {
    final toFetch = ids.where((id) => !_userCache.containsKey(id) && !_fetching.contains(id)).toList();
    if (toFetch.isEmpty) return;
    for (final id in toFetch) _fetching.add(id);
    final meta = await AgencyChatRepository.fetchUserMeta(
      agencyId: widget.agencyId,
      userIds: toFetch,
    );
    if (!mounted) return;
    setState(() {
      _userCache.addAll(meta);
      for (final id in toFetch) _userCache.putIfAbsent(id, () => AgencyChatUserMeta.empty);
      _fetching.removeAll(toFetch);
    });
  }

  void _ensureMeta(String userId) {
    if (!_userCache.containsKey(userId) && !_fetching.contains(userId)) {
      _fetchMetaBatch([userId]);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  AgencyChatMessage _enrich(AgencyChatMessage m) {
    final meta = _userCache[m.senderId];
    if (meta == null) return m;
    return m.copyWith(
      avatarUrl:       meta.avatarUrl,
      chatFrameUrl:    meta.chatFrameUrl,
      vipLevel:        meta.vipLevel,
      agencyRole:      meta.agencyRole,
      countryCode:     meta.countryCode,
      necklaceIconUrl: meta.necklaceIconUrl,
    );
  }

  // ── إرسال نص ─────────────────────────────────────────────────────────────
  Future<void> _sendText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() { _sending = true; });
    _textCtrl.clear();
    final err = await AgencyChatRepository.sendText(
      agencyId: widget.agencyId,
      body: text,
      isViewOnce: _isViewOnceMode,
      viewDurationSecs: _isViewOnceMode ? _viewOnceDuration : null,
    );
    if (mounted) {
      setState(() { _sending = false; });
      if (err != null && err != 'ok') {
        _showError(_mapError(err));
      }
    }
  }

  // ── إرسال صورة ───────────────────────────────────────────────────────────
  Future<void> _pickAndSendImage() async {
    final picker = ImagePicker();
    final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (xfile == null || !mounted) return;
    setState(() => _sending = true);
    final err = await AgencyChatRepository.sendImage(
      agencyId: widget.agencyId,
      imageFile: File(xfile.path),
      isViewOnce: _isViewOnceMode,
      viewDurationSecs: _isViewOnceMode ? _viewOnceDuration : null,
    );
    if (mounted) {
      setState(() => _sending = false);
      if (err != null) _showError(_mapError(err));
    }
  }

  // ── تسجيل صوتي — مؤقتاً معطّل (record package غير متوافق) ─────────────
  Future<void> _startRecording() async {
    _showError('التسجيل الصوتي سيكون متاحاً في التحديث القادم');
  }

  Future<void> _stopRecording({bool cancel = false}) async {
    setState(() { _isRecording = false; });
    // TODO: إعادة تفعيل التسجيل الصوتي عند توافر حزمة record متوافقة مع AGP الحديث
  }

  // ── كتم عضو (ضغط طويل على رسالة) ────────────────────────────────────────
  void _onLongPressMessage(AgencyChatMessage msg) {
    if (!_canManage || msg.isMine || msg.isSystem) return;
    final role = msg.agencyRole;
    if (role == AgencyMemberRole.owner) return;
    if (widget.myRole == AgencyMemberRole.supervisor && role == AgencyMemberRole.supervisor) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0B1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MuteSheet(
        displayName: msg.displayName,
        onMute: (hours) async {
          Navigator.pop(context);
          final res = await AgencyChatRepository.muteMember(
            agencyId: widget.agencyId,
            userId: msg.senderId,
            hours: hours,
          );
          final status = res['status']?.toString() ?? '';
          if (mounted) {
            KayanInAppToast.info(
              hours == 0
                  ? 'تم رفع الكتم عن ${msg.displayName}'
                  : status == 'muted'
                      ? 'تم كتم ${msg.displayName} لـ $hours ساعة'
                      : _mapError(status),
            );
          }
        },
      ),
    );
  }

  // ── إظهار قائمة مدة view-once ────────────────────────────────────────────
  void _showViewOnceDurationPicker() {
    final options = [5, 10, 30, 60, 120, 300];
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0D0B1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DText('مدة عرض الرسالة',
              style: GoogleFonts.tajawal(color: _textMain, fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          ...options.map((s) => ListTile(
            title: DText(_formatDuration(s),
              style: GoogleFonts.tajawal(color: _textMain)),
            trailing: _viewOnceDuration == s
                ? const Icon(Icons.check_circle_rounded, color: _purple)
                : null,
            onTap: () {
              setState(() => _viewOnceDuration = s);
              Navigator.pop(context);
            },
          )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  String _formatDuration(int s) {
    if (s < 60) return '$s ثانية';
    return '${s ~/ 60} دقيقة';
  }

  String _mapError(String e) {
    switch (e) {
      case 'muted':             return 'أنت مكتوم حالياً من الدردشة';
      case 'not_member':        return 'لست عضواً نشطاً في الوكالة';
      case 'empty_message':     return 'الرسالة فارغة';
      case 'upload_error':      return 'فشل رفع الملف، حاول مجدداً';
      default:                  return 'حدث خطأ، حاول مجدداً';
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    KayanInAppToast.warning(msg);
  }

  @override
  void dispose() {
    SystemChannels.lifecycle.setMessageHandler(null);
    _buffer.flushNow();
    _buffer.dispose();
    _rt?.dispose();
    _scroll.dispose();
    _textCtrl.dispose();
    _recordTimer?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isMuted = _mutedUntil != null && _mutedUntil!.isAfter(DateTime.now());

    // ScreenshotGuard: يمنع التقاط الشاشة (Android FLAG_SECURE + iOS overlay)
    // حصراً في قروب الوكالة — يُلغى تلقائياً عند dispose()
    return ScreenshotGuard(
      child: Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Column(
        children: [
          // ── قائمة الرسائل ────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: _purple))
                : _messages.isEmpty
                    ? _emptyState()
                    : ShaderMask(
                        shaderCallback: (b) => const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.white, Colors.white],
                          stops: [0.0, 0.06, 1.0],
                        ).createShader(b),
                        blendMode: BlendMode.dstIn,
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                          itemCount: _messages.length,
                          cacheExtent: 1200,
                          itemBuilder: (ctx, i) {
                            final msg = _enrich(_messages[i]);
                            return RepaintBoundary(
                              key: ValueKey(msg.id),
                              child: _AgencyBubble(
                                message: msg,
                                canManage: _canManage,
                                onLongPress: () => _onLongPressMessage(msg),
                                onViewOnceOpen: () => _openViewOnce(msg),
                              ),
                            );
                          },
                        ),
                      ),
          ),

          // ── شريط الإدخال ─────────────────────────────────────────────────
          _AgencyChatInputBar(
            controller: _textCtrl,
            isMuted: isMuted,
            mutedUntil: _mutedUntil,
            sending: _sending,
            isRecording: _isRecording,
            recordSeconds: _recordSeconds,
            isViewOnceMode: _isViewOnceMode,
            viewOnceDuration: _viewOnceDuration,
            onSend: _sendText,
            onPickImage: _pickAndSendImage,
            onRecordStart: _startRecording,
            onRecordStop: () => _stopRecording(),
            onRecordCancel: () => _stopRecording(cancel: true),
            onToggleViewOnce: () => setState(() => _isViewOnceMode = !_isViewOnceMode),
            onPickDuration: _showViewOnceDurationPicker,
          ),
        ],
      ),
    ),   // Scaffold
    );   // ScreenshotGuard
  }

  // ── فتح view-once ─────────────────────────────────────────────────────────
  Future<void> _openViewOnce(AgencyChatMessage msg) async {
    final result = await AgencyChatRepository.openViewOnce(msg.id);
    if (result == null || !mounted) return;
    final status = result['status']?.toString() ?? '';
    if (status == 'already_viewed') {
      KayanInAppToast.info('لقد شاهدت هذه الرسالة مسبقاً');
      return;
    }
    if (status != 'ok') return;

    // فتح عارض view-once
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ViewOnceViewer(
          messageType: AgencyChatMessageType.fromString(result['message_type']?.toString()),
          body:        result['body']?.toString(),
          assetUrl:    result['asset_url']?.toString(),
          durationSecs: result['view_duration_seconds'] as int? ??
                        result['asset_duration_secs']   as int? ?? 10,
        ),
      ),
    );

    // بعد العودة نعلّم الرسالة كـ "مشاهَدة"
    setState(() {
      final idx = _messages.indexWhere((m) => m.id == msg.id);
      if (idx >= 0) {
        _messages[idx] = _messages[idx].copyWith(viewedByMe: true);
      }
    });
  }

  AppBar _buildAppBar() => AppBar(
    backgroundColor: const Color(0xFF0A0820),
    elevation: 0,
    leading: IconButton(
      icon: const Icon(Icons.arrow_back_ios_rounded, color: _textMain),
      onPressed: () => Navigator.pop(context),
    ),
    title: Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [_purple, _cyan]),
          ),
          child: const Icon(Icons.groups_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DText(widget.agencyName,
              style: GoogleFonts.tajawal(color: _textMain, fontSize: 15, fontWeight: FontWeight.w700)),
            DText('قروب الوكالة',
              style: GoogleFonts.tajawal(color: _textMuted, fontSize: 11)),
          ],
        ),
      ],
    ),
    actions: [
      // زر معلومات أو إعدادات
      IconButton(
        icon: const Icon(Icons.info_outline_rounded, color: _textMuted),
        onPressed: () {},
      ),
    ],
  );

  Widget _emptyState() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.chat_bubble_outline_rounded, color: _textMuted, size: 64),
        const SizedBox(height: 12),
        DText('لا توجد رسائل بعد',
          style: GoogleFonts.tajawal(color: _textMuted, fontSize: 16)),
        DText('كن أول من يرسل رسالة في قروب الوكالة',
          style: GoogleFonts.tajawal(color: _textMuted, fontSize: 12)),
      ],
    ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// فقاعة الرسالة
// ═════════════════════════════════════════════════════════════════════════════
class _AgencyBubble extends StatelessWidget {
  const _AgencyBubble({
    required this.message,
    required this.canManage,
    required this.onLongPress,
    required this.onViewOnceOpen,
  });
  final AgencyChatMessage message;
  final bool canManage;
  final VoidCallback onLongPress;
  final VoidCallback onViewOnceOpen;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) return _SystemBubble(message: message);
    return _UserBubble(
      message: message,
      canManage: canManage,
      onLongPress: onLongPress,
      onViewOnceOpen: onViewOnceOpen,
    );
  }
}

// ── رسالة النظام (📸 محاولة لقطة / انضمام) ──────────────────────────────────
class _SystemBubble extends StatelessWidget {
  const _SystemBubble({required this.message});
  final AgencyChatMessage message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xBBFF8F00),
            borderRadius: BorderRadius.circular(20),
          ),
          child: DText(
            message.body ?? '',
            style: GoogleFonts.tajawal(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

// ── رسالة مستخدم ─────────────────────────────────────────────────────────────
class _UserBubble extends StatelessWidget {
  const _UserBubble({
    required this.message,
    required this.canManage,
    required this.onLongPress,
    required this.onViewOnceOpen,
  });
  final AgencyChatMessage message;
  final bool canManage;
  final VoidCallback onLongPress;
  final VoidCallback onViewOnceOpen;

  Color get _nameColor {
    const colors = [
      Color(0xFFFFB300), Color(0xFF64B5F6), Color(0xFFAED581),
      Color(0xFFBA68C8), Color(0xFF4DD0E1), Color(0xFFFF80AB),
      Color(0xFFFF8A65), Color(0xFFFFF176),
    ];
    return colors[message.senderId.hashCode.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, right: 4, left: 4),
      child: GestureDetector(
        onLongPress: canManage ? onLongPress : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // صف: أفاتار + اسم + دور + بيانات
            Row(
              textDirection: TextDirection.rtl,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _Avatar(url: message.avatarUrl, size: 34),
                const SizedBox(width: 6),
                Expanded(child: _MetaRow(message: message, nameColor: _nameColor)),
              ],
            ),
            const SizedBox(height: 4),
            // محتوى الرسالة
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 40),
              child: Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _buildContent(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (message.isViewOnce) {
      return _ViewOnceBubble(
        message: message,
        onOpen: onViewOnceOpen,
      );
    }
    if (message.isText) {
      return _TextBubble(body: message.body ?? '');
    }
    if (message.isImage) {
      return _ImageBubble(url: message.assetUrl ?? '');
    }
    if (message.isAudio) {
      return _AudioBubble(
        url: message.assetUrl ?? '',
        durationSecs: message.assetDurationSecs ?? 0,
      );
    }
    return const SizedBox.shrink();
  }
}

// ── أفاتار ───────────────────────────────────────────────────────────────────
class _Avatar extends StatelessWidget {
  const _Avatar({this.url, required this.size});
  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: _border, width: 1.2),
      ),
      clipBehavior: Clip.antiAlias,
      child: url != null && url!.isNotEmpty
          ? SmartImage(url: url!, fit: BoxFit.cover)
          : Container(
              color: _bgCard,
              child: const Icon(Icons.person_rounded, color: _textMuted, size: 18),
            ),
    );
  }
}

// ── صف البيانات (اسم + دور + مستوى + علم + قلادة) ──────────────────────────
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.message, required this.nameColor});
  final AgencyChatMessage message;
  final Color nameColor;

  String _flag(String? code) {
    if (code == null || code.length != 2) return '';
    try {
      final u = code.toUpperCase();
      final a = u.codeUnitAt(0) - 0x41 + 0x1F1E6;
      final b = u.codeUnitAt(1) - 0x41 + 0x1F1E6;
      return String.fromCharCode(a) + String.fromCharCode(b);
    } catch (_) { return ''; }
  }

  @override
  Widget build(BuildContext context) {
    final flag = _flag(message.countryCode);
    return Wrap(
      textDirection: TextDirection.rtl,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      runSpacing: 2,
      children: [
        // 1. الاسم
        DText(
          message.displayName,
          style: GoogleFonts.tajawal(
            color: nameColor, fontSize: 12, fontWeight: FontWeight.w800,
            shadows: [Shadow(color: Colors.black.withValues(alpha: 0.6), blurRadius: 4)],
          ),
          textDirection: TextDirection.rtl,
        ),
        // 2. شارة دور الوكالة
        if (message.agencyRole != null && message.agencyRole != AgencyMemberRole.host)
          _RoleBadge(role: message.agencyRole!),
        // 3. المستوى
        _LevelChip(level: (message.vipLevel > 0) ? message.vipLevel * 10 : 1),
        // 4. علم
        if (flag.isNotEmpty)
          DText(flag, style: const TextStyle(fontSize: 11)),
        // 5. قلادة
        if (message.necklaceIconUrl != null && message.necklaceIconUrl!.isNotEmpty)
          _NecklaceIcon(url: message.necklaceIconUrl!),
      ],
    );
  }
}

// ── شارة الدور (مالك/مشرف) ──────────────────────────────────────────────────
class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});
  final AgencyMemberRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: role.badgeColor.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: role.badgeColor.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(role.badgeIcon, color: role.badgeColor, size: 10),
          const SizedBox(width: 3),
          DText(
            role.label,
            style: TextStyle(color: role.badgeColor, fontSize: 9, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

// ── شارة المستوى ─────────────────────────────────────────────────────────────
class _LevelChip extends StatelessWidget {
  const _LevelChip({required this.level});
  final int level;

  @override
  Widget build(BuildContext context) {
    final colors = level >= 50
        ? [const Color(0xFFFF6F00), const Color(0xFFFFB300)]
        : level >= 20
            ? [const Color(0xFF6A1B9A), const Color(0xFFAB47BC)]
            : [const Color(0xFF1565C0), const Color(0xFF42A5F5)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(6),
      ),
      child: DText('Lv.$level',
        style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w900)),
    );
  }
}

// ── أيقونة القلادة ───────────────────────────────────────────────────────────
class _NecklaceIcon extends StatelessWidget {
  const _NecklaceIcon({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20, height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white24, width: 0.8),
      ),
      clipBehavior: Clip.antiAlias,
      child: SmartImage(url: url, fit: BoxFit.cover),
    );
  }
}

// ── فقاعة نصية ───────────────────────────────────────────────────────────────
class _TextBubble extends StatelessWidget {
  const _TextBubble({required this.body});
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF12103A),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          topLeft: Radius.circular(16),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(color: _border, width: 0.6),
      ),
      child: DText(body,
        style: GoogleFonts.tajawal(color: _textMain, fontSize: 13),
        textDirection: TextDirection.rtl),
    );
  }
}

// ── فقاعة صورة ───────────────────────────────────────────────────────────────
class _ImageBubble extends StatelessWidget {
  const _ImageBubble({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => _FullImageViewer(url: url))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 220, height: 160,
          child: SmartImage(url: url, fit: BoxFit.cover),
        ),
      ),
    );
  }
}

// ── فقاعة صوت ────────────────────────────────────────────────────────────────
class _AudioBubble extends StatefulWidget {
  const _AudioBubble({required this.url, required this.durationSecs});
  final String url;
  final int    durationSecs;

  @override
  State<_AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<_AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((pos) {
      if (!mounted) return;
      final total = widget.durationSecs * 1000;
      setState(() => _progress = total > 0 ? pos.inMilliseconds / total : 0);
    });
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        setState(() { _playing = false; _progress = 0; });
      }
    });
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
    } else {
      if (_player.processingState == ProcessingState.idle ||
          _player.processingState == ProcessingState.completed) {
        await _player.setUrl(widget.url);
      }
      try {
        await _player.play();
      } catch (_) {}
      setState(() => _playing = true);
    }
  }

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF12103A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border, width: 0.6),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          GestureDetector(
            onTap: _toggle,
            child: Container(
              width: 36, height: 36,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(colors: [_purple, _cyan]),
              ),
              child: Icon(_playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: _progress.clamp(0.0, 1.0),
                  backgroundColor: _border,
                  color: _purple,
                  minHeight: 3,
                ),
                const SizedBox(height: 4),
                DText(_fmt(widget.durationSecs),
                  style: const TextStyle(color: _textMuted, fontSize: 10)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          const Icon(Icons.mic_rounded, color: _textMuted, size: 16),
        ],
      ),
    );
  }
}

// ── فقاعة view-once ───────────────────────────────────────────────────────────
class _ViewOnceBubble extends StatelessWidget {
  const _ViewOnceBubble({required this.message, required this.onOpen});
  final AgencyChatMessage message;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final viewed = message.viewedByMe;

    IconData icon;
    String   label;
    Color    color;

    if (viewed) {
      icon  = Icons.check_circle_rounded;
      label = 'تمت المشاهدة';
      color = _textMuted;
    } else if (message.isText) {
      icon  = Icons.lock_rounded;
      label = 'رسالة لمرة واحدة — اضغط للقراءة';
      color = _purple;
    } else if (message.isImage) {
      icon  = Icons.image_rounded;
      label = 'صورة لمرة واحدة — اضغط للعرض';
      color = _cyan;
    } else {
      icon  = Icons.mic_rounded;
      label = 'صوت لمرة واحدة — اضغط للاستماع';
      color = _gold;
    }

    return GestureDetector(
      onTap: viewed ? null : onOpen,
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF12103A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: DText(label,
                style: GoogleFonts.tajawal(color: viewed ? _textMuted : color, fontSize: 12),
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// عارض view-once (full-screen + عداد تنازلي)
// ═════════════════════════════════════════════════════════════════════════════
class _ViewOnceViewer extends StatefulWidget {
  const _ViewOnceViewer({
    required this.messageType,
    this.body,
    this.assetUrl,
    required this.durationSecs,
  });
  final AgencyChatMessageType messageType;
  final String? body;
  final String? assetUrl;
  final int durationSecs;

  @override
  State<_ViewOnceViewer> createState() => _ViewOnceViewerState();
}

class _ViewOnceViewerState extends State<_ViewOnceViewer> {
  late int _remaining;
  Timer? _timer;
  AudioPlayer? _audioPlayer;

  @override
  void initState() {
    super.initState();
    _remaining = widget.durationSecs;

    if (widget.messageType == AgencyChatMessageType.audio && widget.assetUrl != null) {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.setUrl(widget.assetUrl!).then((_) {
        if (mounted) _audioPlayer?.play().catchError((_) {});
      }).catchError((Object e) {
        debugPrint('[agency_chat_screen] audioPlayer setUrl error: $e');
      });
      _audioPlayer!.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed && mounted) {
          Navigator.pop(context);
        }
      });
    } else {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _remaining--);
        if (_remaining <= 0) Navigator.pop(context);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _audioPlayer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (widget.messageType != AgencyChatMessageType.audio)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _red.withValues(alpha: 0.5)),
                  ),
                  child: DText('$_remaining ث',
                    style: GoogleFonts.tajawal(color: _red, fontSize: 14, fontWeight: FontWeight.w800)),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: widget.messageType == AgencyChatMessageType.text
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: DText(widget.body ?? '',
                    style: GoogleFonts.tajawal(color: Colors.white, fontSize: 22),
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.center),
                )
              : widget.messageType == AgencyChatMessageType.image && widget.assetUrl != null
                  ? InteractiveViewer(child: SmartImage(url: widget.assetUrl!, fit: BoxFit.contain))
                  : widget.messageType == AgencyChatMessageType.audio
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.graphic_eq_rounded, color: _purple, size: 80),
                            const SizedBox(height: 16),
                            DText('جارٍ التشغيل...',
                              style: GoogleFonts.tajawal(color: Colors.white, fontSize: 16)),
                          ],
                        )
                      : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// عارض صورة كاملة
// ═════════════════════════════════════════════════════════════════════════════
class _FullImageViewer extends StatelessWidget {
  const _FullImageViewer({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: InteractiveViewer(child: SmartImage(url: url, fit: BoxFit.contain)),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// شريط الإدخال
// ═════════════════════════════════════════════════════════════════════════════
class _AgencyChatInputBar extends StatelessWidget {
  const _AgencyChatInputBar({
    required this.controller,
    required this.isMuted,
    required this.mutedUntil,
    required this.sending,
    required this.isRecording,
    required this.recordSeconds,
    required this.isViewOnceMode,
    required this.viewOnceDuration,
    required this.onSend,
    required this.onPickImage,
    required this.onRecordStart,
    required this.onRecordStop,
    required this.onRecordCancel,
    required this.onToggleViewOnce,
    required this.onPickDuration,
  });

  final TextEditingController controller;
  final bool isMuted;
  final DateTime? mutedUntil;
  final bool sending;
  final bool isRecording;
  final int  recordSeconds;
  final bool isViewOnceMode;
  final int  viewOnceDuration;
  final VoidCallback onSend;
  final VoidCallback onPickImage;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordStop;
  final VoidCallback onRecordCancel;
  final VoidCallback onToggleViewOnce;
  final VoidCallback onPickDuration;

  String _fmt(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  }

  @override
  Widget build(BuildContext context) {
    // إذا مكتوم
    if (isMuted && mutedUntil != null) {
      final until = mutedUntil!;
      final diff  = until.difference(DateTime.now());
      final hh    = diff.inHours;
      final mm    = diff.inMinutes % 60;
      return Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF0A0820),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.mic_off_rounded, color: _red, size: 18),
            const SizedBox(width: 8),
            DText(
              'أنت مكتوم لمدة ${hh}س ${mm}د',
              style: GoogleFonts.tajawal(color: _red, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // شريط التسجيل
    if (isRecording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: const Color(0xFF0A0820),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            // إلغاء
            GestureDetector(
              onTap: onRecordCancel,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _red.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.delete_outline_rounded, color: _red, size: 18),
                    const SizedBox(width: 4),
                    DText('إلغاء', style: GoogleFonts.tajawal(color: _red, fontSize: 12)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            // مؤشر التسجيل
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fiber_manual_record_rounded, color: _red, size: 12),
                  const SizedBox(width: 6),
                  DText('تسجيل  ${_fmt(recordSeconds)}',
                    style: GoogleFonts.tajawal(color: _textMain, fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // إرسال
            GestureDetector(
              onTap: onRecordStop,
              child: Container(
                width: 44, height: 44,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(colors: [_purple, _cyan]),
                ),
                child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      );
    }

    // الشريط العادي
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF0A0820),
        border: Border(top: BorderSide(color: _border, width: 0.6)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // شريط view-once إذا مفعّل
          if (isViewOnceMode)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  const Icon(Icons.lock_rounded, color: _purple, size: 14),
                  const SizedBox(width: 4),
                  DText('لمرة واحدة — ', style: GoogleFonts.tajawal(color: _purple, fontSize: 11)),
                  GestureDetector(
                    onTap: onPickDuration,
                    child: DText(
                      viewOnceDuration < 60 ? '$viewOnceDuration ثانية' : '${viewOnceDuration ~/ 60} دقيقة',
                      style: GoogleFonts.tajawal(color: _gold, fontSize: 11,
                        decoration: TextDecoration.underline),
                    ),
                  ),
                ],
              ),
            ),

          Row(
            textDirection: TextDirection.rtl,
            children: [
              // زر إرسال / زر تسجيل صوت (التسجيل مُعطَّل مؤقتاً)
              sending
                  ? const SizedBox(
                      width: 44, height: 44,
                      child: Center(child: CircularProgressIndicator(color: _purple, strokeWidth: 2)))
                  : ValueListenableBuilder(
                      valueListenable: controller,
                      builder: (_, val, __) {
                        final isEmpty = val.text.trim().isEmpty;
                        return Tooltip(
                          message: isEmpty ? 'التسجيل الصوتي قادم في التحديث القادم' : '',
                          child: GestureDetector(
                            onTap: isEmpty ? onRecordStart : onSend,
                            child: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: isEmpty
                                    ? const LinearGradient(
                                        colors: [Color(0xFF777777), Color(0xFF999999)],
                                      )
                                    : const LinearGradient(colors: [_purple, _cyan]),
                              ),
                              child: Icon(
                                isEmpty ? Icons.mic_off_rounded : Icons.send_rounded,
                                color: Colors.white, size: 22,
                              ),
                            ),
                          ),
                        );
                      },
                    ),

              const SizedBox(width: 6),

              // حقل النص
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF120F2E),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _border, width: 0.6),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textDirection: TextDirection.rtl,
                          maxLines: 4,
                          minLines: 1,
                          style: GoogleFonts.tajawal(color: _textMain, fontSize: 14),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: 'اكتب رسالة...',
                            hintStyle: GoogleFonts.tajawal(color: _textMuted, fontSize: 13),
                          ),
                          onSubmitted: (_) => onSend(),
                        ),
                      ),
                      // زر الصورة
                      IconButton(
                        onPressed: onPickImage,
                        icon: const Icon(Icons.image_rounded, color: _textMuted, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // زر view-once toggle
              GestureDetector(
                onTap: onToggleViewOnce,
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isViewOnceMode
                        ? _purple.withValues(alpha: 0.25)
                        : Colors.transparent,
                    border: Border.all(
                      color: isViewOnceMode ? _purple : _border, width: 1),
                  ),
                  child: Icon(Icons.lock_rounded,
                    color: isViewOnceMode ? _purple : _textMuted, size: 18),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// BottomSheet كتم العضو
// ═════════════════════════════════════════════════════════════════════════════
class _MuteSheet extends StatelessWidget {
  const _MuteSheet({required this.displayName, required this.onMute});
  final String displayName;
  final void Function(int hours) onMute;

  @override
  Widget build(BuildContext context) {
    final options = [
      (1,  'كتم ساعة واحدة'),
      (6,  'كتم 6 ساعات'),
      (24, 'كتم يوم كامل'),
      (72, 'كتم 3 أيام'),
      (168,'كتم أسبوع'),
      (0,  'رفع الكتم'),
    ];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DText('$displayName — إدارة الكتم',
            style: GoogleFonts.tajawal(color: _textMain, fontSize: 15, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ...options.map((o) => ListTile(
            leading: Icon(
              o.$1 == 0 ? Icons.mic_rounded : Icons.mic_off_rounded,
              color: o.$1 == 0 ? _cyan : _red, size: 20,
            ),
            title: DText(o.$2,
              style: GoogleFonts.tajawal(color: _textMain, fontSize: 13)),
            onTap: () => onMute(o.$1),
          )),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
