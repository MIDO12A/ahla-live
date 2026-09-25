import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../config/r.dart';
import '../../config/app_colors.dart';
import '../../services/supabase_service.dart';
import '../../models/user_model.dart';

// layout_room_admins_blacks.xml
class RoomAdminsScreen extends StatefulWidget {
  final String roomId;

  const RoomAdminsScreen({super.key, required this.roomId});

  @override
  State<RoomAdminsScreen> createState() => _RoomAdminsScreenState();
}

class _RoomAdminsScreenState extends State<RoomAdminsScreen> {
  final SupabaseService _firebaseService = SupabaseService();
  List<String> _moderatorUids = [];
  final Map<String, UserModel> _adminProfiles = {};
  bool _isLoading = true;
  StreamSubscription? _roomSub;

  @override
  void initState() {
    super.initState();
    _listenToModerators();
  }

  void _listenToModerators() {
    _roomSub = FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
        .collection('rooms')
        .doc(widget.roomId)
        .snapshots()
        .listen((snap) async {
      if (!mounted) return;
      if (!snap.exists) {
        setState(() => _isLoading = false);
        return;
      }
      final data = snap.data() ?? {};
      final mods = (data['moderators'] as List?)?.map((e) => e.toString()).toList() ?? [];
      
      setState(() {
        _moderatorUids = mods;
        _isLoading = false;
      });

      // Load profile info for newly found admins
      for (final uid in mods) {
        if (!_adminProfiles.containsKey(uid)) {
          final u = await _firebaseService.getUser(uid);
          if (u != null && mounted) {
            setState(() {
              _adminProfiles[uid] = u;
            });
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    super.dispose();
  }

  Future<void> _removeAdmin(String uid, String name) async {
    try {
      await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('rooms').doc(widget.roomId).update({
        'moderators': FieldValue.arrayRemove([uid]),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم إزالة $name من المشرفين')),
        );
      }
    } catch (e) {
      debugPrint('removeAdmin error: $e');
    }
  }

  void _showAddAdminDialog() {
    final idCtrl = TextEditingController();
    bool isSearching = false;
    String? errorText;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: const Color(0xFF211211),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'إضافة مشرف للغرفة',
            style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'أدخل المعرف (ID) الخاص بالمستخدم لتعيينه مشرفاً في الغرفة:',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0x1AFFFFFF),
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: TextField(
                  controller: idCtrl,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'معرف المستخدم (ID)',
                    hintStyle: TextStyle(color: Colors.white38),
                    border: InputBorder.none,
                  ),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(errorText!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldLight,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: isSearching
                  ? null
                  : () async {
                      final input = idCtrl.text.trim();
                      if (input.isEmpty) return;
                      setDlgState(() {
                        isSearching = true;
                        errorText = null;
                      });
                      try {
                        // Search by custom_id or uid
                        final userSnap = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default')
                            .collection('users')
                            .where('custom_id', isEqualTo: input)
                            .limit(1)
                            .get();
                        String? targetUid;
                        String? targetName;
                        if (userSnap.docs.isNotEmpty) {
                          targetUid = userSnap.docs.first.id;
                          targetName = userSnap.docs.first.data()['name']?.toString() ?? 'User';
                        } else {
                          // Try doc id
                          final doc = await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('users').doc(input).get();
                          if (doc.exists) {
                            targetUid = doc.id;
                            targetName = doc.data()?['name']?.toString() ?? 'User';
                          }
                        }

                        if (targetUid == null) {
                          setDlgState(() {
                            isSearching = false;
                            errorText = 'المستخدم غير موجود';
                          });
                          return;
                        }

                        if (_moderatorUids.contains(targetUid)) {
                          setDlgState(() {
                            isSearching = false;
                            errorText = 'هذا المستخدم مشرف بالفعل';
                          });
                          return;
                        }

                        await FirebaseFirestore.instanceFor(app: Firebase.app(), databaseId: 'default').collection('rooms').doc(widget.roomId).update({
                          'moderators': FieldValue.arrayUnion([targetUid]),
                        });

                        Navigator.pop(ctx);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تم تعيين $targetName مشرفاً في الغرفة 👑')),
                          );
                        }
                      } catch (e) {
                        setDlgState(() {
                          isSearching = false;
                          errorText = 'حدث خطأ أثناء الإضافة';
                        });
                      }
                    },
              child: isSearching
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('تعيين', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final navH = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFF16151A),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.goldLight))
                  : _moderatorUids.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          itemCount: _moderatorUids.length,
                          separatorBuilder: (_, __) => Container(height: 0.5, color: const Color(0x1AFFFFFF)),
                          itemBuilder: (_, i) {
                            final uid = _moderatorUids[i];
                            final profile = _adminProfiles[uid];
                            return _buildAdminItem(context, uid, profile);
                          },
                        ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, navH + 16),
              child: GestureDetector(
                onTap: _showAddAdminDialog,
                child: Container(
                  width: double.infinity,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: AppColors.giftBtnGradient,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'إضافة مشرف',
                    style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
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
          Text(
            'مدراء الغرفة (${_moderatorUids.length})',
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
          const Text(
            'لا يوجد مدراء معينين في هذه الغرفة',
            style: TextStyle(fontSize: 15, color: Colors.white54),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminItem(BuildContext context, String uid, UserModel? profile) {
    final nickname = profile?.name ?? 'Admin';
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
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        nickname,
                        style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        gradient: AppColors.giftBtnGradient,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text('مدير', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text('ID: $customId', style: const TextStyle(fontSize: 12, color: Colors.white54)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _removeAdmin(uid, nickname),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.accentRed.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('إزالة', style: TextStyle(fontSize: 12, color: AppColors.muteRed, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
