import 'package:flutter/material.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/ui/in_app_toast.dart';

class CommissionPeriodDialog extends StatefulWidget {
  final ValueChanged<String>? onSaved;

  const CommissionPeriodDialog({
    super.key,
    this.onSaved,
  });

  static Future<void> show(
    BuildContext context, {
    ValueChanged<String>? onSaved,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => CommissionPeriodDialog(onSaved: onSaved),
    );
  }

  @override
  State<CommissionPeriodDialog> createState() => _CommissionPeriodDialogState();
}

class _CommissionPeriodDialogState extends State<CommissionPeriodDialog> {
  final _sb = Supabase.instance.client;
  String _selectedPeriod = 'monthly';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentPeriod();
  }

  Future<void> _fetchCurrentPeriod() async {
    try {
      final res = await _sb
          .from('commission_settings')
          .select('description, value')
          .eq('key', 'agency_commission_period')
          .maybeSingle();

      String period = 'monthly';
      if (res != null) {
        final desc = res['description']?.toString()?.toLowerCase() ?? '';
        if (desc.contains('day') || desc.contains('يوم')) {
          period = 'daily';
        } else if (desc.contains('week') || desc.contains('أسبوع') || desc.contains('اسبوع')) {
          period = 'weekly';
        } else {
          period = 'monthly';
        }
      } else {
        final cfg = await _sb
            .from('app_config')
            .select('value')
            .eq('key', 'agency_commission_period')
            .maybeSingle();
        if (cfg != null && cfg['value'] != null) {
          final v = cfg['value'].toString().toLowerCase();
          if (v.contains('day') || v.contains('يوم')) {
            period = 'daily';
          } else if (v.contains('week') || v.contains('أسبوع') || v.contains('اسبوع')) {
            period = 'weekly';
          } else {
            period = 'monthly';
          }
        }
      }

      if (mounted) {
        setState(() {
          _selectedPeriod = period;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[CommissionPeriodDialog] Error fetching period: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _savePeriod() async {
    setState(() => _saving = true);
    try {
      final periodVal = _selectedPeriod == 'daily' ? 1.0 : (_selectedPeriod == 'weekly' ? 7.0 : 30.0);

      // 1. Update commission_settings
      await _sb.from('commission_settings').upsert({
        'key': 'agency_commission_period',
        'value': periodVal,
        'percentage': periodVal,
        'description': _selectedPeriod,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

      // 2. Update app_config for realtime syncing across app
      try {
        await _sb.from('app_config').upsert({
          'key': 'agency_commission_period',
          'value': _selectedPeriod,
        });
      } catch (_) {}

      final label = _selectedPeriod == 'daily'
          ? 'يومي ☀️'
          : (_selectedPeriod == 'weekly' ? 'أسبوعي 📅' : 'شهري 🗓️');

      KayanInAppToast.success('تم ضبط دورة عمولة الوكالة بنجاح ($label)');
      widget.onSaved?.call(_selectedPeriod);

      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[CommissionPeriodDialog] Error saving period: $e');
      KayanInAppToast.error('فشل حفظ الدورة: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF131835),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFFFB800).withValues(alpha: 0.3)),
          gradient: const LinearGradient(
            colors: [Color(0xFF161B3D), Color(0xFF0F1226)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFB800).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.date_range_rounded, color: Color(0xFFFFB800), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'تحديد دورة احتساب عمولة الوكالة',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 20),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'اختر دورة احتساب وعرض أرباح عمولة الوكلاء في شاشات الوكالة:',
              style: TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'Tajawal'),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(30),
                child: Center(child: CircularProgressIndicator(color: Color(0xFFFFB800))),
              )
            else ...[
              _buildOptionTile(
                value: 'daily',
                title: 'دورة يومية (Daily)',
                subtitle: 'تُحتسب وتُعرض عمولة الوكالة بناءً على أرباح اليوم',
                icon: Icons.wb_sunny_rounded,
                iconColor: const Color(0xFFFF9D3E),
              ),
              const SizedBox(height: 10),
              _buildOptionTile(
                value: 'weekly',
                title: 'دورة أسبوعية (Weekly)',
                subtitle: 'تُحتسب وتُعرض عمولة الوكالة بنظام كل أسبوع (7 أيام)',
                icon: Icons.calendar_view_week_rounded,
                iconColor: const Color(0xFF00D4FF),
              ),
              const SizedBox(height: 10),
              _buildOptionTile(
                value: 'monthly',
                title: 'دورة شهرية (Monthly)',
                subtitle: 'تُحتسب وتُعرض عمولة الوكالة بنظام شهري كامل (الافتراضي)',
                icon: Icons.calendar_month_rounded,
                iconColor: const Color(0xFF00E5A0),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('إلغاء', style: TextStyle(fontFamily: 'Tajawal')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFB800),
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: _saving ? null : _savePeriod,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                            )
                          : const Text(
                              'حفظ التحديد',
                              style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Tajawal'),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
  }) {
    final isSelected = _selectedPeriod == value;
    return InkWell(
      onTap: () => setState(() => _selectedPeriod = value),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? iconColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                ],
              ),
            ),
            Radio<String>(
              value: value,
              groupValue: _selectedPeriod,
              activeColor: iconColor,
              onChanged: (v) {
                if (v != null) setState(() => _selectedPeriod = v);
              },
            ),
          ],
        ),
      ),
    );
  }
}
