import 'package:flutter/material.dart';
import '../../core/cache/encrypted_image_provider.dart';
import '../../services/dynamic_config_service.dart';
import 'cp_service.dart';
import 'package:zero/core/dtext.dart';

class CcCenterManagerScreen extends StatefulWidget {
  const CcCenterManagerScreen({super.key});

  @override
  State<CcCenterManagerScreen> createState() => _CcCenterManagerScreenState();
}

class _CcCenterManagerScreenState extends State<CcCenterManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _rejected = [];
  List<Map<String, dynamic>> _pending = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final data = await CpService.getMyData();
      final rejected = (data['rejected_requests'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final pending = (data['pending_requests'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) {
        setState(() {
          _rejected = rejected;
          _pending = pending;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _respond(String requestId, bool accept) async {
    await CpService.respondRequest(requestId, accept);
    _loadData();
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
        title: const DText('مركز إدارة العلاقات',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: cfg.cpGold, width: 2),
            insets: const EdgeInsets.symmetric(horizontal: 40),
          ),
          labelColor: cfg.cpGold,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          indicatorSize: TabBarIndicatorSize.label,
          dividerColor: Colors.transparent,
          tabs: [
            Tab(text: 'المرفوضة (${_rejected.length})'),
            Tab(text: 'المعلقة (${_pending.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: cfg.cpGold))
          : _error != null
              ? Center(child: DText(_error!, style: const TextStyle(color: Colors.white54)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTab(cfg, _rejected, isRejected: true),
                    _buildPendingTab(cfg, _pending),
                  ],
                ),
    );
  }

  Widget _buildTab(DynamicConfigService cfg, List<Map<String, dynamic>> items, {bool isRejected = false}) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(isRejected ? Icons.cancel_outlined : Icons.inbox_outlined,
                size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            DText(isRejected ? 'لا توجد طلبات مرفوضة' : 'لا توجد طلبات معلقة',
                style: const TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildItem(cfg, items[i], isRejected: isRejected),
      ),
    );
  }

  Widget _buildPendingTab(DynamicConfigService cfg, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
            const SizedBox(height: 12),
            const DText('لا توجد طلبات معلقة',
                style: TextStyle(color: Colors.white54, fontSize: 16)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
        itemCount: items.length,
        itemBuilder: (_, i) => _buildItem(cfg, items[i], isRejected: false),
      ),
    );
  }

  Widget _buildItem(DynamicConfigService cfg, Map<String, dynamic> req, {required bool isRejected}) {
    final name = req['sender_name'] as String? ?? '';
    final avatar = req['sender_avatar'] as String? ?? '';
    final rejectedAt = req['rejected_at'] as String?;

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cfg.cpCardBg.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cfg.cpCardBorder, width: 1),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
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
                DText(name,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    overflow: TextOverflow.ellipsis),
                if (rejectedAt != null) ...[
                  const SizedBox(height: 2),
                  DText('تم الرفض', style: TextStyle(color: cfg.cpSubText, fontSize: 11)),
                ],
              ],
            ),
          ),
          if (isRejected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const DText('مرفوض', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 60, height: 28,
                  child: ElevatedButton(
                    onPressed: () => _respond(req['id'].toString(), true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: cfg.cpGold,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                    ),
                    child: const DText('قبول', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 60, height: 28,
                  child: OutlinedButton(
                    onPressed: () => _respond(req['id'].toString(), false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white54,
                      side: const BorderSide(color: Colors.white24),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(35)),
                    ),
                    child: const DText('رفض', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
