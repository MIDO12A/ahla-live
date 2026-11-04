import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../config/supabase_config.dart';
import '../../../core/supabase_compat.dart';
import '../../../models/message_model.dart';
import '../../../services/global_banner_service.dart';
import '../../../services/supabase_data_service.dart';
import '../models/lucky_bag_config.dart';
import '../models/lucky_bag_model.dart';
import '../widgets/lucky_bag_grab_overlay.dart';
import 'package:zero/core/dtext.dart';

/// خدمة المظاريف الحمراء وأكياس الحظ (Lucky Bag / Red Packet)
///
/// تعمل بالكامل على جدول `lucky_bags` في Supabase بدون RPC:
/// - `total_count` / `remaining_count`: عدد الحقائب الكلي والمتبقي
/// - `total_value` / `remaining_value`: قيمة العملات الكلية والمتبقية
/// - `claims` (jsonb): `{ meta: {...}, list: [claim, ...] }`
class LuckyBagService {
  static final LuckyBagService _instance = LuckyBagService._internal();
  factory LuckyBagService() => _instance;
  LuckyBagService._internal();

  static const String _baseUrl = SupabaseConfig.projectUrl;

  static Map<String, String> get _headers => {
        'apikey': SupabaseConfig.anonKey,
        'Authorization': 'Bearer ${SupabaseConfig.anonKey}',
        'Content-Type': 'application/json',
      };

  final SupabaseDataService _ds = SupabaseDataService();

  LuckyBagConfig _config = const LuckyBagConfig();
  DateTime _configLoadedAt = DateTime.fromMillisecondsSinceEpoch(0);

  Timer? _expiryTimer;
  bool _processingExpiry = false;

  Map<String, Map<String, dynamic>> _localBags = {};

  // ── الإعدادات ──────────────────────────────────────────

