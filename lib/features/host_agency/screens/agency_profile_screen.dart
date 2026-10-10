import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'agency_exit_screen.dart';
import '../data/agency_models.dart';
import '../data/agency_repository.dart';
import '../../../providers/user_provider.dart';
import '../../../services/level_service.dart';
import '../../../widgets/user_id_widget.dart';
import '../../../config/r.dart';
import '../../../core/cache/encrypted_image_provider.dart';

// ═══════════════════════════════════════════════════════════════════
//  AgencyProfileScreen — شاشة تفاصيل وطلب الانضمام إلى الوكالة
//  مطابقة 1:1 للتطبيق الأصلي (UnionApplyActivity & union_activity_detail_info.xml)
// ═══════════════════════════════════════════════════════════════════
class AgencyProfileScreen extends StatefulWidget {
  final String agencyId;
  const AgencyProfileScreen({super.key, required this.agencyId});

  @override
  State<AgencyProfileScreen> createState() => _AgencyProfileScreenState();
}

class _AgencyProfileScreenState extends State<AgencyProfileScreen> {
  AgencyCard? _agency;
  bool _loading = true;
  bool _joining = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final agency = await AgencyRepository.getProfile(widget.agencyId);
      if (!mounted) return;
      setState(() {
        _agency = agency;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[agency_profile] error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      await AgencyRepository.requestJoin(widget.agencyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم إرسال طلب الانضمام بنجاح'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر إرسال الطلب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  Future<void> _leaveAgency() async {
    final exitResult = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AgencyExitScreen()),
    );
    if (exitResult == true) {
      await _load();
      return;
    }

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF222028),
        title: const Text('تأكيد الانسحاب المباشر', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'هل تريد تأكيد الانسحاب المباشر من هذه الوكالة الآن؟ سيتم إنهاء عضويتك فوراً.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الانسحاب'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _joining = true);
    try {
      await AgencyRepository.leaveAgency(widget.agencyId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ تم الانسحاب من الوكالة بنجاح'),
          backgroundColor: Color(0xFF2E7D32),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر الانسحاب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A1A),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFFD4AF37)))
          : _error != null
              ? _buildErrorView()
              : _agency == null
                  ? _buildNotFoundView()
                  : _buildContent(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white38, size: 48),
          const SizedBox(height: 12),
          const Text(
            'تعذر تحميل بيانات الوكالة',
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD4AF37),
              foregroundColor: Colors.black,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFoundView() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/mipmap-xxhdpi/common_empty_ic_1.webp',
            width: 120,
            height: 120,
            errorBuilder: (_, __, ___) => const Icon(Icons.search_off, color: Colors.white38, size: 64),
          ),
          const SizedBox(height: 16),
          const Text(
            'لم يتم العثور على الوكالة',
            style: TextStyle(color: Colors.white60, fontSize: 15),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF303030)),
            child: const Text('رجوع', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final a = _agency!;
    final topPadding = MediaQuery.of(context).padding.top;
    final rank = a.rank ?? 1;

    // تحديد خلفية الهالة حسب التصنيف تماماً كما في التطبيق الأصلي (UnionApplyActivity.kt):
    // 1 -> union_my_agency_avatar_1_bg
    // 2 -> union_my_agency_avatar_2_bg
    // 3 -> union_my_agency_avatar_3_bg
    // default -> union_my_agency_avatar_4_bg
    String auraBgAsset;
    if (rank == 1) {
      auraBgAsset = 'assets/mipmap-xxhdpi/union_my_agency_avatar_1_bg.webp';
    } else if (rank == 2) {
      auraBgAsset = 'assets/mipmap-xxhdpi/union_my_agency_avatar_2_bg.webp';
    } else if (rank == 3) {
      auraBgAsset = 'assets/mipmap-xxhdpi/union_my_agency_avatar_3_bg.webp';
    } else {
      auraBgAsset = 'assets/mipmap-xxhdpi/union_my_agency_avatar_4_bg.webp';
    }

    return Stack(
      children: [
        // ── 1. خلفية الشاشة الأساسية المطابقة للأصل (iv_header_bg) ──
        Positioned.fill(
          child: Image.asset(
            'assets/mipmap-xxhdpi/union_my_agency_bg.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/mipmap-xxhdpi/union_my_agency_bg.9.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF0F0E17)),
            ),
          ),
        ),

        // ── 2. محتوى الوسط التمريري (NestedScrollView) ──
        Positioned.fill(
          bottom: 175, // يترك مساحة كافية لبطاقة المستخدم والزر السفلية
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                SizedBox(height: topPadding + 44 + 20),

                // عنوان التصنيف: Last week's ranking / تصنيف الأسبوع الماضي
                const Text(
                  'تصنيف الأسبوع الماضي',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),

                // رقم الترتيب مع أيقونة TOP الأصلية (tv_rank_top)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/mipmap-xxhdpi/union_rank_top_ic.webp',
                      width: 32,
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'TOP $rank',
                      style: const TextStyle(
                        fontSize: 38,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFFFFFAD),
                        fontStyle: FontStyle.italic,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // ── بطاقة الوكالة المركزية مع الهالة والتاج والإطار (iv_bg + iv_avatar_bg + iv_rank_crown) ──
                Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    // صورة الهالة الخلفية للرتبة (iv_bg)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: AspectRatio(
                        aspectRatio: 1 / 1.267,
                        child: Image.asset(
                          auraBgAsset,
                          fit: BoxFit.fill,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),
                    ),

                    // التاج الذهبي للمركز الأول حصراً (iv_rank_crown)
                    if (rank == 1)
                      Positioned(
                        top: 75,
                        child: Image.asset(
                          'assets/mipmap-xxhdpi/union_agency_avatar_heder_ic.webp',
                          width: 48,
                          height: 38,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                        ),
                      ),

                    // إطار الأفاتار وصورة الوكالة المستديرة الحواف (iv_avatar_bg + iv_avatar)
                    Positioned(
                      top: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // إطار الصورة المزخرف (iv_avatar_bg: 129x129dp)
                          Image.asset(
                            'assets/mipmap-xxhdpi/union_avatar_border_ic.png',
                            width: 129,
                            height: 129,
                            fit: BoxFit.fill,
                            errorBuilder: (_, __, ___) => Container(
                              width: 129,
                              height: 129,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: const Color(0xFFFFD700), width: 2),
                              ),
                            ),
                          ),

                          // صورة الوكالة (iv_avatar: 117x117dp مع حواف دائرية 17dp)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: SizedBox(
                              width: 117,
                              height: 117,
                              child: a.photoUrl != null && a.photoUrl!.isNotEmpty
                                  ? Image(
                                      image: (a.photoUrl!.startsWith('http') && !a.photoUrl!.endsWith('.enc'))
                                          ? R.cachedImage(a.photoUrl!)
                                          : EncryptedImageProvider(a.photoUrl!),
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => _buildAvatarFallback(a.name),
                                    )
                                  : _buildAvatarFallback(a.name),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // اسم وتفاصيل الوكالة أسفل الأفاتار
                    Positioned(
                      top: 242,
                      left: 30,
                      right: 30,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // اسم الوكالة (tv_name)
                          Text(
                            a.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // بيانات الوكالة الثلاثية متراصة في المنتصف (الدولة، الأعضاء، ID)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                // علم واسم الدولة (iv_country + tv_country_name)
                                _buildAgencyMetaRow(
                                  icon: (a.country != null && a.country!.isNotEmpty)
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(2),
                                          child: Image.network(
                                            'https://flagcdn.com/w40/${a.country!.toLowerCase()}.png',
                                            width: 20,
                                            height: 13,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Text('📍', style: TextStyle(fontSize: 12)),
                                          ),
                                        )
                                      : const Text('📍', style: TextStyle(fontSize: 12)),
                                  text: a.country ?? 'عالمي',
                                ),
                                const SizedBox(height: 9),

                                // عدد الأعضاء (iv_member_ic + tv_member_count)
                                _buildAgencyMetaRow(
                                  icon: Image.asset(
                                    'assets/mipmap-xxhdpi/union_info_member_ic.webp',
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.people, size: 18, color: Color(0xFFFFFFAD)),
                                  ),
                                  text: '${a.memberCount}',
                                ),
                                const SizedBox(height: 9),

                                // معرف الوكالة (iv_id_ic + tv_member_id)
                                _buildAgencyMetaRow(
                                  icon: Image.asset(
                                    'assets/mipmap-xxhdpi/union_info_id_ic.webp',
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.contain,
                                    errorBuilder: (_, __, ___) => const Icon(Icons.badge, size: 18, color: Color(0xFFFFFFAD)),
                                  ),
                                  text: formatAgencyNumericId(a.agencyPublicId ?? a.id),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 30),
              ],
            ),
          ),
        ),

        // ── 3. شريط العنوان والرجوع العلوي (iv_back + tv_title) ──
        Positioned(
          top: topPadding,
          left: 0,
          right: 0,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // زر الرجوع الأصلي (back_white_2)
              Positioned(
                left: 6,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Image.asset(
                    'assets/mipmap-xxhdpi/back_white_2.webp',
                    width: 24,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
                  ),
                ),
              ),
              // عنوان الشاشة: تفاصيل الوكالة (union_detail_title)
              const Text(
                'تفاصيل الوكالة',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        // ── 4. البطاقة السفلية للمستخدم وزر التأكيد (cl_guild_user_info) ──
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: _buildBottomApplicantCard(a),
        ),
      ],
    );
  }

  Widget _buildAvatarFallback(String name) {
    return Container(
      color: const Color(0xFF2C243B),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name.characters.first : 'U',
        style: const TextStyle(
          color: Color(0xFFFFFFAD),
          fontSize: 34,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildAgencyMetaRow({required Widget icon, required String text}) {
    return SizedBox(
      width: 170,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(width: 22, height: 20, child: Center(child: icon)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFFFFFFAD),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// البطاقة السفلية الثابتة لعرض بيانات مقدم الطلب وزر الانضمام الذهبي (cl_guild_user_info)
  Widget _buildBottomApplicantCard(AgencyCard a) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1A1A1A),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // منحنى علوي مزخرف (union_tab_bg)
          Image.asset(
            'assets/mipmap-xxhdpi/union_tab_bg.webp',
            width: double.infinity,
            height: 14,
            fit: BoxFit.fill,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),

          // بطاقة بيانات المستخدم المتقدم (cl_user_info)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // صورة المستخدم الدائرية بحجم 48x48dp (iv_user_avatar)
                ClipOval(
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: (user?.photoUrl != null && user!.photoUrl.isNotEmpty)
                        ? Image(
                            image: R.cachedImage(user.photoUrl),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Image.asset(R.avaBoy, fit: BoxFit.cover),
                          )
                        : Image.asset(R.avaBoy, fit: BoxFit.cover),
                  ),
                ),

                const SizedBox(width: 14),

                // تفاصيل المستخدم (الاسم، الدولة، الجنس، المعرف، المستوى، أيقونة الوكالة)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // السطر الأول: علم الدولة + الاسم + أيقونة الجنس
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (user?.country != null && user!.country.isNotEmpty) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: Image.network(
                                'https://flagcdn.com/w40/${user.country.toLowerCase()}.png',
                                width: 20,
                                height: 12,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          Flexible(
                            child: Text(
                              user?.name ?? 'مستخدم',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Image.asset(
                            (user?.gender == 'female') ? R.sexFemaleIc : R.sexMaleIc,
                            width: 18,
                            height: 16,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // السطر الثاني: معرف المستخدم UserIdWidget مطابق للأصل تماماً
                      UserIdWidget(
                        idText: (user?.customId != null && user!.customId.isNotEmpty)
                            ? user.customId
                            : ((1000000 + (user?.uid.hashCode.abs() ?? 0) % 9000000).toString()),
                        showCopy: false,
                        fontSize: 11.5,
                      ),
                      const SizedBox(height: 5),

                      // السطر الثالث: أيقونة الوكالة union_ic + شارات المستوى (RankLevelView)
                      Row(
                        children: [
                          Image.asset(
                            'assets/mipmap-xxhdpi/union_ic.webp',
                            width: 20,
                            height: 20,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 6),
                          _buildLevelBadge(user?.wealthLevel ?? 1, 'wealth'),
                          const SizedBox(width: 6),
                          _buildLevelBadge(user?.rechargeLevel ?? 1, 'recharge'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // زر تقديم الطلب الأصلي الذهبي أو تم التقديم الرمادي (tv_confirm)
          Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              bottom: bottomInset > 0 ? bottomInset + 8 : 18,
            ),
            child: _buildActionButton(a),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelBadge(int level, String type) {
    final config = LevelService().getLevelConfig(type, level);
    final url = config?.imageUrl;
    if (url != null && url.isNotEmpty) {
      return SizedBox(
        width: 38,
        height: 18,
        child: R.loadAsset(url, fit: BoxFit.contain),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF2C2518),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFD700), width: 0.8),
      ),
      child: Text(
        'Lv.$level',
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          color: Color(0xFFFFFFAD),
        ),
      ),
    );
  }

  Widget _buildActionButton(AgencyCard a) {
    // الحالة 1: عضو بالفعل في الوكالة -> بطاقة العضوية + زر الانسحاب من الوكالة
    if (a.isMember) {
      return Row(
        children: [
          Expanded(
            flex: 3,
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A24),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFF2E7D32), width: 1),
              ),
              alignment: Alignment.center,
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_rounded, color: Color(0xFF4CAF50), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'أنت عضو',
                    style: TextStyle(
                      color: Color(0xFF4CAF50),
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 4,
            child: GestureDetector(
              onTap: _joining ? null : _leaveAgency,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF3B1E22),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0xFFE53935), width: 1),
                ),
                alignment: Alignment.center,
                child: _joining
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.exit_to_app, color: Color(0xFFFF5252), size: 18),
                          SizedBox(width: 6),
                          Text(
                            'الانسحاب من الوكالة',
                            style: TextStyle(
                              color: Color(0xFFFF5252),
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      );
    }

    // الحالة 2: تم التقديم وموجود طلب معلق (union_btn_nor_bg: رمادي #303030، نص #565964)
    if (a.hasPendingRequest) {
      return Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF303030),
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: const Text(
          'تم التقديم (قيد المراجعة)',
          style: TextStyle(
            color: Color(0xFFB0B3C0),
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    // الحالة 3: متاح التقديم والانضمام (الزر الذهبي الفاخر)
    return GestureDetector(
      onTap: _joining ? null : _join,
      child: Container(
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFFFAE9B5), Color(0xFFF1CC87)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x59F1CC87),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: _joining
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF59370D)),
              )
            : const Text(
                'تقديم طلب الانضمام',
                style: TextStyle(
                  color: Color(0xFF59370D),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}
