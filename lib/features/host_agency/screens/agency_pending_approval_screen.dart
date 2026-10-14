import 'package:flutter/material.dart';
import 'dart:async';
import 'package:provider/provider.dart';
import '../../../../core/supabase_compat.dart';
import '../../../../providers/user_provider.dart';
import '../../../../services/supabase_data_service.dart';
import '../../../../core/ui/in_app_toast.dart';
import '../host_agency_screen.dart';

/// شاشة انتظار موافقة الإدارة على فتح الوكالة
class AgencyPendingApprovalScreen extends StatefulWidget {
  final Map<String, dynamic>? applicationData;
  final String? agencyId;

  const AgencyPendingApprovalScreen({
    super.key,
    this.applicationData,
    this.agencyId,
  });

  @override
  State<AgencyPendingApprovalScreen> createState() => _AgencyPendingApprovalScreenState();
}

class _AgencyPendingApprovalScreenState extends State<AgencyPendingApprovalScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  bool _checking = false;
  Map<String, dynamic>? _currentData;
  String _status = 'pending';
  String? _rejectionReason;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _currentData = widget.applicationData;
    _status = _currentData?['status']?.toString() ?? 'pending';
    _rejectionReason = _currentData?['rejection_reason']?.toString();
    _checkStatus(silent: true);
    _startRealtimeCheck();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  void _startRealtimeCheck() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (mounted) _checkStatus(silent: true);
    });
  }

  Future<void> _checkStatus({bool silent = false}) async {
    if (!silent) {
      setState(() => _checking = true);
    }

    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final uid = user?.uid;
      if (uid == null || uid.isEmpty) {
        if (!silent && mounted) setState(() => _checking = false);
        return;
      }

      // 1. Check Supabase agency_applications
      Map<String, dynamic>? freshApp;
      try {
        final rows = await Supabase.instance.client
            .from('agency_applications')
            .select('*')
            .eq('user_id', uid)
            .order('created_at', ascending: false)
            .limit(1);
        if (rows.isNotEmpty) {
          freshApp = Map<String, dynamic>.from(rows.first as Map);
        }
      } catch (_) {}



      // 3. Also check if host_agencies is directly active for this owner
      bool isDirectlyActive = false;
      try {
        final ag = await Supabase.instance.client
            .from('host_agencies')
            .select('id, status, is_active')
            .eq('owner_uid', uid)
            .maybeSingle();
        if (ag != null && (ag['status'] == 'active' || ag['is_active'] == true)) {
          isDirectlyActive = true;
        }
      } catch (_) {}

      if (mounted) {
        final newStatus = isDirectlyActive ? 'approved' : (freshApp?['status']?.toString() ?? _status);
        setState(() {
          if (freshApp != null) _currentData = freshApp;
          _status = newStatus;
          _rejectionReason = freshApp?['rejection_reason']?.toString() ?? _rejectionReason;
          _checking = false;
        });

        if (newStatus == 'approved') {
          _onApproved();
        } else if (!silent) {
          if (newStatus == 'rejected') {
            KayanInAppToast.warning('تم رفض طلب فتح الوكالة. يرجى مراجعة السبب أدناه.');
          } else {
            KayanInAppToast.agency('طلبك قيد المراجعة حالياً من قِبل إدارة التطبيق ⏳');
          }
        }
      }
    } catch (e) {
      if (mounted && !silent) {
        setState(() => _checking = false);
        KayanInAppToast.warning('تعذر تحديث الحالة حالياً: $e');
      }
    }
  }

  void _onApproved() {
    KayanInAppToast.agency('مبروك! تمت الموافقة على فتح وكالتك رسمياً! 🎉');
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HostAgencyScreen()),
      (route) => route.isFirst,
    );
  }

  Future<void> _cancelApplication() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF232328),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('إلغاء طلب فتح الوكالة', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: const Text(
          'هل أنت متأكد من رغبتك في إلغاء طلب فتح الوكالة؟ ستتمكن من التقديم مرة أخرى لاحقاً.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('تأكيد الإلغاء', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final user = Provider.of<UserProvider>(context, listen: false).currentUser;
      final uid = user?.uid ?? '';

      // Delete from Supabase
      try {
        await Supabase.instance.client.from('agency_applications').delete().eq('user_id', uid);
        await Supabase.instance.client.from('host_agencies').delete().eq('owner_uid', uid).eq('status', 'pending');
      } catch (_) {}



      if (mounted) {
        KayanInAppToast.agency('تم إلغاء الطلب بنجاح');
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HostAgencyScreen()),
        );
      }
    } catch (e) {
      if (mounted) KayanInAppToast.warning('تعذر إلغاء الطلب: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final agencyName = _currentData?['agency_name']?.toString() ?? 'وكالتي الرسمية';
    final agencyLogo = _currentData?['agency_logo']?.toString() ?? _currentData?['photo_url']?.toString() ?? '';
    final supervisorName = _currentData?['supervisor_name']?.toString() ?? 'مشرف معتمد';
    final supervisorId = _currentData?['supervisor_id']?.toString() ?? _currentData?['supervisor_custom_id']?.toString() ?? '';
    final country = _currentData?['country']?.toString() ?? 'عالمي';
    final whatsapp = _currentData?['whatsapp']?.toString() ?? '';
    final createdAtRaw = _currentData?['created_at']?.toString() ?? '';
    String createdFormatted = '';
    if (createdAtRaw.isNotEmpty) {
      final dt = DateTime.tryParse(createdAtRaw);
      if (dt != null) {
        createdFormatted = '${dt.year}/${dt.month}/${dt.day} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }

    final isRejected = _status == 'rejected';

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF141416),
        appBar: AppBar(
          backgroundColor: const Color(0xFF141416),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            isRejected ? (isAr ? 'حالة طلب الوكالة' : 'Application Status') : (isAr ? 'انتظار موافقة الإدارة' : 'Pending Approval'),
            style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            children: [
              const SizedBox(height: 10),

              // ── Pulse Status Icon Header ──
              Center(
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (ctx, child) {
                    final scale = isRejected ? 1.0 : (1.0 + (_pulseController.value * 0.06));
                    return Transform.scale(
                      scale: scale,
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: isRejected
                                ? [const Color(0xFFFF5252), const Color(0xFFB71C1C)]
                                : [const Color(0xFFFFD700), const Color(0xFFFF9800)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (isRejected ? const Color(0xFFFF5252) : const Color(0xFFFFD700)).withOpacity(0.35),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(
                          isRejected ? Icons.highlight_off_rounded : Icons.hourglass_top_rounded,
                          size: 48,
                          color: Colors.black,
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // ── Main Status Title ──
              Text(
                isRejected
                    ? (isAr ? 'تم رفض طلب فتح الوكالة' : 'Application Rejected')
                    : (isAr ? 'طلب فتح الوكالة قيد مراجعة الإدارة ⏳' : 'Agency Application Under Review ⏳'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isRejected ? const Color(0xFFFF5252) : const Color(0xFFFFD700),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 8),

              Text(
                isRejected
                    ? (isAr ? 'نعتذر، لم تستوفِ الوكالة متطلبات الاعتماد الحالية.' : 'Agency application did not meet approval requirements.')
                    : (isAr ? 'تم استلام طلبك بنجاح وهو بانتظار مراجعة وقبول الإدارة من لوحة التحكم.' : 'Your application was received and is awaiting approval from the dashboard.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
              ),

              const SizedBox(height: 24),

              // ── Agency Info Card ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E24),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: isRejected ? const Color(0x33FF5252) : const Color(0x33FFD700),
                  ),
                ),
                child: Column(
                  children: [
                    // Agency Avatar & Name
                    Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            width: 60,
                            height: 60,
                            color: Colors.white12,
                            child: agencyLogo.isNotEmpty
                                ? Image.network(
                                    agencyLogo,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.shield, color: Color(0xFFFFD700), size: 30),
                                  )
                                : const Icon(Icons.shield, color: Color(0xFFFFD700), size: 30),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                agencyName,
                                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isRejected ? const Color(0x22FF5252) : const Color(0x22FFD700),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isRejected ? (isAr ? 'مرفوض' : 'Rejected') : (isAr ? '⏳ قيد الانتظار' : 'Pending Review'),
                                  style: TextStyle(
                                    color: isRejected ? const Color(0xFFFF5252) : const Color(0xFFFFD700),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 10),

                    // Details Rows
                    _buildDetailRow(
                      icon: Icons.person_pin_rounded,
                      label: isAr ? 'المشرف التابع له' : 'Supervisor',
                      value: supervisorId.isNotEmpty ? '$supervisorName (#$supervisorId)' : supervisorName,
                    ),
                    const SizedBox(height: 10),
                    _buildDetailRow(
                      icon: Icons.public,
                      label: isAr ? 'الدولة' : 'Country',
                      value: country,
                    ),
                    if (whatsapp.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        icon: Icons.phone_android,
                        label: isAr ? 'رقم التواصل' : 'WhatsApp',
                        value: whatsapp,
                      ),
                    ],
                    if (createdFormatted.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _buildDetailRow(
                        icon: Icons.schedule,
                        label: isAr ? 'تاريخ التقديم' : 'Submitted at',
                        value: createdFormatted,
                      ),
                    ],

                    if (isRejected && _rejectionReason != null && _rejectionReason!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0x1AFF5252),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0x44FF5252)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.info_outline, color: Color(0xFFFF5252), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isAr ? 'سبب الرفض من الإدارة:' : 'Rejection Reason:',
                                    style: const TextStyle(color: Color(0xFFFF5252), fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    _rejectionReason!,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Informative Message Box ──
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF181C28),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF283A5E)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.security, color: Color(0xFF4FC3F7), size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        isAr
                            ? 'بمجرد اعتماد وقبول طلبك في لوحة التحكم، سيتم تفعيل الوكالة وتعيينك كمالك رسمي لها فوراً مع فتح إدارة المضيفين والأرباح.'
                            : 'Once approved by the admin dashboard, your agency will be activated immediately with full owner privileges.',
                        style: const TextStyle(color: Color(0xFFB0BEC5), fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 30),

              // ── Action Buttons ──
              // 1. Refresh Status Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : () => _checkStatus(silent: false),
                  icon: _checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.5))
                      : const Icon(Icons.refresh_rounded, color: Colors.black, size: 22),
                  label: Text(
                    _checking ? (isAr ? 'جاري الفحص...' : 'Checking...') : (isAr ? 'فحص وتحديث الحالة الآن 🔄' : 'Check Status Now 🔄'),
                    style: const TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFD700),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 3,
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // 2. Re-apply / Cancel Button
              if (isRejected) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: OutlinedButton.icon(
                    onPressed: _cancelApplication,
                    icon: const Icon(Icons.replay, color: Color(0xFFFFD700), size: 20),
                    label: Text(
                      isAr ? 'تقديم طلب جديد' : 'Reapply',
                      style: const TextStyle(color: Color(0xFFFFD700), fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0x66FFD700)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
              ] else ...[
                TextButton(
                  onPressed: _cancelApplication,
                  child: Text(
                    isAr ? 'إلغاء الطلب والتراجع' : 'Cancel Application',
                    style: const TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow({required IconData icon, required String label, required String value}) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFFFD700)),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
        const Spacer(),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
