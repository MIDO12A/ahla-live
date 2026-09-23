import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../providers/user_provider.dart';
import '../models/task_model.dart';
import '../services/task_service.dart';

/// شاشة مركز المهام (Task Center) — مطابقة تماماً لتصميم act_tasks.xml و frag_task.xml و item_task.xml
class DailyTasksScreen extends StatefulWidget {
  const DailyTasksScreen({super.key});

  @override
  State<DailyTasksScreen> createState() => _DailyTasksScreenState();
}

class _DailyTasksScreenState extends State<DailyTasksScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  String? _bannerUrl;
  List<TaskModel> _tasks = [];
  int _selectedTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging || _tabCtrl.index != _selectedTabIndex) {
        setState(() => _selectedTabIndex = _tabCtrl.index);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid ?? '';

    final banner = await TaskService().fetchEventBanner();
    final list = await TaskService().fetchTasks(uid);

    if (mounted) {
      setState(() {
        _bannerUrl = banner;
        _tasks = list;
        _loading = false;
      });
    }
  }

  List<TaskModel> _filterByGroup(String group) {
    return _tasks.where((t) => t.group == group).toList();
  }

  void _handleTaskAction(TaskModel task) {
    if (task.canClaim) {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid ?? '';
      TaskService().claimTaskReward(context, uid, task).then((ok) {
        if (ok) _loadData();
      });
      return;
    }

    if (task.isCompleted) return;

    Navigator.of(context).pop();
    switch (task.actionRoute) {
      case 'room':
        break;
      case 'gift':
      case 'lucky_gift':
        break;
      case 'recharge':
        break;
      case 'store':
        break;
      case 'profile':
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.white, // @color/white من act_tasks.xml
      body: Stack(
        children: [
          // 1. الصورة الخلفية العلوية imgBg: @mipmap/bg_room_info_title
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Image.asset(
              'assets/images/bg_room_info_title.png',
              fit: BoxFit.fitWidth,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // 2. شريط العنوان toolBar: TitleToolBar (مركز المهام)
                _buildToolBar(),

                // 3. المحتوى القابل للتمرير
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF00DEFF)))
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          color: const Color(0xFF00DEFF),
                          child: SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 4. بانر الفعالية cardBanner (CardView 110dp, corner 14dp, margin 15dp)
                                _buildCardBanner(),

                                const SizedBox(height: 12),

                                // 5. بطاقة رصيد العملات والخبرة
                                _buildUserHeader(user),

                                const SizedBox(height: 14),

                                // 6. أزرار التبويبات الثلاثية المطابقة لـ frag_task.xml (مهام الوكيل، مهام المضيف، المهام اليومية)
                                _buildTabs(),

                                const SizedBox(height: 10),

                                // 7. قائمة المهام التابعة للتبويب النشط
                                _buildCurrentTaskList(),
                                const SizedBox(height: 30),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// شريط العنوان العلوي مطابق لـ toolBar
  Widget _buildToolBar() {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF333333), size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              'مركز المهام',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
          ),
          const SizedBox(width: 48), // لموازنة زر الرجوع
        ],
      ),
    );
  }

  /// بانر الفعالية cardBanner مطابق تماماً لـ CardView 110dp و 14dp radius
  Widget _buildCardBanner() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 6),
      height: 110,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: _bannerUrl != null && _bannerUrl!.isNotEmpty
            ? Image.network(
                _bannerUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                errorBuilder: (_, __, ___) => _buildDefaultBanner(),
              )
            : _buildDefaultBanner(),
      ),
    );
  }

  Widget _buildDefaultBanner() {
    return Stack(
      children: [
        Positioned.fill(
          child: Image.asset(
            'assets/images/ic_daily_task_top.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Image.asset(
              'assets/images/float_task.png',
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF00DEFF), Color(0xFF3AFF92)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.black.withValues(alpha: 0.4), Colors.transparent],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
          ),
        ),
        PositionedDirectional(
          bottom: 12,
          start: 14,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'مركز المهام والمكافآت اليومية',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 4)],
                ),
              ),
              SizedBox(height: 2),
              Text(
                'أنجز المهام واستلم كوينز وجوائز حصرية يومياً',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  shadows: [Shadow(color: Colors.black45, blurRadius: 3)],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// رصيد المستخدم من العملات ونقاط الخبرة
  Widget _buildUserHeader(dynamic user) {
    final coins = user?.coins ?? 0;
    final exp = user?.experience ?? 0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAEFF5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Row(
            children: [
              Image.asset(
                'assets/images/ic_min_coins.png',
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => const Text('🪙', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('العملات الذهبية', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                  Text(
                    '$coins',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFFFB606),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Container(width: 1, height: 26, color: const Color(0xFFE2E7ED)),
          Row(
            children: [
              Image.asset(
                'assets/images/sunlight_task.png',
                width: 22,
                height: 22,
                errorBuilder: (_, __, ___) => const Text('⭐', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('نقاط الخبرة EXP', style: TextStyle(fontSize: 11, color: Color(0xFF888888))),
                  Text(
                    '$exp',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF00B0FF),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// التبويبات الثلاثية المطابقة لـ frag_task.xml
  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 15),
      child: Row(
        children: [
          _buildTabButton(0, 'المهام اليومية'),
          const SizedBox(width: 12),
          _buildTabButton(1, 'مهام المضيف'),
          const SizedBox(width: 12),
          _buildTabButton(2, 'مهام الوكيل'),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String title) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          _tabCtrl.animateTo(index);
          setState(() => _selectedTabIndex = index);
        },
        child: Container(
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6), // app:shape_radius="6.0dp"
            gradient: isSelected
                ? const LinearGradient(
                    colors: [Color(0xFF00DEFF), Color(0xFF3AFF92)], // app:shape_solidGradientStartColor / EndColor
                  )
                : null,
            color: isSelected ? null : const Color(0xFFF3F5F7),
          ),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : const Color(0xFF666666),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTaskList() {
    final group = _selectedTabIndex == 0
        ? 'daily'
        : (_selectedTabIndex == 1 ? 'host' : 'agency');
    final list = _filterByGroup(group);

    if (list.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 40),
        alignment: Alignment.center,
        child: Column(
          children: [
            Image.asset(
              'assets/images/ic_mine_task.png',
              width: 50,
              height: 50,
              errorBuilder: (_, __, ___) => const Icon(Icons.assignment_outlined, size: 40, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            const Text(
              'لا توجد مهام حالياً في هذا القسم',
              style: TextStyle(color: Color(0xFF999999), fontSize: 13),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 15),
      itemCount: list.length,
      itemBuilder: (ctx, idx) => _buildTaskItem(list[idx]),
    );
  }

  /// عنصر المهمة مطابق تماماً لـ item_task.xml
  Widget _buildTaskItem(TaskModel task) {
    String iconAsset = 'assets/images/union_task_coin.png';
    if (task.group == 'host') {
      iconAsset = 'assets/images/sunlight_task.png';
    } else if (task.group == 'agency') {
      iconAsset = 'assets/images/bg_get_task_coin.png';
    } else {
      iconAsset = 'assets/images/mine_task.png';
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              // 1. أيقونة المهمة 42x42dp (img: 42.0dp)
              Image.asset(
                iconAsset,
                width: 42,
                height: 42,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F3F8),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.stars, color: Color(0xFF00DEFF), size: 26),
                ),
              ),
              const SizedBox(width: 12),

              // 2. تفاصيل المهمة (tvName 16sp #333333, tvCoins 14sp #fffeb606)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.titleAr.isNotEmpty ? task.titleAr : task.titleEn,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF333333),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      task.descriptionAr.isNotEmpty ? task.descriptionAr : task.descriptionEn,
                      style: const TextStyle(fontSize: 11, color: Color(0xFF888888)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),

                    // العملات والمكافأة مع أيقونة ic_min_coins.png
                    Row(
                      children: [
                        Image.asset(
                          'assets/images/ic_min_coins.png',
                          width: 14,
                          height: 14,
                          errorBuilder: (_, __, ___) => const Text('🪙', style: TextStyle(fontSize: 10)),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '+${task.coinsReward}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFFFB606), // #fffeb606
                          ),
                        ),
                        if (task.expReward > 0) ...[
                          const SizedBox(width: 8),
                          Text(
                            '+${task.expReward} EXP',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00B0FF),
                            ),
                          ),
                        ],
                        const Spacer(),
                        Text(
                          '${task.currentCount}/${task.targetCount}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFAAAAAA), fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // 3. أزرار الحالة التفاعلية tvGet / tvGoDone
              _buildActionButton(task),
            ],
          ),
        ),

        // خط التقسيم الفاصل vLine: 1.0dp #f9f9f9
        Container(
          height: 1,
          color: const Color(0xFFF5F6F8),
        ),
      ],
    );
  }

  Widget _buildActionButton(TaskModel task) {
    if (task.isClaimed) {
      // حالة الإنجاز (Done)
      return Container(
        height: 32,
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(25),
        ),
        child: const Text(
          'تم الإنجاز',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFFB8B8B8),
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    if (task.canClaim) {
      // زر الاستلام tvGet: متدرج #00deff -> #3aff92 مع دائري 25dp
      return GestureDetector(
        onTap: () => _handleTaskAction(task),
        child: Container(
          height: 32,
          constraints: const BoxConstraints(minWidth: 64),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF00DEFF), Color(0xFF3AFF92)],
            ),
            borderRadius: BorderRadius.circular(25),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00DEFF).withValues(alpha: 0.3),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Text(
            'استلام',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    // زر الذهاب tvGoDone: إطار #00d9c5 مع خلفية شفافة
    return GestureDetector(
      onTap: () => _handleTaskAction(task),
      child: Container(
        height: 32,
        constraints: const BoxConstraints(minWidth: 64),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: const Color(0xFF00D9C5), width: 1.2),
        ),
        child: const Text(
          'اذهب',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF00D9C5),
          ),
        ),
      ),
    );
  }
}
