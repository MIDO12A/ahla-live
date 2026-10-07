import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/supabase_compat.dart';
import '../../../models/user_model.dart';
import '../../../core/ui/in_app_toast.dart';
import '../../../utils/translations.dart';

const Color _bgDeep    = Color(0xFF0A0E21);
const Color _bgCard    = Color(0xFF141A32);
const Color _border    = Color(0x336C63FF);
const Color _primary   = Color(0xFF6C63FF);
const Color _gold      = Color(0xFFFFB800);
const Color _cyan      = Color(0xFF00D4FF);
const Color _green     = Color(0xFF00E5A0);
const Color _textMain  = Color(0xFFFFFFFF);
const Color _textMuted = Color(0xFF8E9BB0);

class BDCenterScreen extends StatefulWidget {
  final UserModel currentUser;

  const BDCenterScreen({
    super.key,
    required this.currentUser,
  });

  @override
  State<BDCenterScreen> createState() => _BDCenterScreenState();
}

class _BDCenterScreenState extends State<BDCenterScreen> {
  final _sb = Supabase.instance.client;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _agencies = [];
  Map<String, dynamic>? _bdMeta;

  int _totalAgencies = 0;
  int _totalHosts = 0;
  int _totalDiamonds = 0;
  double _salary = 0.0;
  double _commissionRate = 10.0;
  String? _supervisorName;

  @override
  void initState() {
    super.initState();
    _salary = widget.currentUser.bdSalary;
    _commissionRate = widget.currentUser.bdCommissionRate;
    _fetchBDData();
  }

