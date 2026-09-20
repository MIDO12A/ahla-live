import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/r.dart';
import '../../config/app_colors.dart';
import '../../services/cloudinary_service.dart';
import '../../services/supabase_service.dart';
import '../../services/dynamic_config_service.dart';
import 'room_admins_screen.dart';
import 'blacklist_screen.dart';
import 'reports_admin_screen.dart';
import 'widgets/room_background_bottom_sheet.dart';

// ═══════════════════════════════════════════════════════════════════
// RoomSettingsScreen — activity_room_set.xml
//
// ─ Header background image (room_create_room_bg)
// ─ Title icon (room_create_label_ic) + "Room Settings"
// ─ Room image 108×108 + camera icon overlay (room_camera_logo_ic)
// ─ Room name EditText (max 20)
// ─ Topic EditText (multiline, 92dp, max 100)
// ─ Room lock + password field (6 digits)
// ─ Admin row (next_2_ic)
// ─ Blacklist row (ic_go_jiantou)
// ─ Confirm button (50dp, margin 16h/12b)
// ═══════════════════════════════════════════════════════════════════

class RoomSettingsScreen extends StatefulWidget {
  final String roomId;
  final String initialName;
  final String initialPassword;
  final String? initialTopic;
  final String? roomAvatarPath;
  final List<Map<String, dynamic>> admins;
  final void Function(String name, String password, String? photoUrl, String? topic)? onConfirm;
  final bool isModerator;

  const RoomSettingsScreen({
    super.key,
    required this.roomId,
    this.initialName = '',
    this.initialPassword = '',
    this.initialTopic,
    this.roomAvatarPath,
    this.admins = const [],
    this.onConfirm,
    this.isModerator = false,
  });

  @override
  State<RoomSettingsScreen> createState() => _RoomSettingsScreenState();
}

