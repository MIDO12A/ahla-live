import 'dart:async';
import 'package:flutter/material.dart';
import '../../config/r.dart';
import '../../config/app_colors.dart';
import '../../services/supabase_service.dart';
import '../../models/user_model.dart';
import 'package:zero/core/dtext.dart';

class BlacklistScreen extends StatefulWidget {
  final String roomId;

  const BlacklistScreen({super.key, required this.roomId});

  @override
  State<BlacklistScreen> createState() => _BlacklistScreenState();
}

class _BlacklistScreenState extends State<BlacklistScreen> {
  final SupabaseService _firebaseService = SupabaseService();
  List<Map<String, dynamic>> _bannedUsers = [];
  final Map<String, UserModel> _userProfiles = {};
  bool _isLoading = true;
  StreamSubscription? _banSub;

  @override
  void initState() {
    super.initState();
    _listenToBannedUsers();
  }

  void _listenToBannedUsers() {
    _banSub = _firebaseService.roomBlocksStream(widget.roomId).listen((users) async {
      if (!mounted) return;
      setState(() {
        _bannedUsers = users;
        _isLoading = false;
      });

      // Load user profiles
      for (final ban in users) {
        final uid = ban['blocked_uid']?.toString() ?? '';
        if (uid.isNotEmpty && !_userProfiles.containsKey(uid)) {
          final u = await _firebaseService.getUser(uid);
          if (u != null && mounted) {
            setState(() {
              _userProfiles[uid] = u;
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _banSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16151A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.goldLight))
                  : _bannedUsers.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: _bannedUsers.length,
                          separatorBuilder: (_, __) => Container(height: 0.5, color: const Color(0x1AFFFFFF)),
                          itemBuilder: (_, i) => _buildBannedItem(context, _bannedUsers[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF16151A),
        border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF), width: 0.5)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: R.image(R.backIc, width: 24, height: 24),
            ),
          ),
          const Spacer(),
          DText(
            'القائمة السوداء (${_bannedUsers.length})',
            style: const TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.shield_outlined, color: Colors.white.withValues(alpha: 0.2), size: 64),
          const SizedBox(height: 16),
          const DText(
            'لا يوجد مستخدمين محظورين في هذه الغرفة',
            style: TextStyle(fontSize: 15, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildBannedItem(BuildContext context, Map<String, dynamic> ban) {
    final uid = ban['blocked_uid']?.toString() ?? '';
    final reason = ban['reason']?.toString() ?? 'مخالفة شروط الغرفة';
    final profile = _userProfiles[uid];
    final nickname = profile?.name ?? (uid.length >= 6 ? 'User_${uid.substring(0, 6)}' : uid);
    final avatar = profile?.photoUrl ?? '';
    final customId = profile?.customId ?? (uid.length >= 6 ? uid.substring(0, 6) : uid);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          ClipOval(
            child: SizedBox(
              width: 46,
              height: 46,
              child: avatar.isNotEmpty
                  ? Image(
                      image: R.cachedImage(avatar),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => R.image(R.avaBoy, fit: BoxFit.cover),
                    )
                  : R.image(R.avaBoy, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DText(nickname, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                DText('ID: $customId', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                const SizedBox(height: 2),
                DText(
                  'السبب: $reason',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              await _firebaseService.unblockUserFromRoom(widget.roomId, uid);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: DText('تم فك الحظر عن $nickname')),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.goldLight.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.goldLight.withValues(alpha: 0.5), width: 0.8),
              ),
              child: const DText('فك الحظر', style: TextStyle(fontSize: 12, color: AppColors.goldLight, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
