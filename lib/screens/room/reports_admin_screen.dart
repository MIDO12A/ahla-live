import 'package:flutter/material.dart';
import '../../services/supabase_service.dart';
import '../../config/r.dart';
import 'package:zero/core/dtext.dart';

class ReportsAdminScreen extends StatefulWidget {
  const ReportsAdminScreen({super.key});

  @override
  State<ReportsAdminScreen> createState() => _ReportsAdminScreenState();
}

class _ReportsAdminScreenState extends State<ReportsAdminScreen> {
  final _service = SupabaseService();
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    setState(() => _loading = true);
    final reports = await _service.getReports();
    if (mounted) setState(() { _reports = reports; _loading = false; });
  }

  Future<void> _resolveReport(String id) async {
    await _service.resolveReport(id);
    _loadReports();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A0F0F),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_reports.isEmpty)
              _buildEmptyState()
            else
              Expanded(child: _buildReportsList()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
          const DText(
            'Reports',
            style: TextStyle(fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _loadReports,
            child: const Icon(Icons.refresh, color: Colors.white54, size: 24),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_outlined, color: Colors.white.withValues(alpha: 0.2), size: 64),
            const SizedBox(height: 16),
            const DText(
              'No reports yet',
              style: TextStyle(fontSize: 15, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsList() {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _reports.length,
      separatorBuilder: (_, __) => Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
      itemBuilder: (_, i) => _buildReportItem(_reports[i]),
    );
  }

  Widget _buildReportItem(Map<String, dynamic> report) {
    final reporter = report['reporter'] as Map<String, dynamic>? ?? {};
    final reported = report['reported'] as Map<String, dynamic>? ?? {};
    final status = report['status']?.toString() ?? 'pending';
    final reason = report['reason']?.toString() ?? '';
    final desc = report['description']?.toString() ?? '';
    final createdAt = report['created_at']?.toString() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DText(
                  'From: ${reporter['name'] ?? 'Unknown'}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
              if (status == 'pending')
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const DText('Pending', style: TextStyle(color: Colors.orange, fontSize: 10)),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const DText('Resolved', style: TextStyle(color: Colors.green, fontSize: 10)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          DText(
            'Against: ${reported['name'] ?? 'Unknown'}',
            style: const TextStyle(color: Colors.white, fontSize: 13),
          ),
          const SizedBox(height: 4),
          DText(
            'Reason: $reason',
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 2),
            DText(
              desc,
              style: const TextStyle(color: Colors.white38, fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              DText(
                createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt,
                style: const TextStyle(color: Colors.white24, fontSize: 10),
              ),
              const Spacer(),
              if (status == 'pending')
                GestureDetector(
                  onTap: () => _resolveReport(report['id']?.toString() ?? ''),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
                    ),
                    child: const DText('Resolve', style: TextStyle(color: Colors.green, fontSize: 11)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
