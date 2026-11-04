/// إعدادات حقيبة الحظ القادمة من لوحة التحكم (`app_config.lucky_bag_config`).
class LuckyBagConfig {
  final bool enabled;
  final int ttlSeconds;
  final int minCoins;
  final int maxCoins;
  final int minShares;
  final int maxShares;
  final int maxBagsPerSend;
  final int maxActivePerRoom;
  final List<int> amountPresets;
  final List<int> sharesPresets;
  final List<int> durationPresets;
  final List<String> greetings;
  final String bagImage;
  final String panelBackground;
  final String primaryColor;
  final String secondaryColor;
  final String countdownColor;

  const LuckyBagConfig({
    this.enabled = true,
    this.ttlSeconds = 30,
    this.minCoins = 100,
    this.maxCoins = 1000000,
    this.minShares = 2,
    this.maxShares = 200,
    this.maxBagsPerSend = 200,
    this.maxActivePerRoom = 3,
    this.amountPresets = const [500, 1000, 2000, 5000, 10000, 20000],
    this.sharesPresets = const [5, 10, 15, 20, 30, 50],
    this.durationPresets = const [10, 30, 240, 600],
    this.greetings = const [
      'حظ سعيد للجميع ✨',
      'مبروك وموفقين 🎁',
      'كل عام وأنتم بخير 🌙',
    ],
    this.bagImage = '',
    this.panelBackground = '',
    this.primaryColor = '#FFF295',
    this.secondaryColor = '#134015',
    this.countdownColor = '#000000',
  });

  Duration get ttl => Duration(seconds: ttlSeconds);

  factory LuckyBagConfig.fromJson(Map<String, dynamic> json) {
    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    List<int> asIntList(dynamic v) {
      if (v is List) {
        return v
            .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()))
            .whereType<int>()
            .where((e) => e > 0)
            .toList();
      }
      if (v is String) {
        return v
            .split(',')
            .map((e) => int.tryParse(e.trim()))
            .whereType<int>()
            .where((e) => e > 0)
            .toList();
      }
      return const [];
    }

    List<String> asStringList(dynamic v) {
      if (v is List) {
        return v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
      }
      return const [];
    }

    String asString(dynamic v, String fallback) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty ? fallback : s;
    }

    final raw = Map<String, dynamic>.from(json);

    return LuckyBagConfig(
      enabled: raw['enabled'] != false,
      ttlSeconds: (asInt(raw['ttl_seconds']) ?? 30).clamp(5, 3600),
      minCoins: asInt(raw['min_coins']) ?? 100,
      maxCoins: asInt(raw['max_coins']) ?? 1000000,
      minShares: asInt(raw['min_shares']) ?? 2,
      maxShares: asInt(raw['max_shares']) ?? 200,
      maxBagsPerSend:
          asInt(raw['max_bags_per_send']) ?? asInt(raw['max_shares']) ?? 200,
      maxActivePerRoom: asInt(raw['max_active_per_room']) ?? 3,
      amountPresets: asIntList(raw['amount_presets']).isEmpty
          ? const [500, 1000, 2000, 5000, 10000, 20000]
          : asIntList(raw['amount_presets']),
      sharesPresets: asIntList(raw['shares_presets']).isEmpty
          ? const [5, 10, 15, 20, 30, 50]
          : asIntList(raw['shares_presets']),
      durationPresets: asIntList(raw['duration_presets']).isEmpty
          ? const [10, 30, 240, 600]
          : asIntList(raw['duration_presets']),
      greetings: asStringList(raw['greetings']).isEmpty
          ? const ['حظ سعيد للجميع ✨']
          : asStringList(raw['greetings']),
      bagImage: asString(raw['bag_image'], ''),
      panelBackground: asString(raw['panel_background'], ''),
      primaryColor: asString(raw['primary_color'], '#FFF295'),
      secondaryColor: asString(raw['secondary_color'], '#134015'),
      countdownColor: asString(raw['countdown_color'], '#000000'),
    );
  }
}
