import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/supabase_compat.dart';
import '../../../providers/user_provider.dart';
import '../../../services/supabase_data_service.dart';
import '../models/task_model.dart';
import '../widgets/task_reward_dialog.dart';

class TaskService {
  static final TaskService _instance = TaskService._internal();
  factory TaskService() => _instance;
  TaskService._internal();

  String _getTodayKey() {
    final now = DateTime.now();
    return '${now.year}_${now.month.toString().padLeft(2, '0')}_${now.day.toString().padLeft(2, '0')}';
  }

  /// جلب المهام وحالة تقدم المستخدم
  Future<List<TaskModel>> fetchTasks(String userId) async {
    final today = _getTodayKey();
    
    // 1. جلب التقدم اليومي للمستخدم من Supabase
    Map<String, dynamic> userDailyData = {};
    try {
      userDailyData = await SupabaseDataService().getUserTasksProgress(userId, today);
    } catch (_) {}

    // 2. جلب التقدم لمهام النمو الدائمة من Supabase
    Map<String, dynamic> userGrowthData = {};
    try {
      userGrowthData = await SupabaseDataService().getGrowthTasksProgress(userId);
    } catch (_) {}

    // 3. جلب قائمة المهام من لوحة التحكم (Supabase app_config ثم Firestore) مع الاحتياطي الافتراضي
    List<Map<String, dynamic>> rawTasks = [];
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'tasks_config')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final val = row['value'];
        final parsed = val is String ? jsonDecode(val) : val;
        if (parsed is List) {
          rawTasks = List<Map<String, dynamic>>.from(parsed.map((e) => Map<String, dynamic>.from(e)));
        } else if (parsed is Map) {
          rawTasks = parsed.values.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }
    } catch (e) {
      debugPrint('[TaskService] Supabase tasks_config fetch: $e');
    }

    if (rawTasks.isEmpty) {
      rawTasks = _getDefaultTasks();
    }

    final List<TaskModel> result = [];
    for (final t in rawTasks) {
      final id = t['id']?.toString() ?? '';
      final group = t['group']?.toString() ?? 'daily';
      
      int progress = 0;
      bool isClaimed = false;

      if (group != 'daily') {
        progress = (userGrowthData['${id}_progress'] as num?)?.toInt() ?? 0;
        isClaimed = userGrowthData['${id}_claimed'] == true;
      } else {
        progress = (userDailyData['${id}_progress'] as num?)?.toInt() ?? 0;
        isClaimed = userDailyData['${id}_claimed'] == true;
      }

      result.add(TaskModel.fromMap(t, userProgress: progress, claimed: isClaimed));
    }

    return result;
  }

  /// زيادة تقدم المستخدم في مهمة معينة
  Future<void> recordTaskAction(String userId, String taskId, {int amount = 1, bool isGrowth = false}) async {
    if (userId.isEmpty) return;
    final today = _getTodayKey();

    try {
      await SupabaseDataService().recordTaskAction(
        userId,
        taskId,
        amount: amount,
        isGrowth: isGrowth,
        dateKey: today,
      );
    } catch (_) {}
  }

  /// زيادة التقدم التلقائي لجميع المهام التي تطابق نوع النشاط
  /// الأنواع المدعومة: 'login' | 'mic' | 'room_stay' | 'gift' | 'lucky_gift' | 'recharge' | 'chat'
  Future<void> recordActionByType(String userId, String actionType, {int amount = 1}) async {
    if (userId.isEmpty) return;
    try {
      final tasks = await fetchTasks(userId);
      final act = actionType.toLowerCase().trim();

      for (final t in tasks) {
        if (t.isCompleted) continue;

        bool matches = false;
        final route = t.actionRoute.toLowerCase().trim();
        final id = t.id.toLowerCase().trim();
        final title = (t.titleAr + ' ' + t.titleEn).toLowerCase();
        final desc = (t.descriptionAr + ' ' + t.descriptionEn).toLowerCase();

        if (act == 'gift') {
          // إرسال هدية عادية (لا تشمل مهام الحظ الحصرية)
          final isLuckyOnly = route == 'lucky_gift' || title.contains('حظ') || id.contains('lucky');
          if (!isLuckyOnly) {
            matches = route == 'gift' || id.contains('gift') || title.contains('هد') || title.contains('gift') || desc.contains('هد');
          }
        } else if (act == 'lucky_gift') {
          // إرسال هدية حظ (يشمل مهام الحظ ومهام الهدايا العامة)
          matches = route == 'lucky_gift' || route == 'lucky' || id.contains('lucky') || title.contains('حظ') || title.contains('lucky') || desc.contains('حظ') ||
                    route == 'gift' || id.contains('gift') || title.contains('هد');
        } else if (act == 'mic') {
          // التحدث على المايك
          matches = (route == 'room' && (title.contains('ميك') || title.contains('مايك') || title.contains('تحدث') || title.contains('mic') || id.contains('mic'))) ||
                    id.contains('mic') || title.contains('ميك') || title.contains('مايك') || desc.contains('ميك') || desc.contains('مايك');
        } else if (act == 'room_stay') {
          // التواجد بالغرفة
          matches = (route == 'room' && (title.contains('غرف') || title.contains('تواجد') || title.contains('stay') || id.contains('stay'))) ||
                    id.contains('stay') || desc.contains('تواجد') || desc.contains('غرف');
        } else if (act == 'recharge') {
          // الشحن
          matches = route == 'recharge' || route == 'wallet' || id.contains('recharge') || title.contains('شحن') || title.contains('charge') || desc.contains('شحن');
        } else if (act == 'login') {
          // تسجيل الدخول
          matches = id.contains('login') || title.contains('دخول') || title.contains('check-in') || desc.contains('دخول');
        } else if (act == 'chat') {
          // إرسال رسائل في الروم
          matches = id.contains('message') || id.contains('chat') || title.contains('رسائل') || title.contains('رسالة') || title.contains('chat') || desc.contains('رسائل');
        } else if (t.id == act || route == act) {
          matches = true;
        }

        if (matches) {
          await recordTaskAction(userId, t.id, amount: amount, isGrowth: t.group == 'growth');
        }
      }
    } catch (e) {
      debugPrint('[TaskService] recordActionByType error: $e');
    }
  }

  /// استلام مكافأة المهمة وإيداع الجوائز فوراً
  Future<bool> claimTaskReward(BuildContext context, String userId, TaskModel task) async {
    if (!task.canClaim) return false;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final today = _getTodayKey();
    final isGrowth = task.group == 'growth';

    try {
      // 1. تحديث حالة الاستلام في Supabase
      await SupabaseDataService().claimTask(
        userId,
        task.id,
        isGrowth: isGrowth,
        dateKey: today,
      );

      // 2. إيداع العملات ونقاط EXP في حساب المستخدم
      final currentCoins = userProvider.currentUser?.coins ?? 0;
      final currentExp = userProvider.currentUser?.experience ?? 0;
      final supaUpdates = <String, dynamic>{};
      if (task.coinsReward > 0) {
        supaUpdates['coins'] = currentCoins + task.coinsReward;
      }
      if (task.expReward > 0) {
        supaUpdates['experience'] = currentExp + task.expReward;
        supaUpdates['exp'] = currentExp + task.expReward;
      }

      // 3. إيداع عنصر المتجر في حقيبة المستخدم إذا وجد
      if (task.storeItemId != null && task.storeItemId!.isNotEmpty) {
        try {
          final curOwned = List<String>.from(userProvider.currentUser?.ownedItems ?? []);
          if (!curOwned.contains(task.storeItemId!)) {
            curOwned.add(task.storeItemId!);
            supaUpdates['owned_items'] = curOwned;
          }

          final giftId = 'task_gift_${DateTime.now().millisecondsSinceEpoch}_${task.id}';
          final expiresAt = DateTime.now().millisecondsSinceEpoch + (7 * 86400000); // 7 أيام

          await Supabase.instance.client.from('gifted_items').insert({
            'id': giftId,
            'uid': userId,
            'item_id': task.storeItemId!,
            'item_category': 'frame',
            'item_name': task.storeItemName ?? 'جائزة إنجاز مهمة',
            'item_icon': task.storeItemIcon ?? '',
            'sent_by': 'system',
            'sent_by_name': 'مركز المهام اليومية',
            'sent_at': DateTime.now().millisecondsSinceEpoch,
            'expires_at': expiresAt,
          });

          await Supabase.instance.client.from('user_backpack').upsert({
            'user_id': userId,
            'item_id': task.storeItemId!,
            'item_type': 'backpack',
            'expires_at': DateTime.fromMillisecondsSinceEpoch(expiresAt).toIso8601String(),
          });
        } catch (itemErr) {
          debugPrint('[TaskService] store item reward error: $itemErr');
        }
      }

      if (supaUpdates.isNotEmpty) {
        await SupabaseDataService().updateUser(userId, supaUpdates);
        await userProvider.loadUser(userId);
      }

      // 4. عرض نافذة استلام المكافآت الاحتفالية
      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => TaskRewardDialog(task: task),
        );
      }

      return true;
    } catch (e) {
      debugPrint('[TaskService] claimTaskReward error: $e');
      return false;
    }
  }

  /// استلام كافة المكافآت الجاهزة دفعة واحدة مع نافذة احتفالية موحدة
  Future<int> claimAllAvailableRewards(BuildContext context, String userId, List<TaskModel> tasks) async {
    final readyTasks = tasks.where((t) => t.canClaim).toList();
    if (readyTasks.isEmpty) return 0;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final today = _getTodayKey();
    int totalCoins = 0;
    int totalExp = 0;
    final List<String> storeItemNames = [];

    for (final task in readyTasks) {
      final isGrowth = task.group == 'growth';
      await SupabaseDataService().claimTask(
        userId,
        task.id,
        isGrowth: isGrowth,
        dateKey: today,
      );
      totalCoins += task.coinsReward;
      totalExp += task.expReward;

      if (task.storeItemId != null && task.storeItemId!.isNotEmpty) {
        try {
          final giftId = 'task_gift_${DateTime.now().millisecondsSinceEpoch}_${task.id}';
          final expiresAt = DateTime.now().millisecondsSinceEpoch + (7 * 86400000);

          await Supabase.instance.client.from('gifted_items').insert({
            'id': giftId,
            'uid': userId,
            'item_id': task.storeItemId!,
            'item_category': 'frame',
            'item_name': task.storeItemName ?? 'جائزة إنجاز مهمة',
            'item_icon': task.storeItemIcon ?? '',
            'sent_by': 'system',
            'sent_by_name': 'مركز المهام اليومية',
            'sent_at': DateTime.now().millisecondsSinceEpoch,
            'expires_at': expiresAt,
          });

          await Supabase.instance.client.from('user_backpack').upsert({
            'user_id': userId,
            'item_id': task.storeItemId!,
            'item_type': 'backpack',
            'expires_at': DateTime.fromMillisecondsSinceEpoch(expiresAt).toIso8601String(),
          });
          if (task.storeItemName != null && task.storeItemName!.isNotEmpty) {
            storeItemNames.add(task.storeItemName!);
          }
        } catch (_) {}
      }
    }

    final currentCoins = userProvider.currentUser?.coins ?? 0;
    final currentExp = userProvider.currentUser?.experience ?? 0;
    final supaUpdates = <String, dynamic>{};
    if (totalCoins > 0) supaUpdates['coins'] = currentCoins + totalCoins;
    if (totalExp > 0) {
      supaUpdates['experience'] = currentExp + totalExp;
      supaUpdates['exp'] = currentExp + totalExp;
    }
    if (supaUpdates.isNotEmpty) {
      await SupabaseDataService().updateUser(userId, supaUpdates);
      await userProvider.loadUser(userId);
    }

    if (context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => TaskRewardDialog(
          task: TaskModel(
            id: 'batch_claim',
            titleAr: 'تم استلام كافة المكافآت المكتملة!',
            titleEn: 'All completed tasks claimed!',
            descriptionAr: storeItemNames.isNotEmpty ? 'العناصر: ${storeItemNames.join(", ")}' : 'تم إضافة العملات والخبرة بنجاح إلى حسابك',
            descriptionEn: 'Coins & EXP added to your account',
            group: 'daily',
            targetCount: readyTasks.length,
            currentCount: readyTasks.length,
            coinsReward: totalCoins,
            expReward: totalExp,
            actionRoute: '',
            isClaimed: true,
          ),
        ),
      );
    }

    return readyTasks.length;
  }

  /// جلب رابط بانر الفعالية لمركز المهام
  Future<String?> fetchEventBanner() async {
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select('value')
          .eq('key', 'tasks_event_config')
          .maybeSingle();
      if (row != null && row['value'] != null) {
        final val = row['value'];
        final parsed = val is String ? jsonDecode(val) : val;
        if (parsed is Map && parsed['banner_url'] != null) {
          final b = parsed['banner_url'].toString();
          if (b.isNotEmpty) return b;
        }
      }
    } catch (_) {}

    return null;
  }

  /// المهام الافتراضية المطابقة للتطبيق الأصلي
  List<Map<String, dynamic>> _getDefaultTasks() {
    return [
      // 🌟 المهام اليومية (Daily Tasks)
      {
        'id': 'daily_login',
        'title_ar': 'تسجيل الدخول اليومي',
        'title_en': 'Daily Check-in',
        'description_ar': 'قم بفتح التطبيق يومياً للحصول على المكافأة',
        'description_en': 'Open the app daily to claim reward',
        'group': 'daily',
        'target_count': 1,
        'coins_reward': 200,
        'exp_reward': 20,
        'action_route': 'none',
      },
      {
        'id': 'daily_mic_time',
        'title_ar': 'التحدث على المايك 10 دقائق',
        'title_en': 'Speak on Mic for 10 Mins',
        'description_ar': 'اصعد وتحدث في أي غرفة صوتية لمدة 10 دقائق',
        'description_en': 'Speak on any room mic for 10 minutes',
        'group': 'daily',
        'target_count': 1,
        'coins_reward': 500,
        'exp_reward': 50,
        'action_route': 'room',
      },
      {
        'id': 'daily_send_messages',
        'title_ar': 'إرسال 5 رسائل في شات الروم',
        'title_en': 'Send 5 Room Chat Messages',
        'description_ar': 'تفاعل وأرسل 5 رسائل نصية في الدردشة العامة',
        'description_en': 'Send 5 chat messages in room public chat',
        'group': 'daily',
        'target_count': 5,
        'coins_reward': 300,
        'exp_reward': 30,
        'action_route': 'room',
      },
      {
        'id': 'daily_room_stay',
        'title_ar': 'التواجد في الغرف لمدة 20 دقيقة',
        'title_en': 'Stay in Rooms for 20 Mins',
        'description_ar': 'استمع واستمتع داخل الغرف الصوتية',
        'description_en': 'Stay and listen inside voice rooms',
        'group': 'daily',
        'target_count': 1,
        'coins_reward': 400,
        'exp_reward': 40,
        'action_route': 'room',
      },
      {
        'id': 'daily_send_gift',
        'title_ar': 'إرسال هدية في الغرفة',
        'title_en': 'Send a Gift in Room',
        'description_ar': 'أرسل أي هدية للأصدقاء داخل الغرفة',
        'description_en': 'Send any gift to friends in room',
        'group': 'daily',
        'target_count': 1,
        'coins_reward': 600,
        'exp_reward': 60,
        'action_route': 'gift',
      },

      // 🎙️ مهام المضيف (Host Tasks)
      {
        'id': 'host_live_time',
        'title_ar': 'البث الصوتي المباشر لمدة 30 دقيقة',
        'title_en': 'Live Audio Broadcast for 30 Mins',
        'description_ar': 'افتح غرفتك الصوتية وتحدث مع الجمهور لمدة 30 دقيقة',
        'description_en': 'Open voice room and host for 30 minutes',
        'group': 'host',
        'target_count': 1,
        'coins_reward': 1500,
        'exp_reward': 150,
        'action_route': 'room',
      },
      {
        'id': 'host_receive_gift',
        'title_ar': 'استقبال هدايا بقيمة 5,000 كوينز',
        'title_en': 'Receive 5,000 Coins in Gifts',
        'description_ar': 'احصل على دعم وهدايا من جمهور الغرفة',
        'description_en': 'Receive gifts from room audience',
        'group': 'host',
        'target_count': 5000,
        'coins_reward': 2000,
        'exp_reward': 200,
        'action_route': 'room',
      },
      {
        'id': 'host_invite_guest',
        'title_ar': 'دعوة 3 ضيوف إلى مقاعد المايك',
        'title_en': 'Invite 3 Guests to Mic',
        'description_ar': 'ادعُ 3 مستخدمين للصعود والتحدث على المايك',
        'description_en': 'Invite 3 users to take mic seats',
        'group': 'host',
        'target_count': 3,
        'coins_reward': 800,
        'exp_reward': 80,
        'action_route': 'room',
      },

      // 🏢 مهام الوكيل (Agency Tasks)
      {
        'id': 'agency_target_coins',
        'title_ar': 'تحقيق تارجت الوكالة اليومي 50,000 كوينز',
        'title_en': 'Reach Daily Agency Target 50,000 Coins',
        'description_ar': 'مجموع نشاط إهداء وتلقي الهدايا لمضيفي الوكالة',
        'description_en': 'Total gift volume for agency hosts',
        'group': 'agency',
        'target_count': 50000,
        'coins_reward': 5000,
        'exp_reward': 500,
        'action_route': 'none',
      },
      {
        'id': 'agency_recruit_host',
        'title_ar': 'تسجيل مذيع نشط جديد في الوكالة',
        'title_en': 'Recruit a New Active Host',
        'description_ar': 'ضم مضيف جديد وتفعيله في غرف الوكالة',
        'description_en': 'Onboard new host to agency',
        'group': 'agency',
        'target_count': 1,
        'coins_reward': 3000,
        'exp_reward': 300,
        'action_route': 'profile',
      },
      {
        'id': 'agency_active_hosts',
        'title_ar': 'نشاط 5 مضيفين في وقت واحد',
        'title_en': '5 Hosts Live Concurrently',
        'description_ar': 'بث مباشر متزامن لـ 5 مضيفين من وكالتك',
        'description_en': '5 agency hosts live simultaneously',
        'group': 'agency',
        'target_count': 5,
        'coins_reward': 4000,
        'exp_reward': 400,
        'action_route': 'none',
      },
    ];
  }
}