class _RoomSettingsScreenState extends State<RoomSettingsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _topicCtrl;
  bool _isLocked = false;
  String? _roomAvatar;
  int _adminCount = 0;
  int _blacklistCount = 0;
  final SupabaseService _firebaseService = SupabaseService();
  StreamSubscription? _roomSub;
  StreamSubscription? _blacklistSub;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
    _pwdCtrl = TextEditingController(text: widget.initialPassword);
    _topicCtrl = TextEditingController(text: widget.initialTopic ?? '');
    _isLocked = widget.initialPassword.isNotEmpty;
    _roomAvatar = widget.roomAvatarPath;
    _adminCount = widget.admins.length;
    _listenData();
  }

  void _listenData() {
    _roomSub = _firebaseService.roomStream(widget.roomId).listen((room) {
      if (!mounted || room == null) return;
      setState(() {
        _adminCount = room.moderators.length;
        if (_topicCtrl.text.isEmpty && room.announcement.isNotEmpty) {
          _topicCtrl.text = room.announcement;
        }
        if (_roomAvatar == null && room.roomPhotoUrl.isNotEmpty) {
          _roomAvatar = room.roomPhotoUrl;
        }
      });
    });

    _blacklistSub = _firebaseService.roomBlocksStream(widget.roomId).listen((list) {
      if (!mounted) return;
      setState(() {
        _blacklistCount = list.length;
      });
    });
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _blacklistSub?.cancel();
    _nameCtrl.dispose();
    _pwdCtrl.dispose();
    _topicCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final cfg = DynamicConfigService();
    final navH = MediaQuery.of(context).padding.bottom;
    final statusH = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Column(
        children: [
          // ── Header with background image ───────────────────────
          SizedBox(
            height: statusH + 100,
            child: Stack(
              children: [
                R.loadAssetOr(
                  cfg.roomSettingsHeaderBg,
                  R.roomCreateRoomBg,
                  width: double.infinity,
                  height: double.infinity,
                  fit: BoxFit.fill,
                ),
                Positioned(
                  top: statusH,
                  left: 0,
                  right: 0,
                  child: _buildAppBar(context, isAr, cfg),
                ),
              ],
            ),
          ),

          // ── Scrollable content ──────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 16),

                  // ── Room image ─────────────────────────────────
                  _buildRoomImage(cfg),
                  const SizedBox(height: 24),

                  // ── Room name ──────────────────────────────────
                  _buildSectionLabel(isAr ? 'اسم الغرفة' : 'Room Name'),
                  const SizedBox(height: 8),
                  _buildNameField(isAr),
                  const SizedBox(height: 24),

                  // ── Topic ──────────────────────────────────────
                  _buildSectionLabel(isAr ? 'الموضوع' : 'Topic'),
                  const SizedBox(height: 8),
                  _buildTopicField(isAr),
                  const SizedBox(height: 24),

                  // ── Room lock (owner only) ─────────────────────
                  if (!widget.isModerator) ...[
                    _buildSectionLabel(isAr ? 'قفل الغرفة' : 'Lock Room'),
                    const SizedBox(height: 8),
                    _buildLockRow(isAr),
                    const SizedBox(height: 24),
                  ],

                  // ── Room Background (owner only) ───────────────
                  if (!widget.isModerator) ...[
                    _buildListRow(
                      icon: R.icGoJiantou,
                      label: isAr ? 'خلفية الغرفة' : 'Room Background',
                      count: 0,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => RoomBackgroundBottomSheet(
                            roomId: widget.roomId,
                            currentBackground: '',
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Admin (owner only) ─────────────────────────
                  if (!widget.isModerator) ...[
                    _buildListRow(
                      icon: R.next2Ic,
                      label: isAr ? 'المشرفين' : 'Admin',
                      count: _adminCount,
                      onTap: () => _showAdminSheet(context),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Blacklist (owner only) ─────────────────────
                  if (!widget.isModerator) ...[
                    _buildListRow(
                      icon: R.icGoJiantou,
                      label: isAr ? 'قائمة الحظر' : 'Blacklist',
                      count: _blacklistCount,
                      onTap: () => _showBlacklistSheet(context),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // ── Reports ─────────────────────────────────────
                  _buildListRow(
                    icon: R.icGoJiantou,
                    label: isAr ? 'البلاغات' : 'Reports',
                    count: 0,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReportsAdminScreen()),
                      );
                    },
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),

          // ── Confirm button ─────────────────────────────────────
          Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, navH + 12),
            child: GestureDetector(
              onTap: () {
                final name = _nameCtrl.text.trim();
                final pwd = _isLocked ? _pwdCtrl.text.trim() : '';
                final topic = _topicCtrl.text.trim();
                widget.onConfirm?.call(name, pwd, _roomAvatar, topic);
                Navigator.pop(context);
              },
              child: Container(
                width: double.infinity,
                height: 50,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      cfg.roomSettingsConfirmBtnStart,
                      cfg.roomSettingsConfirmBtnEnd,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: cfg.roomSettingsConfirmBtnEnd.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  isAr ? 'تأكيد' : 'Confirm',
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFFFFFFFF),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(BuildContext context, bool isAr, DynamicConfigService cfg) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: R.image(
              R.backIc,
              width: 28,
              height: 28,
            ),
          ),
          const SizedBox(width: 8),
          R.loadAssetOr(
            cfg.roomSettingsLabelIcon,
            R.roomCreateLabelIc,
            width: 20,
            height: 20,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              isAr ? 'إعدادات الغرفة' : 'Room Settings',
              style: const TextStyle(
                fontSize: 22,
                color: Color(0xFF16151A),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Section label ───────────────────────────────────────────────
  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF16151A),
      ),
    );
  }

  // ── Room image: 108×108 circle + camera icon ────────────────────
  Widget _buildRoomImage(DynamicConfigService cfg) {
    return GestureDetector(
      onTap: _pickRoomImage,
      child: Center(
        child: SizedBox(
          width: 108,
          height: 108,
          child: Stack(
            children: [
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFFC525),
                    width: 0,
                  ),
                  color: const Color(0xFF1A0F0F),
                ),
                child: ClipOval(
                  child: _roomAvatar != null
                      ? (_roomAvatar!.startsWith('http')
                          ? Image(
                              image: R.cachedImage(_roomAvatar!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                            )
                          : Image.asset(
                              _roomAvatar!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                            ))
                      : _avatarPlaceholder(),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 0,
                child: R.loadAssetOr(
                  cfg.roomSettingsCameraIcon,
                  R.roomCameraLogoIc,
                  width: 30,
                  height: 30,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatarPlaceholder() => Container(
    color: const Color(0xFF1A0F0F),
    child: const Icon(Icons.image_outlined, color: Colors.white54, size: 40),
  );

  Future<void> _pickRoomImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (image == null) return;
    try {
      final url = await CloudinaryService().uploadImage(File(image.path));
      if (mounted) setState(() => _roomAvatar = url);
    } catch (e) {
      debugPrint('Error uploading room image: $e');
    }
  }

  // ── Room name field ─────────────────────────────────────────────
  Widget _buildNameField(bool isAr) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FB),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      constraints: const BoxConstraints(minHeight: 49),
      child: TextField(
        controller: _nameCtrl,
        style: const TextStyle(fontSize: 13, color: Color(0xFF16151A)),
        maxLength: 20,
        decoration: InputDecoration(
          hintText: isAr ? 'أدخل اسم الغرفة' : 'Enter room name',
          hintStyle: const TextStyle(color: Color(0xFF9BA1B6)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          isDense: true,
          counterText: '',
        ),
      ),
    );
  }

  // ── Topic field (multiline, 92dp, max 100) ──────────────────────
  Widget _buildTopicField(bool isAr) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FB),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      height: 92,
      child: TextField(
        controller: _topicCtrl,
        style: const TextStyle(fontSize: 13, color: Color(0xFF16151A)),
        maxLength: 100,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        expands: true,
        decoration: InputDecoration(
          hintText: isAr ? 'أدخل موضوع أو إعلان الغرفة' : 'Enter topic description',
          hintStyle: const TextStyle(color: Color(0xFF9BA1B6)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(top: 12, bottom: 32),
          isDense: true,
          counterText: '',
        ),
      ),
    );
  }

  // ── Lock switch row ─────────────────────────────────────────────
  Widget _buildLockRow(bool isAr) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FB),
        borderRadius: BorderRadius.all(Radius.circular(4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      constraints: const BoxConstraints(minHeight: 50),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _pwdCtrl,
              enabled: _isLocked,
              style: const TextStyle(fontSize: 13, color: Color(0xFF16151A)),
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: isAr ? 'تعيين كلمة مرور الغرفة (6 أرقام)' : 'Set room password',
                hintStyle: const TextStyle(color: Color(0xFF9BA1B6)),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                isDense: true,
                counterText: '',
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() {
              _isLocked = !_isLocked;
              if (!_isLocked) _pwdCtrl.clear();
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 47,
              height: 29,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14.5),
                color: _isLocked
                    ? const Color(0xFFFFC525)
                    : const Color(0x33000000),
              ),
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 200),
                    left: _isLocked ? 22 : 2,
                    top: 2,
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── List row (Admin / Blacklist) ────────────────────────────────
  Widget _buildListRow({
    required String icon,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 50),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF000000),
                ),
              ),
            ),
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFC525).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFFFC525),
                  ),
                ),
              ),
            const SizedBox(width: 8),
            R.image(
              icon,
              width: 20,
              height: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ── Admin sheet ─────────────────────────────────────────────────
  void _showAdminSheet(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoomAdminsScreen(roomId: widget.roomId)),
    );
  }

  // ── Blacklist sheet ─────────────────────────────────────────────
  void _showBlacklistSheet(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => BlacklistScreen(roomId: widget.roomId)),
    );
  }
}