  /// تحميل إعدادات الحقيبة من `app_config` (كاش 20 ثانية).
  Future<LuckyBagConfig> loadConfig({bool force = false}) async {
    final fresh = DateTime.now().difference(_configLoadedAt) <
        const Duration(seconds: 20);
    if (!force && fresh) return _config;
    try {
      final url = Uri.parse(
        '$_baseUrl/rest/v1/app_config?key=eq.lucky_bag_config&select=value&limit=1',
      );
      final res = await http.get(url, headers: _headers).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          final rawValue = (list.first as Map)['value'];
          final map = rawValue is Map
              ? Map<String, dynamic>.from(rawValue)
              : rawValue is String
                  ? Map<String, dynamic>.from(jsonDecode(rawValue) as Map)
                  : <String, dynamic>{};
          _config = LuckyBagConfig.fromJson(map);
          _configLoadedAt = DateTime.now();
        }
      }
    } catch (e) {
      debugPrint('[LuckyBagService] loadConfig error: $e');
    }
    return _config;
  }

  // ── الإرسال ────────────────────────────────────────────

  /// إرسال حقيبة حظ إلى الغرفة. يعيد `null` عند فشل الخصم أو الحفظ.
  Future<Map<String, dynamic>?> sendLuckyBag({
    required String roomId,
    String type = 'coins',
    String scope = 'room',
    int? value,
    int? count,
    int? totalCoins,
    String? greetingText,
    bool isSuper = false,
    int? durationSeconds,
    String distribution = 'random',
  }) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return null;
      final cfg = await loadConfig();
      if (!cfg.enabled) return null;

      final user = await _ds.getUser(uid);
      if (user == null) return null;

      final int cost = (totalCoins ?? ((value ?? 0) * (count ?? 1))).toInt();
      final int shares = (count ?? cfg.sharesPresets.first).toInt();
      if (cost < cfg.minCoins || cost > cfg.maxCoins) {
        debugPrint('[LuckyBagService] cost $cost outside [${cfg.minCoins}, ${cfg.maxCoins}]');
        return null;
      }
      if (shares < cfg.minShares || shares > cfg.maxBagsPerSend) return null;
      if (cost < shares) return null;
      if (user.coins < cost) return null;

      final int active = await _countActiveInRoom(roomId);
      if (cfg.maxActivePerRoom > 0 && active >= cfg.maxActivePerRoom) {
        debugPrint('[LuckyBagService] room $roomId hit max active bags ($active/${cfg.maxActivePerRoom})');
        return null;
      }

      final duration = (durationSeconds ?? cfg.ttlSeconds).clamp(5, 3600);
      final now = DateTime.now().toUtc();
      final bagId =
          'bag_${now.millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';

      final meta = <String, dynamic>{
        'type': isSuper ? 'super' : type,
        'scope': scope,
        'distribution': distribution,
        'greeting': greetingText ?? cfg.greetings.first,
      };

      final row = <String, dynamic>{
        'id': bagId,
        'room_id': roomId,
        'sender_uid': uid,
        'sender_name': user.name,
        'sender_photo': user.photoUrl,
        'total_count': shares,
        'remaining_count': shares,
        'total_value': cost,
        'remaining_value': cost,
        'claims': {'meta': meta, 'list': <dynamic>[]},
        'status': 'active',
        'created_at': now.toIso8601String(),
        'expires_at': now.add(Duration(seconds: duration)).toIso8601String(),
      };

      // خصم العملات أولاً
      final deducted = await _ds.updateUser(uid, {
        'coins': user.coins - cost,
        'total_gifts_sent': user.totalGiftsSent + cost,
      });
      if (!deducted) return null;

      final saved = await _insertRow(row);
      if (!saved) {
        // إعادة الرصيد عند فشل الحفظ
        await _ds.updateUser(uid, {'coins': user.coins});
        return null;
      }

      final payload = _rowToPayload(row);
      _localBags[bagId] = payload;

      unawaited(_ds.updateRoom(roomId, {'has_lucky_bag': true}).catchError((_) => false));

      unawaited(_ds
          .sendMessage(MessageModel(
            msgId: const Uuid().v4(),
            roomId: roomId,
            senderUid: uid,
            senderName: user.name,
            senderPhotoUrl: user.photoUrl,
            type: 'lucky_bag',
            text: '🧧 أرسل حقيبة حظ بقيمة $cost 🪙 ($shares حقيبة)',
            luckyBagPayload: payload,
            giftPayload: payload,
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ))
          .catchError((_) => false));

      unawaited(GlobalBannerService.instance.recordLuckyBagBroadcast(
        roomId: roomId,
        senderUid: uid,
        senderName: user.name,
        senderPhotoUrl: user.photoUrl,
        totalCoins: cost,
        bagCount: shares,
      ));

      GlobalBannerService.instance.triggerLuckyBagBanner(payload);

      return {
        'success': true,
        'bagId': bagId,
        'bag': payload,
        'expiresAt': row['expires_at'],
      };
    } catch (e) {
      debugPrint('[LuckyBagService] sendLuckyBag error: $e');
      return null;
    }
  }

  // ── الفتح / الالتقاط ───────────────────────────────────

  Future<LuckyBagClaimResult> grabLuckyBag({
    required String roomId,
    String? bagId,
  }) async {
    try {
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) {
        return const LuckyBagClaimResult(success: false, error: 'not_in_room');
      }
      final user = await _ds.getUser(uid);
      if (user == null) {
        return const LuckyBagClaimResult(success: false, error: 'not_in_room');
      }

      final targetBagId = bagId ?? await _latestActiveBagId(roomId);
      if (targetBagId == null) {
        return const LuckyBagClaimResult(success: false, error: 'no_active_bag');
      }

      for (var attempt = 0; attempt < 4; attempt++) {
        final row = await _fetchRow(targetBagId);
        if (row == null) {
          return const LuckyBagClaimResult(success: false, error: 'no_active_bag');
        }

        final meta = luckyBagMetaFromPayload(row['claims']);
        final claims = luckyBagClaimsFromPayload(row['claims']);
        final senderUid = row['sender_uid']?.toString() ?? '';
        final status = row['status']?.toString() ?? 'active';
        final remainingValue = _asInt(row['remaining_value']);
        final remainingCount = _asInt(row['remaining_count']);
        final expiresAt = DateTime.tryParse(row['expires_at']?.toString() ?? '');

        if (status != 'active') {
          return const LuckyBagClaimResult(
            success: false,
            error: 'bag_empty',
          );
        }
        if (expiresAt != null && DateTime.now().toUtc().isAfter(expiresAt)) {
          unawaited(_finalizeExpired(row));
          return const LuckyBagClaimResult(success: false, error: 'bag_expired');
        }
        if (senderUid == uid) {
          return const LuckyBagClaimResult(
            success: false,
            error: 'cannot_claim_own_bag',
          );
        }
        if (claims.any((c) => c['claimer_id']?.toString() == uid)) {
          return const LuckyBagClaimResult(
            success: false,
            error: 'already_claimed',
          );
        }
        if (remainingValue <= 0 || remainingCount <= 0) {
          return const LuckyBagClaimResult(success: false, error: 'bag_empty');
        }

        final wonAmount = _computeShare(
          remainingValue: remainingValue,
          remainingCount: remainingCount,
          distribution: meta['distribution']?.toString() ?? 'random',
        );
        final newRemainingValue = math.max(0, remainingValue - wonAmount);
        final newRemainingCount = math.max(0, remainingCount - 1);
        final isDone = newRemainingValue <= 0 || newRemainingCount <= 0;

        final entry = <String, dynamic>{
          'id': const Uuid().v4(),
          'claimer_id': uid,
          'claimer_name': user.name,
          'claimer_avatar': user.photoUrl,
          'amount': wonAmount,
          'created_at': DateTime.now().toUtc().toIso8601String(),
        };
        final newClaims = <Map<String, dynamic>>[...claims, entry];

        final patched = await _patchRow(
          bagId: targetBagId,
          filters: {
            'status': 'eq.active',
            'remaining_value': 'eq.$remainingValue',
            'remaining_count': 'eq.$remainingCount',
          },
          body: {
            'remaining_value': newRemainingValue,
            'remaining_count': newRemainingCount,
            // القيد في قاعدة البيانات يسمح فقط بـ active/claimed/expired
            'status': isDone ? 'claimed' : 'active',
            'claims': {'meta': meta, 'list': newClaims},
          },
        );

        if (patched == null) continue; // سباق: أعد المحاولة

        // تحديث النسخة المحلية حتى يختفي الكيس من الواجهة فور اكتماله
        if (isDone) {
          _localBags.remove(targetBagId);
        } else {
          final local = _localBags[targetBagId];
          if (local != null) {
            local['remaining_value'] = newRemainingValue;
            local['remaining_count'] = newRemainingCount;
            local['claims'] = {'meta': meta, 'list': newClaims};
            local['claimed_shares'] = newClaims.length;
          }
        }

        // إيداع الجائزة
        await _ds.updateUser(uid, {'coins': user.coins + wonAmount});
        if (isDone) {
          unawaited(_refreshRoomBagFlag(roomId));
        }

        unawaited(_ds
            .sendMessage(MessageModel(
              msgId: const Uuid().v4(),
              roomId: roomId,
              senderUid: uid,
              senderName: user.name,
              senderPhotoUrl: user.photoUrl,
              type: 'lucky_win',
              text: '🎉 $wonAmount 🪙 من حقيبة الحظ!',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ))
            .catchError((_) => false));

        return LuckyBagClaimResult(
          success: true,
          bagId: targetBagId,
          amount: wonAmount,
          remaining: newRemainingValue,
          isDone: isDone,
        );
      }
    } catch (e) {
      debugPrint('[LuckyBagService] grabLuckyBag error: $e');
    }
    return const LuckyBagClaimResult(success: false, error: 'network_error');
  }

  /// جلب تفاصيل الحقيبة وقائمة الفائزين مباشرة من قاعدة البيانات.
  Future<Map<String, dynamic>?> getLuckyBagDetails(String bagId) async {
    try {
      final row = await _fetchRow(bagId);
      if (row == null) return null;
      return {
        'success': true,
        'bag': _rowToPayload(row),
        'claims': luckyBagClaimsFromPayload(row['claims']),
      };
    } catch (e) {
      debugPrint('[LuckyBagService] getLuckyBagDetails error: $e');
    }
    return null;
  }

  /// تسجيل حقيبة مستلمة من رسائل الغرفة لإظهارها فوراً.
  void registerActiveBag(String bagId, Map<String, dynamic> bagPayload) {
    final status = bagPayload['status']?.toString() ?? 'active';
    if (status == 'active') {
      _localBags[bagId] = Map<String, dynamic>.from(bagPayload);
    }
  }

  // ── البث المباشر للأكياس النشطة ────────────────────────

  Stream<List<LuckyBagModel>> activeBagsStream(String roomId) async* {
    while (true) {
      List<LuckyBagModel> bags = [];
      try {
        final now = Uri.encodeComponent(DateTime.now().toUtc().toIso8601String());
        final url = Uri.parse(
          '$_baseUrl/rest/v1/lucky_bags?room_id=eq.$roomId&status=eq.active'
          '&expires_at=gt.$now&select=*&order=created_at.asc&limit=20',
        );
        final res = await http.get(url, headers: _headers).timeout(
              const Duration(seconds: 6),
            );
        if (res.statusCode == 200) {
          final list = jsonDecode(res.body);
          if (list is List) {
            bags = list
                .whereType<Map>()
                .map((e) => LuckyBagModel.fromJson(_rowToPayload(e)))
                .where((b) => b.bagId.isNotEmpty && b.remainingCount > 0)
                .toList();
          }
        }
      } catch (e) {
        debugPrint('[LuckyBagService] activeBagsStream error: $e');
      }

      // دمج الحقائب المحلية (إرسال فوري قبل وصول الاستعلام)
      final merged = <String, LuckyBagModel>{for (final b in bags) b.bagId: b};
      for (final local in _localBags.values) {
        if (local['room_id']?.toString() != roomId) continue;
        if (local['status']?.toString() != 'active') continue;
        final model = LuckyBagModel.fromJson(local);
        final expires = DateTime.tryParse(model.expiresAt ?? '');
        if (expires != null && DateTime.now().toUtc().isAfter(expires)) continue;
        merged.putIfAbsent(model.bagId, () => model);
      }

      final result = merged.values.toList()
        ..sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
      yield result;
      await Future.delayed(const Duration(milliseconds: 1000));
    }
  }

  // ── مراقب انتهاء الصلاحية واسترداد المتبقي ─────────────

  void startExpiryWatcher() {
    if (_expiryTimer != null) return;
    _expiryTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _processExpired(),
    );
    unawaited(_processExpired());
  }

  Future<void> _processExpired() async {
    if (_processingExpiry) return;
    _processingExpiry = true;
    try {
      final now = Uri.encodeComponent(DateTime.now().toUtc().toIso8601String());
      final url = Uri.parse(
        '$_baseUrl/rest/v1/lucky_bags?status=eq.active&expires_at=lt.$now&select=*&limit=25',
      );
      final res = await http.get(url, headers: _headers).timeout(
            const Duration(seconds: 8),
          );
      if (res.statusCode != 200) return;
      final list = jsonDecode(res.body);
      if (list is! List) return;
      for (final item in list.whereType<Map>()) {
        await _finalizeExpired(Map<String, dynamic>.from(item));
      }
    } catch (e) {
      debugPrint('[LuckyBagService] processExpired error: $e');
    } finally {
      _processingExpiry = false;
    }
  }

  /// إنهاء الحقيبة واسترداد المتبقي للمرسل (يعمل مرة واحدة فقط بفضل شرط status).
  Future<void> _finalizeExpired(Map<String, dynamic> row) async {
    final bagId = row['id']?.toString() ?? '';
    if (bagId.isEmpty) return;
    final senderUid = row['sender_uid']?.toString() ?? '';
    final roomId = row['room_id']?.toString() ?? '';
    final remainingValue = _asInt(row['remaining_value']);
    final remainingCount = _asInt(row['remaining_count']);
    final meta = luckyBagMetaFromPayload(row['claims']);
    final claims = luckyBagClaimsFromPayload(row['claims']);

    final patched = await _patchRow(
      bagId: bagId,
      filters: {'status': 'eq.active'},
      body: {
        'status': 'expired',
        'remaining_value': 0,
        'remaining_count': 0,
        'claims': {'meta': meta, 'list': claims},
      },
    );
    if (patched == null) return; // حُسمت من جهاز آخر

    _localBags.remove(bagId);

    if (remainingValue > 0 && senderUid.isNotEmpty) {
      try {
        final sender = await _ds.getUser(senderUid);
        if (sender != null) {
          await _ds.updateUser(senderUid, {
            'coins': sender.coins + remainingValue,
          });
        }
      } catch (e) {
        debugPrint('[LuckyBagService] refund error: $e');
      }

      if (roomId.isNotEmpty) {
        unawaited(_ds
            .sendMessage(MessageModel(
              msgId: const Uuid().v4(),
              roomId: roomId,
              senderUid: 'system',
              senderName: 'نظام',
              senderPhotoUrl: '',
              type: 'system',
              text:
                  '⏰ انتهى وقت حقيبة الحظ، وأُعيد $remainingValue 🪙 إلى المرسل'
                  '${remainingCount > 0 ? ' ($remainingCount حقيبة لم تُفتح)' : ''}',
              timestamp: DateTime.now().millisecondsSinceEpoch,
            ))
            .catchError((_) => false));
      }
    }

    if (roomId.isNotEmpty) {
      unawaited(_refreshRoomBagFlag(roomId));
    }
  }

  // ── أدوات مساعدة ───────────────────────────────────────

  int _computeShare({
    required int remainingValue,
    required int remainingCount,
    required String distribution,
  }) {
    if (remainingCount <= 1) return remainingValue;
    if (distribution == 'equal') {
      return math.max(1, remainingValue ~/ remainingCount);
    }
    final avg = remainingValue ~/ remainingCount;
    final variance = (avg * 0.45).round();
    final delta = variance <= 0
        ? 0
        : math.Random().nextInt(variance * 2 + 1) - variance;
    return math.max(1, math.min(remainingValue, avg + delta));
  }

  Future<int> _countActiveInRoom(String roomId) async {
    try {
      final now = Uri.encodeComponent(DateTime.now().toUtc().toIso8601String());
      final url = Uri.parse(
        '$_baseUrl/rest/v1/lucky_bags?room_id=eq.$roomId&status=eq.active'
        '&expires_at=gt.$now&select=id',
      );
      final res = await http.get(url, headers: _headers).timeout(
            const Duration(seconds: 6),
          );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List) return list.length;
      }
    } catch (_) {}
    return 0;
  }

  Future<String?> _latestActiveBagId(String roomId) async {
    try {
      final now = Uri.encodeComponent(DateTime.now().toUtc().toIso8601String());
      final url = Uri.parse(
        '$_baseUrl/rest/v1/lucky_bags?room_id=eq.$roomId&status=eq.active'
        '&expires_at=gt.$now&select=id&order=created_at.asc&limit=1',
      );
      final res = await http.get(url, headers: _headers).timeout(
            const Duration(seconds: 6),
          );
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          return (list.first as Map)['id']?.toString();
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Map<String, dynamic>?> _fetchRow(String bagId) async {
    final url = Uri.parse(
      '$_baseUrl/rest/v1/lucky_bags?id=eq.$bagId&select=*&limit=1',
    );
    final res = await http.get(url, headers: _headers).timeout(
          const Duration(seconds: 8),
        );
    if (res.statusCode != 200) return null;
    final list = jsonDecode(res.body);
    if (list is List && list.isNotEmpty) {
      return Map<String, dynamic>.from(list.first as Map);
    }
    return null;
  }

  Future<bool> _insertRow(Map<String, dynamic> row) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/rest/v1/lucky_bags'),
            headers: {..._headers, 'Prefer': 'return=representation'},
            body: jsonEncode(row),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      debugPrint('[LuckyBagService] insert ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('[LuckyBagService] insert error: $e');
    }
    return false;
  }

  Future<Map<String, dynamic>?> _patchRow({
    required String bagId,
    required Map<String, String> filters,
    required Map<String, dynamic> body,
  }) async {
    try {
      final query = StringBuffer('id=eq.$bagId');
      filters.forEach((k, v) => query.write('&$k=$v'));
      final res = await http
          .patch(
            Uri.parse('$_baseUrl/rest/v1/lucky_bags?$query'),
            headers: {..._headers, 'Prefer': 'return=representation'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final list = jsonDecode(res.body);
        if (list is List && list.isNotEmpty) {
          return Map<String, dynamic>.from(list.first as Map);
        }
        return null;
      }
      debugPrint('[LuckyBagService] patch ${res.statusCode}: ${res.body}');
    } catch (e) {
      debugPrint('[LuckyBagService] patch error: $e');
    }
    return null;
  }

  Future<void> _refreshRoomBagFlag(String roomId) async {
    try {
      final now = Uri.encodeComponent(DateTime.now().toUtc().toIso8601String());
      final url = Uri.parse(
        '$_baseUrl/rest/v1/lucky_bags?room_id=eq.$roomId&status=eq.active'
        '&expires_at=gt.$now&select=id',
      );
      final res = await http.get(url, headers: _headers).timeout(
            const Duration(seconds: 6),
          );
      final has = res.statusCode == 200 &&
          (jsonDecode(res.body) as List).isNotEmpty;
      await _ds.updateRoom(roomId, {'has_lucky_bag': has});
    } catch (_) {}
  }

  Map<String, dynamic> _rowToPayload(Map row) {
    final claims = luckyBagClaimsFromPayload(row['claims']);
    final meta = luckyBagMetaFromPayload(row['claims']);
    final id = row['id']?.toString() ?? '';
    final total = _asInt(row['total_count']);
    final remaining = _asInt(row['remaining_count']);
    final senderPhoto = row['sender_photo']?.toString() ?? '';

    return <String, dynamic>{
      ...Map<String, dynamic>.from(row),
      'bagId': id,
      'bag_id': id,
      'roomId': row['room_id']?.toString() ?? '',
      'ownerId': row['sender_uid']?.toString() ?? '',
      'owner_id': row['sender_uid']?.toString() ?? '',
      'ownerName': row['sender_name']?.toString() ?? '',
      'owner_name': row['sender_name']?.toString() ?? '',
      'ownerAvatar': senderPhoto,
      'owner_photo': senderPhoto,
      'type': meta['type']?.toString() ?? 'coins',
      'scope': meta['scope']?.toString() ?? 'room',
      'distribution': meta['distribution']?.toString() ?? 'random',
      'greeting_text': meta['greeting']?.toString() ?? '',
      'total_shares': total,
      'total_bags': total,
      'remaining_count': remaining,
      'claimed_shares': claims.length,
    };
  }

  int _asInt(dynamic v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  // ── عرض إشعار الالتقاط السريع ─────────────────────────

  OverlayEntry? _grabOverlay;

  void showGrabBanner(
    BuildContext context, {
    required String roomId,
    required LuckyBagModel bag,
    required VoidCallback onOpenDialog,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    _grabOverlay?.remove();
    _grabOverlay = OverlayEntry(
      builder: (ctx) => LuckyBagGrabOverlay(
        bag: bag,
        onTapOpen: () {
          _hideGrabBanner();
          onOpenDialog();
        },
        onGrab: () async {
          final result = await grabLuckyBag(
            roomId: roomId,
            bagId: bag.bagId,
          );
          if (!ctx.mounted) return;
          _showGrabResult(ctx, result);
          if (result.success) _hideGrabBanner();
        },
      ),
    );
    overlay.insert(_grabOverlay!);
  }

  void _hideGrabBanner() {
    _grabOverlay?.remove();
    _grabOverlay = null;
  }

  void _showGrabResult(BuildContext context, LuckyBagClaimResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: DText(
          result.success
              ? '🎉 مبروك! حصلت على ${result.amount} 🪙 من حقيبة الحظ'
              : '⚠️ ${_friendlyGrabError(result.error ?? '')}',
        ),
        duration: const Duration(seconds: 3),
        backgroundColor:
            result.success ? const Color(0xFF2E7D32) : const Color(0xFF7A3B00),
      ),
    );
  }

  String _friendlyGrabError(String code) {
    switch (code) {
      case 'cannot_claim_own_bag':
        return 'لا يمكنك فتح حقيبة أرسلتها بنفسك';
      case 'already_claimed':
        return 'لقد فتحت هذه الحقيبة مسبقاً!';
      case 'mic_only':
        return 'هذه الحقيبة مخصصة للمتواجدين على المايك فقط';
      case 'not_in_room':
        return 'يجب أن تكون داخل الغرفة للمشاركة';
      case 'bag_expired':
        return 'انتهت صلاحية هذه الحقيبة';
      case 'bag_empty':
        return 'تم توزيع كافة الأنصبة بالكامل!';
      case 'no_active_bag':
        return 'لا توجد حقائب نشطة حالياً';
      case 'rate_limited':
        return 'تمهل قليلاً وحاول مجدداً';
      default:
        return 'تعذر فتح الحقيبة، ربما نفذت الحصص';
    }
  }

  void dispose() {
    _grabOverlay?.remove();
    _grabOverlay = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }
}
