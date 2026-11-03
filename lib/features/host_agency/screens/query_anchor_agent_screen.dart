import 'package:flutter/material.dart';
import '../../../../config/r.dart';
import '../data/anchor_agent_model.dart';
import 'package:zero/core/dtext.dart';

/// شاشة البحث عن المضيفين داخل الوكالة (QueryAnchorAgentActivity)
class QueryAnchorAgentScreen extends StatefulWidget {
  final List<AnchorAgentUserInfoDataModel> anchors;

  const QueryAnchorAgentScreen({super.key, required this.anchors});

  @override
  State<QueryAnchorAgentScreen> createState() => _QueryAnchorAgentScreenState();
}

class _QueryAnchorAgentScreenState extends State<QueryAnchorAgentScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  List<AnchorAgentUserInfoDataModel> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = widget.anchors;
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() => _filtered = widget.anchors);
    } else {
      setState(() {
        _filtered = widget.anchors.where((a) {
          final idMatch = a.userId.toString().contains(query) || a.userNo.toString().contains(query);
          final nameMatch = a.nickname.toLowerCase().contains(query);
          return idMatch || nameMatch;
        }).toList();
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: Color(0xFF333333)),
          onPressed: () => Navigator.pop(context),
        ),
        title: Container(
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F1F5),
            borderRadius: BorderRadius.circular(19),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: Colors.black45),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  style: const TextStyle(fontSize: 13, color: Color(0xFF333333)),
                  decoration: const InputDecoration(
                    hintText: 'ابحث عن مضيف بالـ ID أو الاسم...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.black38),
                    border: InputBorder.none,
                    isDense: true,
                  ),
                ),
              ),
              if (_searchCtrl.text.isNotEmpty)
                GestureDetector(
                  onTap: () => _searchCtrl.clear(),
                  child: const Icon(Icons.close, size: 16, color: Colors.black45),
                ),
            ],
          ),
        ),
      ),
      body: _filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.search_off, size: 54, color: Colors.black26),
                  SizedBox(height: 10),
                  DText('لا توجد نتائج مطابقة لبحثك', style: TextStyle(color: Colors.black45, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final a = _filtered[index];
                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundImage: a.headImage.isNotEmpty ? R.cachedImage(a.headImage) : null,
                        child: a.headImage.isEmpty ? const Icon(Icons.person, color: Colors.white70) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            DText(
                              a.nickname,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF333333),
                              ),
                            ),
                            const SizedBox(height: 2),
                            DText(
                              'ID: ${a.userNo > 0 ? a.userNo : a.userId}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                            ),
                            const SizedBox(height: 2),
                            DText(
                              a.formattedTime,
                              style: const TextStyle(fontSize: 11, color: Color(0xFFDE880F)),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          DText(
                            '${R.formatCoins(int.tryParse(a.diamonds) ?? 0)} 💎',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFDE880F),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: a.targetProgress >= 1.0 ? Colors.green.shade50 : Colors.amber.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: DText(
                              a.targetProgress >= 1.0 ? 'مكتمل ✅' : '${(a.targetProgress * 100).toInt()}% من التارجت',
                              style: TextStyle(
                                fontSize: 10,
                                color: a.targetProgress >= 1.0 ? Colors.green.shade700 : Colors.amber.shade900,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
