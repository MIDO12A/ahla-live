import 'package:flutter/material.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';

class AgencyVerificationScreen extends StatefulWidget {
  const AgencyVerificationScreen({super.key});

  @override
  State<AgencyVerificationScreen> createState() => _AgencyVerificationScreenState();
}

class _AgencyVerificationScreenState extends State<AgencyVerificationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _docNumberController = TextEditingController();
  final _platformsController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _countryController = TextEditingController();

  HostDocType _selectedDocType = HostDocType.idCard;
  int _dailyHours = 4;
  int _videoDuration = 6; // between 5 and 10 seconds

  final String _docFrontUrl = 'https://picsum.photos/400/250';
  final String _docBackUrl = 'https://picsum.photos/400/250';
  final String _facePhoto1Url = 'https://picsum.photos/300/300';
  final String _facePhoto2Url = 'https://picsum.photos/300/300';
  final String _videoUrl = 'https://sample-videos.com/video123/mp4/720/big_buck_bunny_720p_1mb.mp4';

  bool _isLoading = true;
  bool _isSubmitting = false;
  HostVerificationModel? _existingVerification;

  @override
  void initState() {
    super.initState();
    _loadExistingVerification();
  }

  Future<void> _loadExistingVerification() async {
    setState(() => _isLoading = true);
    try {
      final v = await AgencyRepository.getHostVerificationStatus();
      if (mounted) {
        setState(() {
          _existingVerification = v;
          if (v != null) {
            _nameController.text = v.fullName;
            _selectedDocType = v.docType;
            _docNumberController.text = v.docNumber ?? '';
            _platformsController.text = v.previousPlatforms ?? '';
            _dailyHours = v.dailyWorkHours;
            _whatsappController.text = v.whatsapp ?? '';
            _countryController.text = v.country ?? '';
            _videoDuration = v.videoDurationSeconds;
          }
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _submitVerification() async {
    if (!_formKey.currentState!.validate()) return;

    if (_videoDuration < 5 || _videoDuration > 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('يجب أن تكون مدة مقطع الفيديو بين 5 و 10 ثوانٍ فقط')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final verification = HostVerificationModel(
        id: '',
        uid: '',
        fullName: _nameController.text.trim(),
        docType: _selectedDocType,
        docNumber: _docNumberController.text.trim(),
        docFrontUrl: _docFrontUrl,
        docBackUrl: _selectedDocType == HostDocType.passport ? null : _docBackUrl,
        facePhoto1Url: _facePhoto1Url,
        facePhoto2Url: _facePhoto2Url,
        videoUrl: _videoUrl,
        videoDurationSeconds: _videoDuration,
        previousPlatforms: _platformsController.text.trim(),
        dailyWorkHours: _dailyHours,
        country: _countryController.text.trim(),
        whatsapp: _whatsappController.text.trim(),
        createdAt: DateTime.now(),
      );

      await AgencyRepository.submitHostVerification(verification);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تقديم طلب توثيق المضيف بنجاح! سيتم مراجعته قريباً.')),
        );
        _loadExistingVerification();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء التقديم: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _docNumberController.dispose();
    _platformsController.dispose();
    _whatsappController.dispose();
    _countryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1938),
      appBar: AppBar(
        title: const Text('توثيق المضيف الحقيقي', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF0C1938),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00B5B3)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_existingVerification != null) _buildStatusBanner(),
                    const SizedBox(height: 16),
                    _buildSectionHeader('1. بيانات الهوية الرسمية'),
                    const SizedBox(height: 10),
                    _buildDocTypeSelector(),
                    const SizedBox(height: 12),
                    _buildTextField(_nameController, 'الاسم الكامل (كما في الوثيقة) *', isRequired: true),
                    const SizedBox(height: 12),
                    _buildTextField(_docNumberController, 'رقم الوثيقة / بطاقة الهوية'),
                    const SizedBox(height: 16),
                    _buildSectionHeader('2. رفع صور الوثيقة والوجه'),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _buildUploadCard('الوجه الأمامي للوثيقة', _docFrontUrl, Icons.badge)),
                        const SizedBox(width: 10),
                        if (_selectedDocType != HostDocType.passport)
                          Expanded(child: _buildUploadCard('الوجه الخلفي للوثيقة', _docBackUrl, Icons.badge_outlined)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildUploadCard('صورة الوجه 1 (أمامية واضحة)', _facePhoto1Url, Icons.face)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildUploadCard('صورة الوجه 2 (زاوية أخرى)', _facePhoto2Url, Icons.face_retouching_natural)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildSectionHeader('3. فيديو التحقق الحي (5 - 10 ثوانٍ)'),
                    const SizedBox(height: 10),
                    _buildVideoSection(),
                    const SizedBox(height: 16),
                    _buildSectionHeader('4. استبيان ومعلومات العمل'),
                    const SizedBox(height: 10),
                    _buildTextField(_platformsController, 'المنصات السابقة التي عملت بها'),
                    const SizedBox(height: 12),
                    _buildDailyHoursSelector(),
                    const SizedBox(height: 12),
                    _buildTextField(_countryController, 'الدولة / المنطقة'),
                    const SizedBox(height: 12),
                    _buildTextField(_whatsappController, 'رقم WhatsApp للتواصل الرسمي'),
                    const SizedBox(height: 24),
                    _buildSubmitButton(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusBanner() {
    Color bg;
    IconData icon;
    String text;

    if (_existingVerification!.isApproved) {
      bg = Colors.green.shade800;
      icon = Icons.verified;
      text = 'تم توثيق حسابك كمضيف رسمي بنجاح! يمكنك الآن الانضمام للوكالات.';
    } else if (_existingVerification!.isRejected) {
      bg = Colors.red.shade800;
      icon = Icons.error;
      text = 'تم رفض طلب التوثيق: ${_existingVerification!.rejectionReason ?? "يرجى تعديل البيانات وإعادة التقديم."}';
    } else {
      bg = Colors.amber.shade800;
      icon = Icons.hourglass_top;
      text = 'طلبك قيد المراجعة حالياً من قبل الإدارة. يرجى الانتظار بصبر.';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(
        children: [
          Icon(icon, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(color: Color(0xFF00B5B3), fontSize: 15, fontWeight: FontWeight.bold),
    );
  }

  Widget _buildDocTypeSelector() {
    return Row(
      children: HostDocType.values.map((type) {
        final isSelected = _selectedDocType == type;
        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _selectedDocType = type),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF00B5B3) : const Color(0xFF16274D),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isSelected ? Colors.white : Colors.transparent),
              ),
              child: Center(
                child: Text(
                  type.label,
                  style: TextStyle(color: isSelected ? Colors.white : Colors.white70, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextField(TextEditingController controller, String hint, {bool isRequired = false}) {
    return TextFormField(
      controller: controller,
      style: const TextStyle(color: Colors.white, fontSize: 14),
      validator: isRequired ? (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null : null,
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(color: Colors.white60, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF16274D),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildUploadCard(String label, String url, IconData icon) {
    return Container(
      height: 90,
      decoration: BoxDecoration(
        color: const Color(0xFF16274D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24, style: BorderStyle.solid),
      ),
      child: InkWell(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم اختيار $label')));
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF00B5B3), size: 28),
            const SizedBox(height: 6),
            Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF16274D),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.videocam, color: Color(0xFF00B5B3)),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('فيديو سيلفي للتحقق من الشخص الحقيقي', style: TextStyle(color: Colors.white, fontSize: 13)),
              ),
              Text('$_videoDuration ثوانٍ', style: const TextStyle(color: Color(0xFF00B5B3), fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Slider(
            value: _videoDuration.toDouble(),
            min: 5,
            max: 10,
            divisions: 5,
            activeColor: const Color(0xFF00B5B3),
            inactiveColor: Colors.white24,
            label: '$_videoDuration ثوانٍ',
            onChanged: (v) => setState(() => _videoDuration = v.toInt()),
          ),
          const Text('تنبيه: يجب أن تظهر ملامح وجهك بوضوح تام لمدة لا تقل عن 5 ولا تزيد عن 10 ثوانٍ.', style: TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildDailyHoursSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16274D),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text('ساعات العمل اليومية المتاحة:', style: TextStyle(color: Colors.white70, fontSize: 13)),
          DropdownButton<int>(
            value: _dailyHours,
            dropdownColor: const Color(0xFF16274D),
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: 2, child: Text('ساعتان (2H)')),
              DropdownMenuItem(value: 4, child: Text('4 ساعات (4H)')),
              DropdownMenuItem(value: 6, child: Text('6 ساعات (6H)')),
              DropdownMenuItem(value: 8, child: Text('8 ساعات (8H)')),
            ],
            onChanged: (v) => setState(() => _dailyHours = v ?? 4),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF00B5B3),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: _isSubmitting ? null : _submitVerification,
        child: _isSubmitting
            ? const CircularProgressIndicator(color: Colors.white)
            : const Text('تقديم طلب التوثيق', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
