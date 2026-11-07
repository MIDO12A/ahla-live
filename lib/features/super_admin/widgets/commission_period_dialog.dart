import 'package:flutter/material.dart';
import '../../../core/supabase_compat.dart';
import '../../../core/ui/in_app_toast.dart';
import 'package:zero/core/dtext.dart';

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
  int _weekStart = 1; // 1=الاثنين .. 7=الأحد
  int _releaseDay = 1; // أسبوعياً: 1..7 — شهرياً: 1..28
  TimeOfDay _releaseTime = const TimeOfDay(hour: 0, minute: 0);
  String _timezone = 'Asia/Riyadh';
  bool _autoRelease = false;

  bool _loading = true;
  bool _saving = false;

  static const _weekdays = <int, String>{
    1: 'الاثنين',
    2: 'الثلاثاء',
    3: 'الأربعاء',
    4: 'الخميس',
    5: 'الجمعة',
    6: 'السبت',
    7: 'الأحد',
  };

  static const _timezones = <String, String>{
    'Asia/Riyadh': 'الرياض (GMT+3)',
    'Asia/Dubai': 'دبي (GMT+4)',
    'Asia/Kuwait': 'الكويت (GMT+3)',
    'Asia/Baghdad': 'بغداد (GMT+3)',
    'Asia/Amman': 'عمّان (GMT+3)',
    'Asia/Cairo': 'القاهرة (GMT+2)',
    'Europe/London': 'لندن (GMT+0)',
    'UTC': 'UTC',
  };

  @override
  void initState() {
    super.initState();
    _fetchCurrentConfig();
  }

  String _parsePeriod(dynamic raw) {
    final v = raw?.toString().toLowerCase() ?? '';
    if (v.contains('day') || v.contains('يوم')) return 'daily';
    if (v.contains('week') || v.contains('أسبوع') || v.contains('اسبوع')) {
      return 'weekly';
    }
    return 'monthly';
  }

  Future<void> _fetchCurrentConfig() async {
    try {
      String period = 'monthly';
      int weekStart = 1;
      int releaseDay = 1;
      TimeOfDay time = const TimeOfDay(hour: 0, minute: 0);
      String timezone = 'Asia/Riyadh';
      bool autoRelease = false;

      // 1) الإعداد الكامل من app_config.agency_commission_cycle
      try {
        final cycleRow = await _sb
            .from('app_config')
            .select('value')
            .eq('key', 'agency_commission_cycle')
            .maybeSingle();
        final raw = cycleRow?['value'];
        Map<String, dynamic> map = {};
        if (raw is Map) {
          map = Map<String, dynamic>.from(raw);
        } else if (raw is String && raw.trim().isNotEmpty) {
          try {
            final decoded = raw.trim();
            // قد تُعاد كسلسلة JSON — نحلّلها يدوياً بشكل مبسّط
            if (decoded.startsWith('{')) {
              final weekMatch =
                  RegExp(r'"week_start"\s*:\s*(\d+)').firstMatch(decoded);
              final dayMatch =
                  RegExp(r'"release_day"\s*:\s*(\d+)').firstMatch(decoded);
              final timeMatch =
                  RegExp(r'"release_time"\s*:\s*"([^"]+)"').firstMatch(decoded);
              final tzMatch =
                  RegExp(r'"timezone"\s*:\s*"([^"]+)"').firstMatch(decoded);
              final periodMatch =
                  RegExp(r'"period"\s*:\s*"([^"]+)"').firstMatch(decoded);
              final autoMatch =
                  RegExp(r'"auto_release"\s*:\s*(true|false)').firstMatch(decoded);
              if (periodMatch != null) {
                map['period'] = periodMatch.group(1);
              }
              if (weekMatch != null) {
                map['week_start'] = int.tryParse(weekMatch.group(1)!);
              }
              if (dayMatch != null) {
                map['release_day'] = int.tryParse(dayMatch.group(1)!);
              }
              if (timeMatch != null) map['release_time'] = timeMatch.group(1);
              if (tzMatch != null) map['timezone'] = tzMatch.group(1);
              if (autoMatch != null) {
                map['auto_release'] = autoMatch.group(1) == 'true';
              }
            }
          } catch (_) {}
        }

        if (map['period'] != null) period = _parsePeriod(map['period']);
        weekStart = int.tryParse(map['week_start']?.toString() ?? '') ?? 1;
        releaseDay = int.tryParse(map['release_day']?.toString() ?? '') ?? 1;
        timezone = (map['timezone']?.toString().isNotEmpty ?? false)
            ? map['timezone'].toString()
            : timezone;
        autoRelease = map['auto_release'] == true ||
            map['auto_release']?.toString().toLowerCase() == 'true';
        final timeStr = map['release_time']?.toString() ?? '';
        final parts = timeStr.split(':');
        if (parts.length >= 2) {
          time = TimeOfDay(
            hour: (int.tryParse(parts[0]) ?? 0).clamp(0, 23),
            minute: (int.tryParse(parts[1]) ?? 0).clamp(0, 59),
          );
        }
      } catch (_) {}

      // 2) احتياطي: الإعداد القديم للدورة
      if (period == 'monthly') {
        final res = await _sb
            .from('commission_settings')
            .select('description')
            .eq('key', 'agency_commission_period')
            .maybeSingle();
        if (res != null) {
          period = _parsePeriod(res['description']);
        } else {
          final cfg = await _sb
              .from('app_config')
              .select('value')
              .eq('key', 'agency_commission_period')
              .maybeSingle();
          if (cfg != null && cfg['value'] != null) {
            period = _parsePeriod(cfg['value']);
          }
        }
      }

      if (mounted) {
        setState(() {
          _selectedPeriod = period;
          _weekStart = weekStart.clamp(1, 7);
          _releaseDay = releaseDay.clamp(1, 28);
          _releaseTime = time;
          _timezone = timezone;
          _autoRelease = autoRelease;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('[CommissionPeriodDialog] Error fetching config: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _timeLabel =>
      '${_releaseTime.hour.toString().padLeft(2, '0')}:${_releaseTime.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _releaseTime,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _releaseTime = picked);
  }

  Future<void> _savePeriod() async {
    setState(() => _saving = true);
    try {
      final periodVal = _selectedPeriod == 'daily'
          ? 1.0
          : (_selectedPeriod == 'weekly' ? 7.0 : 30.0);

      final cycle = <String, dynamic>{
        'period': _selectedPeriod,
        'week_start': _weekStart,
        'release_day': _releaseDay,
        'release_time': _timeLabel,
        'timezone': _timezone,
        'auto_release': _autoRelease,
      };

      // 1. الإعداد الكامل لدورة الإصدار
      try {
        await _sb.from('app_config').upsert({
          'key': 'agency_commission_cycle',
          'value': cycle,
        });
      } catch (e) {
        debugPrint('[CommissionPeriodDialog] save cycle error: $e');
      }

      // 2. التوافق مع الإعداد القديم
      await _sb.from('commission_settings').upsert({
        'key': 'agency_commission_period',
        'value': periodVal,
        'percentage': periodVal,
        'description': _selectedPeriod,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });

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
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return Dialog(
      backgroundColor: const Color(0xFF131835),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight, maxWidth: 460),
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
                    child: const Icon(Icons.date_range_rounded,
                        color: Color(0xFFFFB800), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: DText(
                      'دورة إصدار عمولة الوكالة',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Tajawal',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white54, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const DText(
                'تُحتسب العمولة كمستحقات معلّقة، ولا تُضاف للرصيد القابل للصرف إلا عند إصدارها في الموعد المحدد:',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12, fontFamily: 'Tajawal'),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFFFFB800))),
                )
              else ...[
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildOptionTile(
                          value: 'daily',
                          title: 'دورة يومية (Daily)',
                          subtitle: 'تُصدر العمولة كل يوم في الموعد المحدد',
                          icon: Icons.wb_sunny_rounded,
                          iconColor: const Color(0xFFFF9D3E),
                        ),
                        const SizedBox(height: 10),
                        _buildOptionTile(
                          value: 'weekly',
                          title: 'دورة أسبوعية (Weekly)',
                          subtitle: 'أسبوع كامل من بداية الأسبوع حتى يوم الإصدار',
                          icon: Icons.calendar_view_week_rounded,
                          iconColor: const Color(0xFF00D4FF),
                        ),
                        const SizedBox(height: 10),
                        _buildOptionTile(
                          value: 'monthly',
                          title: 'دورة شهرية (Monthly)',
                          subtitle: 'شهر كامل ينتهي بيوم الإصدار المحدد (الافتراضي)',
                          icon: Icons.calendar_month_rounded,
                          iconColor: const Color(0xFF00E5A0),
                        ),
                        const SizedBox(height: 18),
                        if (_selectedPeriod == 'weekly') ...[
                          _buildLabel('بداية الأسبوع'),
                          const SizedBox(height: 6),
                          _buildDropdown<int>(
                            value: _weekStart,
                            items: _weekdays.entries
                                .map((e) => DropdownMenuItem<int>(
                                      value: e.key,
                                      child: DText(e.value,
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontFamily: 'Tajawal')),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _weekStart = v ?? 1),
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_selectedPeriod != 'daily') ...[
                          _buildLabel(_selectedPeriod == 'weekly'
                              ? 'يوم الإصدار (اليوم)'
                              : 'يوم الإصدار (من الشهر)'),
                          const SizedBox(height: 6),
                          _selectedPeriod == 'weekly'
                              ? _buildDropdown<int>(
                                  value: _releaseDay.clamp(1, 7),
                                  items: _weekdays.entries
                                      .map((e) => DropdownMenuItem<int>(
                                            value: e.key,
                                            child: DText(e.value,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontFamily: 'Tajawal')),
                                          ))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _releaseDay = v ?? 1),
                                )
                              : _buildDropdown<int>(
                                  value: _releaseDay.clamp(1, 28),
                                  items: List.generate(28, (i) => i + 1)
                                      .map((d) => DropdownMenuItem<int>(
                                            value: d,
                                            child: DText('يوم $d',
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontFamily: 'Tajawal')),
                                          ))
                                      .toList(),
                                  onChanged: (v) =>
                                      setState(() => _releaseDay = v ?? 1),
                                ),
                          const SizedBox(height: 14),
                        ],
                        _buildLabel('وقت الإصدار'),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: _pickTime,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.access_time_rounded,
                                    color: Color(0xFFFFB800), size: 18),
                                const SizedBox(width: 10),
                                DText(
                                  _timeLabel,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Tajawal'),
                                ),
                                const Spacer(),
                                const Icon(Icons.edit_rounded,
                                    color: Colors.white38, size: 16),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        _buildLabel('المنطقة الزمنية'),
                        const SizedBox(height: 6),
                        _buildDropdown<String>(
                          value: _timezones.containsKey(_timezone)
                              ? _timezone
                              : 'Asia/Riyadh',
                          items: _timezones.entries
                              .map((e) => DropdownMenuItem<String>(
                                    value: e.key,
                                    child: DText(e.value,
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontFamily: 'Tajawal')),
                                  ))
                              .toList(),
                          onChanged: (v) => setState(
                              () => _timezone = v ?? 'Asia/Riyadh'),
                        ),
                        const SizedBox(height: 14),
                        SwitchListTile(
                          value: _autoRelease,
                          onChanged: (v) => setState(() => _autoRelease = v),
                          activeColor: const Color(0xFFFFB800),
                          contentPadding: EdgeInsets.zero,
                          title: const DText(
                            'إصدار تلقائي عند حلول الموعد',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontFamily: 'Tajawal'),
                          ),
                          subtitle: const DText(
                            'عند التعطيل يتم الإصدار يدوياً من لوحة التحكم',
                            style: TextStyle(
                                color: Colors.white38,
                                fontSize: 11,
                                fontFamily: 'Tajawal'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white70,
                          side: const BorderSide(color: Colors.white24),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _saving ? null : () => Navigator.pop(context),
                        child: const DText('إلغاء',
                            style: TextStyle(fontFamily: 'Tajawal')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFFB800),
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: _saving ? null : _savePeriod,
                        child: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.black, strokeWidth: 2),
                              )
                            : const DText(
                                'حفظ الإعدادات',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'Tajawal'),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return DText(
      text,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 12,
          fontWeight: FontWeight.bold,
          fontFamily: 'Tajawal'),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1B2145),
          icon: const Icon(Icons.expand_more_rounded, color: Colors.white54),
          items: items,
          onChanged: onChanged,
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
      onTap: () => setState(() {
        _selectedPeriod = value;
        if (value == 'weekly') {
          _releaseDay = _releaseDay.clamp(1, 7);
        } else if (value == 'monthly') {
          _releaseDay = _releaseDay.clamp(1, 28);
        }
      }),
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? iconColor.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.04),
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
                  DText(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Tajawal',
                    ),
                  ),
                  const SizedBox(height: 2),
                  DText(
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
                if (v != null) {
                  setState(() {
                    _selectedPeriod = v;
                    if (v == 'weekly') {
                      _releaseDay = _releaseDay.clamp(1, 7);
                    } else if (v == 'monthly') {
                      _releaseDay = _releaseDay.clamp(1, 28);
                    }
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
