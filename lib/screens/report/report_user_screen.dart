import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import '../../config/r.dart';
import '../../services/supabase_service.dart';
import '../../services/cloudinary_service.dart';
import '../../providers/user_provider.dart';
import 'package:zero/core/dtext.dart';

class ReportUserScreen extends StatefulWidget {
  final String nickname;
  final String reportedUid;
  final String? avatar;

  const ReportUserScreen({
    super.key,
    required this.nickname,
    required this.reportedUid,
    this.avatar,
  });

  @override
  State<ReportUserScreen> createState() => _ReportUserScreenState();
}

class _ReportUserScreenState extends State<ReportUserScreen> {
  final _detailsController = TextEditingController();
  int? _selectedReason;
  File? _screenshot;
  bool _isUploading = false;

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

  Future<void> _submit() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: DText('الرجاء اختيار سبب الإبلاغ')));
      return;
    }
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final user = userProvider.currentUser;
    if (user == null) return;

    setState(() => _isUploading = true);

    String? imageUrl;
    try {
      if (_screenshot != null) {
        imageUrl = await CloudinaryService().uploadImage(File(_screenshot!.path));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: DText('فشل رفع الصورة: $e')));
      }
      return;
    }

    final reason = _reasons[_selectedReason!];
    final details = _detailsController.text.trim();

    final data = {
      'reporter_uid': user.uid,
      'reported_uid': widget.reportedUid,
      'reported_name': widget.nickname,
      'reason': reason,
      'details': details,
      'screenshot': imageUrl ?? '',
      'created_at': DateTime.now().toIso8601String(),
      'status': 'pending',
    };

    try {
      await SupabaseService().setDoc('reports', '${user.uid}_${widget.reportedUid}_${DateTime.now().millisecondsSinceEpoch}', data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: DText('تم إرسال البلاغ بنجاح')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: DText('حدث خطأ: $e')));
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) {
      setState(() => _screenshot = File(picked.path));
    }
  }

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
                    _buildUserInfoCard(),
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
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _pickImage,
                      child: Container(
                        height: 100,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8F9FA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0E0E0), style: BorderStyle.solid),
                        ),
                        child: _screenshot != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(_screenshot!, fit: BoxFit.cover, width: double.infinity),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.add_photo_alternate, color: Color(0xFF9BA1B6), size: 32),
                                  SizedBox(height: 8),
                                  DText('إضافة سكرين شوت (اختياري)', style: TextStyle(color: Color(0xFF9BA1B6))),
                                ],
                              ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    GestureDetector(
                      onTap: _isUploading ? null : _submit,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE53935),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: _isUploading
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Row(
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
          const DText('الإبلاغ عن المستخدم', style: TextStyle(fontSize: 17, color: Color(0xFF16151A), fontWeight: FontWeight.w500)),
          const Spacer(),
          const SizedBox(width: 32),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard() {
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
            borderRadius: BorderRadius.circular(28),
            child: R.loadImage(
              widget.avatar ?? R.avaBoy,
              width: 56,
              height: 56,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          DText(
            widget.nickname,
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
