// lib/features/host_agency/screens/agency_item_detail_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// 100% Match for union_activity_agency_item_detail.xml,
// union_adapter_agency_detail_header.xml & union_adapter_agency_detail_item.xml
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../config/r.dart';
import '../../../../services/dynamic_config_service.dart';
import 'package:provider/provider.dart';

class AgencyItemDetailScreen extends StatefulWidget {
  final String agencyId;
  final String agencyName;
  final String periodTitle; // e.g. "اليوم", "أمس", "هذا الأسبوع", "هذا الشهر"
  final int totalDiamonds;
  final double commissionRate;
  final List<Map<String, dynamic>> members;

  const AgencyItemDetailScreen({
    super.key,
    required this.agencyId,
    required this.agencyName,
    required this.periodTitle,
    required this.totalDiamonds,
    required this.commissionRate,
    required this.members,
  });

  @override
  State<AgencyItemDetailScreen> createState() => _AgencyItemDetailScreenState();
}

class _AgencyItemDetailScreenState extends State<AgencyItemDetailScreen> {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> _liveMembers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _liveMembers = widget.members;
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      if (widget.agencyId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final snap = await _db
          .collection('host_agency_members')
          .where('agency_id', isEqualTo: widget.agencyId)
          .where('status', isEqualTo: 'active')
          .get();

      if (snap.docs.isNotEmpty) {
        final list = snap.docs.map((d) {
          final m = d.data();
          m['id'] = d.id;
          return m;
        }).toList();

        // Sort descending by diamonds
        list.sort((a, b) {
          final da = (a['diamonds_earned_monthly'] as num?)?.toInt() ??
              (a['diamonds_balance'] as num?)?.toInt() ??
              0;
          final dbVal = (b['diamonds_earned_monthly'] as num?)?.toInt() ??
              (b['diamonds_balance'] as num?)?.toInt() ??
              0;
          return dbVal.compareTo(da);
        });

        if (mounted) {
          setState(() {
            _liveMembers = list;
            _loading = false;
          });
        }
      } else {
        if (mounted) setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatNumber(num n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  String _formatDuration(num seconds) {
    final s = seconds.toInt();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final dyn = context.watch<DynamicConfigService>();

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: const Color(0xFF1A1A1A),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          elevation: 0,
          leading: IconButton(
            icon: Image.asset(
              R.backWhite2,
              width: 24,
              height: 24,
              errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 20),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          centerTitle: true,
          title: Text(
            isAr ? 'تفاصيل الوكالة' : 'Agency Details',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: RefreshIndicator(
          color: const Color(0xFFFFD19C),
          backgroundColor: const Color(0xFF262626),
          onRefresh: _fetchMembers,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── Header Card (matching union_adapter_agency_detail_header.xml) ──
              _buildDetailHeaderCard(isAr, dyn),

              const SizedBox(height: 16),

              // ── Table Column Headers ──
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x33000000),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        isAr ? 'المضيف' : 'Host',
                        style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Center(
                        child: Text(
                          isAr ? 'الماسات' : 'Diamonds',
                          style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Align(
                        alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
                        child: Text(
                          isAr ? 'مدة المايك' : 'Mic Time',
                          style: const TextStyle(color: Color(0xFF9E9E9E), fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // ── Members List (matching union_adapter_agency_detail_item.xml) ──
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: Color(0xFFFFD19C)),
                  ),
                )
              else if (_liveMembers.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      isAr ? 'لا توجد بيانات للمضيفين في هذه الفترة' : 'No host data in this period',
                      style: const TextStyle(color: Color(0x80FFFFFF), fontSize: 13),
                    ),
                  ),
                )
              else
                ..._liveMembers.map((m) => _buildMemberRow(m, isAr)),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  /// Header Card matching union_adapter_agency_detail_header.xml
  Widget _buildDetailHeaderCard(bool isAr, DynamicConfigService dyn) {
    final ratePercent = (widget.commissionRate * 100).toStringAsFixed(0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        image: const DecorationImage(
          image: AssetImage(R.unionAgencyItemBg),
          fit: BoxFit.fill,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period Title
          Text(
            widget.periodTitle,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 14),

          // Two Columns: Total Diamonds & Commission Rate
          Row(
            children: [
              // Diamonds Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          R.commonDiamondIc,
                          width: 20,
                          height: 20,
                          errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Color(0xFFFFD19C), size: 18),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _formatNumber(widget.totalDiamonds),
                          style: const TextStyle(
                            color: Color(0xFFFFF5AD),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAr ? 'دخل الألماس' : 'Diamond Income',
                      style: const TextStyle(
                        color: Color(0x80FFF5AD),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),

              // Commission Rate Column
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Image.asset(
                          R.unionRate1Ic,
                          width: 20,
                          height: 20,
                          errorBuilder: (_, __, ___) => const Icon(Icons.percent, color: Color(0xFFFFD19C), size: 18),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '$ratePercent %',
                          style: const TextStyle(
                            color: Color(0xFFFFF5AD),
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isAr ? 'نسبة العمولة' : 'Commission Rate',
                      style: const TextStyle(
                        color: Color(0x80FFF5AD),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Member row matching union_adapter_agency_detail_item.xml
  Widget _buildMemberRow(Map<String, dynamic> m, bool isAr) {
    final name = (m['display_name'] ?? m['name'] ?? m['user_name'] ?? (isAr ? 'مضيف' : 'Host')).toString();
    final avatar = (m['avatar_url'] ?? m['photo_url'] ?? '').toString();
    final diamonds = (m['diamonds_earned_monthly'] as num?)?.toInt() ??
        (m['diamonds_balance'] as num?)?.toInt() ??
        0;
    final liveSeconds = (m['live_seconds_monthly'] as num?)?.toInt() ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF222222),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Row(
        children: [
          // Column 1: Avatar + Nickname
          Expanded(
            flex: 4,
            child: Row(
              children: [
                ClipOval(
                  child: Container(
                    width: 32,
                    height: 32,
                    color: Colors.white10,
                    child: avatar.isNotEmpty
                        ? Image(
                            image: R.cachedImage(avatar),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(Icons.person, color: Colors.white54, size: 20),
                          )
                        : const Icon(Icons.person, color: Colors.white54, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Column 2: Diamonds
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset(
                  R.commonDiamondIc,
                  width: 14,
                  height: 14,
                  errorBuilder: (_, __, ___) => const Icon(Icons.diamond, color: Color(0xFFFFD19C), size: 12),
                ),
                const SizedBox(width: 4),
                Text(
                  _formatNumber(diamonds),
                  style: const TextStyle(
                    color: Color(0xFFFFF5AD),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Column 3: Microphone Time
          Expanded(
            flex: 3,
            child: Align(
              alignment: isAr ? Alignment.centerLeft : Alignment.centerRight,
              child: Text(
                _formatDuration(liveSeconds),
                style: const TextStyle(
                  color: Color(0xCCFFFFFF),
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
