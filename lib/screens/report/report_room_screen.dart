import 'package:flutter/material.dart';
import '../../config/r.dart';
import 'package:zero/core/dtext.dart';

class ReportRoomScreen extends StatefulWidget {
  final String roomName;
  final String? roomAvatar;

  const ReportRoomScreen({
    super.key,
    required this.roomName,
    this.roomAvatar,
  });

  @override
  State<ReportRoomScreen> createState() => _ReportRoomScreenState();
}

class _ReportRoomScreenState extends State<ReportRoomScreen> {
  final _detailsController = TextEditingController();
  int? _selectedReason;

  final List<String> _reasons = [
    'محتوى غير لائق',
    'إعلانات مزعجة',
    'تحرش',
    'انتحال شخصية',
    'أخرى',
  ];

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  void _submit() {}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildRoomInfoCard(),
                    const SizedBox(height: 24),
                    const DText(
                      'سبب الإبلاغ',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF16151A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...List.generate(_reasons.length, (i) {
                      return _buildReasonItem(i, _reasons[i]);
                    }),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: TextField(
                        controller: _detailsController,
                        maxLines: 4,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        decoration: const InputDecoration(
                          hintText: 'تفاصيل إضافية...',
                          hintTextDirection: TextDirection.rtl,
                          hintStyle: TextStyle(color: Color(0xFF9BA1B6), fontSize: 14),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: _submit,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            R.image(R.mineReportIc, width: 22, height: 22),
                            const SizedBox(width: 8),
                            const DText(
                              'إرسال الإبلاغ',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          const DText('الإبلاغ عن الغرفة', style: TextStyle(fontSize: 17, color: Color(0xFF16151A), fontWeight: FontWeight.w500)),
          const Spacer(),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildRoomInfoCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: R.loadImage(
              widget.roomAvatar ?? R.roomBgFriend,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          DText(
            widget.roomName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Color(0xFF16151A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReasonItem(int index, String text) {
    final selected = _selectedReason == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedReason = index),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0))),
        ),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            DText(
              text,
              style: TextStyle(
                fontSize: 15,
                color: const Color(0xFF16151A),
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            const Spacer(),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? const Color(0xFF1877F2) : const Color(0xFF9BA1B6),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}