  Future<void> _fetchBDData() async {
    setState(() => _loading = true);
    try {
      final uid = widget.currentUser.uid;

      // 1. Fetch metadata from app_config if exists
      try {
        final configRow = await _sb
            .from('app_config')
            .select('value')
            .eq('key', 'bd_meta_$uid')
            .maybeSingle();

        if (configRow != null && configRow['value'] != null) {
          final meta = Map<String, dynamic>.from(configRow['value'] as Map);
          _bdMeta = meta;
          if (meta['salary'] != null) {
            _salary = (meta['salary'] as num).toDouble();
          }
          if (meta['commissionRate'] != null) {
            _commissionRate = (meta['commissionRate'] as num).toDouble();
          }
          if (meta['supervisorId'] != null && meta['supervisorId'].toString().isNotEmpty) {
            final supId = meta['supervisorId'].toString();
            // Fetch supervisor name
            final supRow = await _sb
                .from('admin_users')
                .select('display_name, email')
                .eq('uid', supId)
                .maybeSingle();
            if (supRow != null) {
              _supervisorName = supRow['display_name'] ?? supRow['email'];
            }
          }
        }
      } catch (_) {}

      // 2. Fetch agencies linked to this BD
      final agenciesRes = await _sb
          .from('host_agencies')
          .select('id, name, owner_uid, member_count, total_diamonds_monthly, total_diamonds_cumulative, data, created_at, status')
          .order('created_at', ascending: false);

      final List<Map<String, dynamic>> matchedAgencies = [];
      int totalMembers = 0;
      int diamondsSum = 0;

      if (agenciesRes != null) {
        for (final row in (agenciesRes as List)) {
          final map = Map<String, dynamic>.from(row as Map);
          final dataMap = map['data'] is Map ? Map<String, dynamic>.from(map['data'] as Map) : {};
          final bdUid = dataMap['bd_uid'] ?? dataMap['bdUid'] ?? map['owner_uid'];

          if (bdUid == uid) {
            matchedAgencies.add(map);
            totalMembers += (map['member_count'] as num? ?? 1).toInt();
            final monthly = (map['total_diamonds_monthly'] as num? ?? 0).toInt();
            final cumulative = (map['total_diamonds_cumulative'] as num? ?? 0).toInt();
            diamondsSum += (monthly > 0 ? monthly : cumulative);
          }
        }
      }

      if (mounted) {
        setState(() {
          _agencies = matchedAgencies;
          _totalAgencies = matchedAgencies.length;
          _totalHosts = totalMembers;
          _totalDiamonds = diamondsSum;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  String _formatNumber(num value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDeep,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        centerTitle: true,
        title: Text(
          context.tr('مركز الـ BD والوكالات', 'BD & Agencies Center'),
          style: const TextStyle(
            color: _textMain,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _cyan, size: 22),
            onPressed: _fetchBDData,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(_primary),
              ),
            )
          : _error != null
              ? _buildErrorView()
              : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 48),
            const SizedBox(height: 12),
            Text(
              context.tr('حدث خطأ أثناء تحميل البيانات', 'Failed to load BD data'),
              style: const TextStyle(color: _textMain, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _textMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchBDData,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(context.tr('إعادة المحاولة', 'Retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final estimatedCommission = (_totalDiamonds * (_commissionRate / 100)).round();

    return RefreshIndicator(
      onRefresh: _fetchBDData,
      color: _primary,
      backgroundColor: _bgCard,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Header Card: BD Profile & Status
          _buildBDHeaderCard(),

          const SizedBox(height: 16),

          // Statistics Grid (Agencies, Hosts, Diamonds, Salary/Earnings)
          _buildStatsGrid(estimatedCommission),

          const SizedBox(height: 20),

          // Section Title: Recruited Agencies
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: _primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.tr('الوكالات التابعة لك', 'Your Recruited Agencies'),
                    style: const TextStyle(
                      color: _textMain,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _primary.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$_totalAgencies ${context.tr("وكالة", "Agencies")}',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Agencies List or Empty State
          if (_agencies.isEmpty)
            _buildEmptyAgenciesState()
          else
            ..._agencies.map((agency) => _buildAgencyCard(agency)),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildBDHeaderCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF2E1C68),
            _bgCard,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              // BD Badge Icon
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF9C6BFF), Color(0xFF6C63FF)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _primary.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            widget.currentUser.name.isNotEmpty
                                ? widget.currentUser.name
                                : context.tr('مسؤول BD', 'BD Manager'),
                            style: const TextStyle(
                              color: _textMain,
                              fontWeight: FontWeight.bold,
                              fontSize: 17,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: _green.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            context.tr('معتمد', 'Active BD'),
                            style: const TextStyle(
                              color: _green,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ID: ${widget.currentUser.customId.isNotEmpty ? widget.currentUser.customId : widget.currentUser.uid}',
                      style: const TextStyle(
                        color: _cyan,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_supervisorName != null && _supervisorName!.isNotEmpty) ...[
            const Divider(color: Color(0x22FFFFFF), height: 24),
            Row(
              children: [
                const Icon(Icons.shield_outlined, color: _gold, size: 16),
                const SizedBox(width: 6),
                Text(
                  context.tr('المشرف المسؤول: ', 'Assigned Supervisor: '),
                  style: const TextStyle(color: _textMuted, fontSize: 13),
                ),
                Text(
                  _supervisorName!,
                  style: const TextStyle(color: _gold, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsGrid(int estimatedCommission) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: context.tr('الوكالات المسجلة', 'Agencies'),
                value: '$_totalAgencies',
                icon: Icons.corporate_fare_rounded,
                color: _cyan,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: context.tr('إجمالي المضيفين', 'Total Hosts'),
                value: '$_totalHosts',
                icon: Icons.groups_rounded,
                color: _green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                title: context.tr('ألماس الوكالات', 'Total Diamonds'),
                value: _formatNumber(_totalDiamonds),
                icon: Icons.diamond_rounded,
                color: const Color(0xFF00E5FF),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricTile(
                title: context.tr('الراتب الشهري', 'Monthly Salary'),
                value: '\$${_salary.toStringAsFixed(0)}',
                icon: Icons.attach_money_rounded,
                color: _gold,
                subtitle: '$_commissionRate% ${context.tr("عمولة", "Commission")}',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                color: color.withValues(alpha: 0.8),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyAgenciesState() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(Icons.domain_disabled_rounded, size: 48, color: _textMuted.withValues(alpha: 0.5)),
          const SizedBox(height: 12),
          Text(
            context.tr('لا توجد وكالات مسجلة تحت إدارتك بعد', 'No agencies registered under your BD code yet'),
            style: const TextStyle(color: _textMuted, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            context.tr('عند انضمام وكالات جديدة برمز الـ BD الخاص بك، ستظهر إحصاءاتها هنا تلقائياً.',
                'When agencies join with your BD referral code, their stats will appear here automatically.'),
            style: TextStyle(color: _textMuted.withValues(alpha: 0.6), fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAgencyCard(Map<String, dynamic> agency) {
    final name = agency['name']?.toString() ?? context.tr('وكالة غير مسمّاة', 'Unnamed Agency');
    final members = (agency['member_count'] as num? ?? 1).toInt();
    final monthly = (agency['total_diamonds_monthly'] as num? ?? 0).toInt();
    final cumulative = (agency['total_diamonds_cumulative'] as num? ?? 0).toInt();
    final diamonds = monthly > 0 ? monthly : cumulative;
    final status = agency['status']?.toString() ?? 'active';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.apartment_rounded, color: _primary, size: 24),
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
                        name,
                        style: const TextStyle(
                          color: _textMain,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (status == 'active' ? _green : _gold).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: status == 'active' ? _green : _gold,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded, size: 14, color: _textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '$members ${context.tr("عضو", "Members")}',
                      style: const TextStyle(color: _textMuted, fontSize: 12),
                    ),
                    const SizedBox(width: 14),
                    const Icon(Icons.diamond_outlined, size: 14, color: _cyan),
                    const SizedBox(width: 4),
                    Text(
                      _formatNumber(diamonds),
                      style: const TextStyle(color: _cyan, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
