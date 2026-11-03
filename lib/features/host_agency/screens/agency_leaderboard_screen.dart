import 'package:flutter/material.dart';

import '../data/agency_models.dart';
import '../data/agency_repository.dart';
import 'agency_profile_screen.dart';
import '../../../core/cache/encrypted_image_provider.dart';
import 'package:zero/core/dtext.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyLeaderboardScreen — تصنيف الوكالات
// ═══════════════════════════════════════════════════════════════════
class AgencyLeaderboardScreen extends StatefulWidget {
  const AgencyLeaderboardScreen({super.key});

  @override
  State<AgencyLeaderboardScreen> createState() => _AgencyLeaderboardScreenState();
}

class _AgencyLeaderboardScreenState extends State<AgencyLeaderboardScreen> {
  final ScrollController _scroll = ScrollController();
  List<AgencyLeaderboardEntry> _entries = [];
  bool _loading = true;
  bool _loadingMore = false;
  String? _filterCountry;
  int _offset = 0;
  static const int _pageSize = 30;

  // ─── الدول المتاحة للتصفية ──────────────────────────────────────
  final List<String?> _countries = [null, 'SA', 'AE', 'KW', 'QA', 'EG', 'JO'];
  final Map<String?, String> _countryLabels = {
    null:  '🌐 عالمي',
    'SA':  '🇸🇦 السعودية',
    'AE':  '🇦🇪 الإمارات',
    'KW':  '🇰🇼 الكويت',
    'QA':  '🇶🇦 قطر',
    'EG':  '🇪🇬 مصر',
    'JO':  '🇯🇴 الأردن',
  };

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 200 &&
        !_loadingMore) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      setState(() { _loading = true; _offset = 0; _entries = []; });
    } else {
      if (_loadingMore) return;
      setState(() => _loadingMore = true);
    }

    final data = await AgencyRepository.getLeaderboard(
      country: _filterCountry,
      limit:   _pageSize,
      offset:  reset ? 0 : _offset,
    );

    if (!mounted) return;
    setState(() {
      if (reset) {
        _entries  = data;
        _loading  = false;
      } else {
        _entries.addAll(data);
        _loadingMore = false;
      }
      _offset += data.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        foregroundColor: Colors.white,
        title: const DText('🏆 تصنيف الوكالات', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter strip
          _buildFilterStrip(),
          // List
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
                : _entries.isEmpty
                    ? Center(
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const DText('🏢', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          DText('لا توجد وكالات بعد', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                        ]),
                      )
                    : RefreshIndicator(
                        color: const Color(0xFFD4AF37),
                        onRefresh: () => _load(reset: true),
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _entries.length + (_loadingMore ? 1 : 0),
                          itemBuilder: (ctx, i) {
                            if (i == _entries.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16),
                                child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFD4AF37))),
                              );
                            }
                            return _AgencyRankCard(
                              entry: _entries[i],
                              onTap: () => Navigator.push(context, MaterialPageRoute(
                                builder: (_) => AgencyProfileScreen(agencyId: _entries[i].agencyId),
                              )),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterStrip() {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _countries.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final c = _countries[i];
          final selected = _filterCountry == c;
          return GestureDetector(
            onTap: () {
              setState(() => _filterCountry = c);
              _load(reset: true);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              decoration: BoxDecoration(
                color: selected ? const Color(0xFFD4AF37) : Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: DText(
                _countryLabels[c] ?? c ?? 'عالمي',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? Colors.black : Colors.white.withOpacity(0.7),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─── بطاقة الوكالة في التصنيف ─────────────────────────────────────
class _AgencyRankCard extends StatelessWidget {
  final AgencyLeaderboardEntry entry;
  final VoidCallback onTap;

  const _AgencyRankCard({required this.entry, required this.onTap});

  static const _tierColors = {
    AgencyTier.bronze:   Color(0xFFCD7F32),
    AgencyTier.silver:   Color(0xFFC0C0C0),
    AgencyTier.gold:     Color(0xFFD4AF37),
    AgencyTier.platinum: Color(0xFF6ADBF5),
    AgencyTier.diamond:  Color(0xFFB39DDB),
  };

  String _fmtK(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000)    return '${(n / 1000).toStringAsFixed(0)}K';
    return n.toString();
  }

  @override
  Widget build(BuildContext context) {
    final tierColor = _tierColors[entry.tier] ?? const Color(0xFFD4AF37);
    final isTop3 = entry.rank <= 3;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: isTop3
              ? LinearGradient(
                  colors: [tierColor.withOpacity(0.15), Colors.transparent],
                  begin: Alignment.centerRight,
                )
              : null,
          color: isTop3 ? null : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isTop3 ? tierColor.withOpacity(0.4) : Colors.white.withOpacity(0.08),
          ),
        ),
        child: Row(
          children: [
            // Rank badge
            _RankBadge(rank: entry.rank, tierColor: tierColor),
            const SizedBox(width: 12),
            // Agency avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: tierColor.withOpacity(0.2),
                image: entry.photoUrl != null
                    ? DecorationImage(image: EncryptedImageProvider(entry.photoUrl!), fit: BoxFit.cover)
                    : null,
              ),
              child: entry.photoUrl == null
                  ? Center(child: DText(entry.name.characters.first, style: TextStyle(color: tierColor, fontWeight: FontWeight.bold, fontSize: 18)))
                  : null,
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DText(entry.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isHallOfFame) ...[
                        const SizedBox(width: 4),
                        const DText('🏆', style: TextStyle(fontSize: 12)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      _Chip(label: entry.tier.label, color: tierColor),
                      const SizedBox(width: 6),
                      if (entry.agencyPublicId != null) ...[
                        DText(
                          'ID: ${entry.agencyPublicId}',
                          style: const TextStyle(
                            color: Color(0xFFD4AF37),
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      DText('${entry.memberCount} عضو',
                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
            // Diamonds
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                DText(_fmtK(entry.totalDiamondsMonthly),
                  style: TextStyle(
                    color: tierColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const DText('♦ الشهر',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  final Color tierColor;

  const _RankBadge({required this.rank, required this.tierColor});

  @override
  Widget build(BuildContext context) {
    final emojis = {1: '🥇', 2: '🥈', 3: '🥉'};
    if (emojis.containsKey(rank)) {
      return SizedBox(width: 32, child: Center(child: DText(emojis[rank]!, style: const TextStyle(fontSize: 24))));
    }
    return SizedBox(
      width: 32,
      child: Center(
        child: DText('#$rank',
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontWeight: FontWeight.bold, fontSize: 13)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: DText(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
