import 'package:flutter/material.dart';
import '../models/seat_model.dart';

// ═══════════════════════════════════════════════════════════════════
// Seat action bottom sheets
//
// layout_seat_opretion_empty.xml   → showEmptySeatDialog
// layout_seat_opretion_hasuser.xml → showOccupiedSeatDialog
// ═══════════════════════════════════════════════════════════════════

class SeatDialogs {
  // ──────────────────────────────────────────────────────────────────
  // showEmptySeatDialog  — layout_seat_opretion_empty.xml
  //   idSeatActionTakeMic
  //   idSeatActionInviteSeat
  //   idSeatActionLockSeat
  //   idSeatActionMicStatus
  //   [separator 10dp]
  //   idSeatActionCancel
  // ──────────────────────────────────────────────────────────────────
  static Future<void> showEmptySeatDialog(
    BuildContext context, {
    required int seatIndex,
    required bool isOwnerOrModerator,
    required bool isLocked,
    required bool isMuted,
    VoidCallback? onTakeMic,
    VoidCallback? onInviteToMic,
    void Function(bool locked)? onToggleLock,
    void Function(bool muted)? onToggleMic,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmptySeatSheet(
        seatIndex: seatIndex,
        isOwnerOrModerator: isOwnerOrModerator,
        isLocked: isLocked,
        isMuted: isMuted,
        onTakeMic: onTakeMic,
        onInviteToMic: onInviteToMic,
        onToggleLock: onToggleLock,
        onToggleMic: onToggleMic,
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────
  // showOccupiedSeatDialog  — layout_seat_opretion_hasuser.xml
  //   idSeatActionUserDetail
  //   idSeatActionKickOffMic
  //   idSeatActionLockUnLockMic
  //   idSeatActionSetAdminOrRemove
  //   idSeatActionComments
  //   idSeatActionBlackOrUnBlackUser
  //   idSeatActionKickOutFromRoom
  //   [separator]
  //   Cancel
  // ──────────────────────────────────────────────────────────────────
  static Future<void> showOccupiedSeatDialog(
    BuildContext context, {
    required UserModel user,
    required bool isOwner,
    required bool isOwnerOrModerator,
    bool canKickAndMicDown = true,
    required bool isMuted,
    required bool isAdmin,
    required bool isBlacked,
    VoidCallback? onUserDetail,
    VoidCallback? onKickOffMic,
    void Function(bool muted)? onToggleMicLock,
    void Function(bool admin)? onSetAdmin,
    void Function(bool enabled)? onToggleComments,
    void Function(bool blacked)? onToggleBlack,
    VoidCallback? onKickOutFromRoom,
    VoidCallback? onPrivateMessage,
    VoidCallback? onGift,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _OccupiedSeatSheet(
        user: user,
        isOwner: isOwner,
        isOwnerOrModerator: isOwnerOrModerator,
        canKickAndMicDown: canKickAndMicDown,
        isMuted: isMuted,
        isAdmin: isAdmin,
        isBlacked: isBlacked,
        onUserDetail: onUserDetail,
        onKickOffMic: onKickOffMic,
        onToggleMicLock: onToggleMicLock,
        onSetAdmin: onSetAdmin,
        onToggleComments: onToggleComments,
        onToggleBlack: onToggleBlack,
        onKickOutFromRoom: onKickOutFromRoom,
        onPrivateMessage: onPrivateMessage,
        onGift: onGift,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Empty seat sheet
// ─────────────────────────────────────────────────────────────────
class _EmptySeatSheet extends StatelessWidget {
  final int seatIndex;
  final bool isOwnerOrModerator;
  final bool isLocked;
  final bool isMuted;
  final VoidCallback? onTakeMic;
  final VoidCallback? onInviteToMic;
  final void Function(bool locked)? onToggleLock;
  final void Function(bool muted)? onToggleMic;

  const _EmptySeatSheet({
    required this.seatIndex,
    required this.isOwnerOrModerator,
    required this.isLocked,
    required this.isMuted,
    this.onTakeMic,
    this.onInviteToMic,
    this.onToggleLock,
    this.onToggleMic,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // idPartA — Main Actions Card (shape_white_juxing1)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _DragHandle(),
                  // idSeatActionTakeMic
                  _SheetItem(
                    label: isAr ? 'صعود المايك' : 'Take Mic',
                    onTap: () {
                      Navigator.pop(context);
                      onTakeMic?.call();
                    },
                  ),
                  _Divider(),
                  // idSeatActionInviteSeat — owner/moderator only
                  if (isOwnerOrModerator) ...[
                    _SheetItem(
                      label: isAr ? 'دعوة للمايك' : 'Invite to Mic',
                      onTap: () {
                        Navigator.pop(context);
                        onInviteToMic?.call();
                      },
                    ),
                    _Divider(),
                    // idSeatActionLockSeat
                    _SheetItem(
                      label: isLocked
                          ? (isAr ? 'إلغاء قفل المقعد' : 'Unlock Seat')
                          : (isAr ? 'قفل المقعد' : 'Lock Seat'),
                      onTap: () {
                        Navigator.pop(context);
                        onToggleLock?.call(!isLocked);
                      },
                    ),
                    _Divider(),
                    // idSeatActionMicStatus
                    _SheetItem(
                      label: isMuted
                          ? (isAr ? 'إلغاء كتم المايك' : 'Unmute Mic')
                          : (isAr ? 'كتم المايك' : 'Mute Mic'),
                      onTap: () {
                        Navigator.pop(context);
                        onToggleMic?.call(!isMuted);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            // idSeatActionCancel — Separate floating card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _SheetItem(
                label: isAr ? 'إلغاء' : 'Cancel',
                color: const Color(0xFF666666),
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// Occupied seat sheet
// ─────────────────────────────────────────────────────────────────
class _OccupiedSeatSheet extends StatelessWidget {
  final UserModel user;
  final bool isOwner;
  final bool isOwnerOrModerator;
  final bool isMuted;
  final bool isAdmin;
  final bool isBlacked;
  final bool canKickAndMicDown;
  final VoidCallback? onUserDetail;
  final VoidCallback? onKickOffMic;
  final void Function(bool muted)? onToggleMicLock;
  final void Function(bool admin)? onSetAdmin;
  final void Function(bool enabled)? onToggleComments;
  final void Function(bool blacked)? onToggleBlack;
  final VoidCallback? onKickOutFromRoom;
  final VoidCallback? onPrivateMessage;
  final VoidCallback? onGift;

  const _OccupiedSeatSheet({
    required this.user,
    required this.isOwner,
    required this.isOwnerOrModerator,
    this.canKickAndMicDown = true,
    required this.isMuted,
    required this.isAdmin,
    required this.isBlacked,
    this.onUserDetail,
    this.onKickOffMic,
    this.onToggleMicLock,
    this.onSetAdmin,
    this.onToggleComments,
    this.onToggleBlack,
    this.onKickOutFromRoom,
    this.onPrivateMessage,
    this.onGift,
  });

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // idPartA — Main Actions Card (shape_white_juxing1)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DragHandle(),
                    // User name header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        user.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF16151A),
                        ),
                      ),
                    ),
                    _Divider(),
                    // idSeatActionUserDetail
                    _SheetItem(
                      label: isAr ? 'معلومات المستخدم' : 'User Detail',
                      onTap: () {
                        Navigator.pop(context);
                        onUserDetail?.call();
                      },
                    ),
                    _Divider(),
                    // Owner/moderator actions
                    if (isOwnerOrModerator) ...[
                      // idSeatActionKickOffMic
                      if (canKickAndMicDown) ...[
                        _SheetItem(
                          label: isAr ? 'إنزال من المايك' : 'Kick Off Mic',
                          onTap: () {
                            Navigator.pop(context);
                            onKickOffMic?.call();
                          },
                        ),
                        _Divider(),
                      ],
                      // idSeatActionLockUnLockMic
                      _SheetItem(
                        label: isMuted
                            ? (isAr ? 'إلغاء كتم المايك' : 'Unmute Mic')
                            : (isAr ? 'كتم المايك' : 'Mute Mic'),
                        onTap: () {
                          Navigator.pop(context);
                          onToggleMicLock?.call(!isMuted);
                        },
                      ),
                      _Divider(),
                      // idSeatActionKickOutFromRoom — owner/moderator
                      if (canKickAndMicDown) ...[
                        _SheetItem(
                          label: isAr ? 'طرد من الغرفة' : 'Kick Out From Room',
                          color: const Color(0xFFE82323),
                          onTap: () {
                            Navigator.pop(context);
                            onKickOutFromRoom?.call();
                          },
                        ),
                        _Divider(),
                      ],
                    ],
                    // Owner-only actions
                    if (isOwner) ...[
                      // idSeatActionSetAdminOrRemove
                      _SheetItem(
                        label: isAdmin
                            ? (isAr ? 'إلغاء تعيين مسؤول' : 'Remove Admin')
                            : (isAr ? 'تعيين كمسؤول' : 'Set as Admin'),
                        onTap: () {
                          Navigator.pop(context);
                          onSetAdmin?.call(!isAdmin);
                        },
                      ),
                      _Divider(),
                      // idSeatActionComments
                      _SheetItem(
                        label: isAr ? 'السماح بالتعليقات' : 'Allow Comments',
                        onTap: () {
                          Navigator.pop(context);
                          onToggleComments?.call(true);
                        },
                      ),
                      _Divider(),
                      // idSeatActionBlackOrUnBlackUser
                      _SheetItem(
                        label: isBlacked
                            ? (isAr ? 'إلغاء الحظر' : 'Unblack User')
                            : (isAr ? 'إضافة للقائمة السوداء' : 'Black User'),
                        color: isBlacked ? Colors.black87 : const Color(0xFFE82323),
                        onTap: () {
                          Navigator.pop(context);
                          onToggleBlack?.call(!isBlacked);
                        },
                      ),
                      _Divider(),
                    ],
                    if (!isOwnerOrModerator) ...[
                      // Regular user options: private message, gift
                      _SheetItem(
                        label: isAr ? 'رسالة خاصة' : 'Private Message',
                        onTap: () {
                          Navigator.pop(context);
                          onPrivateMessage?.call();
                        },
                      ),
                      _Divider(),
                      _SheetItem(
                        label: isAr ? 'إرسال هدية' : 'Send Gift',
                        onTap: () {
                          Navigator.pop(context);
                          onGift?.call();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            // idSeatActionCancel — Separate floating card
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: _SheetItem(
                label: isAr ? 'إلغاء' : 'Cancel',
                color: const Color(0xFF666666),
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared widgets ──────────────────────────────────────────────

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 4),
        width: 36,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0x1A000000),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _SheetItem extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _SheetItem({
    required this.label,
    this.color = Colors.black87,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(
            label,
            style: TextStyle(fontSize: 16, color: color),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(height: 0.6, color: const Color(0x1A000000));
  }
}
