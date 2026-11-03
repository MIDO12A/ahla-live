import 'package:flutter/material.dart';
import '../../core/cache/encrypted_image_provider.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';
import 'package:zero/core/dtext.dart';

class CcInvitationListScreen extends StatefulWidget {
  const CcInvitationListScreen({super.key});

  @override
  State<CcInvitationListScreen> createState() => _CcInvitationListScreenState();
}

class _CcInvitationListScreenState extends State<CcInvitationListScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await CpService.getMyData();
      final requests = (data['pending_requests'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _requests = requests;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _respond(String requestId, bool accept) async {
    await CpService.respondRequest(requestId, accept);
    _loadRequests();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = DynamicConfigService();

    return Scaffold(
      backgroundColor: cfg.cpHeaderBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const DText('قائمة الدعوات', style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cfg.cpGold))
          : _error != null
              ? Center(child: DText(_error!, style: const TextStyle(color: Colors.white54)))
              : Column(
                  children: [
                    // Seat limit card
                    Container(
                      height: 36,
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                      decoration: BoxDecoration(
                        color: cfg.cpCardBg.withValues(alpha: 0.3),
                        borderRadius: const BorderRadius.all(Radius.circular(6)),
                      ),
                      child: const Row(
                        children: [
                          SizedBox(width: 8),
                          Expanded(child: DText('حد المقاعد', style: TextStyle(color: Color(0xFFd99d47), fontSize: 14, fontWeight: FontWeight.bold))),
                          Icon(Icons.add_box, color: Colors.white, size: 28),
                          SizedBox(width: 4),
                          DText('بطاقة مقعد', style: TextStyle(color: Colors.white, fontSize: 12)),
                          Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
                          SizedBox(width: 8),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: _requests.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.mail_outline, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(height: 12),
                                  const DText('لا توجد دعوات', style: TextStyle(color: Colors.white54, fontSize: 16)),
                                ],
                              ),
                            )
                          : RefreshIndicator(
                              onRefresh: _loadRequests,
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(12, 0, 12, 80),
                                itemCount: _requests.length,
                                itemBuilder: (_, i) => _buildRequestItem(cfg, _requests[i]),
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildRequestItem(DynamicConfigService cfg, Map<String, dynamic> req) {
    final name = req['sender_name'] as String? ?? req['name'] as String? ?? '';
    final avatar = req['sender_avatar'] as String? ?? '';
    final msg = req['message'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cfg.cpCardBg.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cfg.cpCardBorder, width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            backgroundImage: avatar.isNotEmpty ? EncryptedImageProvider(avatar) : null,
            child: avatar.isEmpty
                ? Icon(Icons.person, color: Colors.white.withValues(alpha: 0.5))
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 100),
                      child: DText(name,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          overflow: TextOverflow.ellipsis),
                    ),
                    if (msg.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: DText(msg,
                            style: TextStyle(color: cfg.cpSubText, fontSize: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildSmallChip(Icons.female, const Color(0xFFff6b9d)),
                    const SizedBox(width: 8),
                    DText('نقاط: 0', style: TextStyle(color: cfg.cpSubText, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(
            width: 80, height: 28,
            child: ElevatedButton(
              onPressed: () => _respond(req['id'].toString(), true),
              style: ElevatedButton.styleFrom(
                backgroundColor: cfg.cpGold,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
              ),
              child: const DText('إرسال', style: TextStyle(color: Colors.white, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallChip(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, size: 12, color: color),
    );
  }
}
