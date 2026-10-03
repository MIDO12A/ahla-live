import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/api_service.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/supabase_service.dart';
import '../../services/supabase_data_service.dart';
import '../../core/supabase_compat.dart';
import '../../features/events/screens/recharge_event_screen.dart';

class WalletMainScreen extends StatefulWidget {
  const WalletMainScreen({super.key});

  @override
  State<WalletMainScreen> createState() => _WalletMainScreenState();
}

class _WalletMainScreenState extends State<WalletMainScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _api = ApiService();
  List<Map<String, dynamic>> _coinPlans = [];
  List<Map<String, dynamic>> _diamondPlans = [];
  bool _loadingPlans = true;

  final Map<String, dynamic> _gatewayConfig = {
    'googlePlayEnabled': true,
    'vodafoneCashEnabled': true,
    'vodafoneCashNumber': '01000000000',
    'vodafoneCashInstructions': 'حول المبلغ المطلوب لرقم فودافون كاش ثم اضغط تأكيد.',
    'binanceEnabled': true,
    'binanceId': '84920193',
    'binanceAddress': 'Txxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx',
    'binanceInstructions': 'أرسل USDT (TRC-20) للعنوان الموضح أو استخدم Binance Pay ID.',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      // 1. Fetch live plans and gateways from Supabase / Firestore app_config
      try {
        final config = await SupabaseDataService().getAppConfig();
        dynamic plansRaw = config['recharge_plans'];
        dynamic gwRaw = config['recharge_gateways'];

        if (plansRaw == null) {
          plansRaw = await FirebaseService().getAppConfig('recharge_plans');
        }
        if (gwRaw == null) {
          gwRaw = await FirebaseService().getAppConfig('recharge_gateways');
        }

        if (plansRaw != null) {
          final List list = (plansRaw is String) ? jsonDecode(plansRaw) : (plansRaw as List);
          if (list.isNotEmpty) {
            final parsed = list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
            if (mounted) {
              setState(() {
                _coinPlans = parsed.where((p) => (p['currency'] ?? 'coins') == 'coins').toList();
                _diamondPlans = parsed.where((p) => (p['currency'] ?? 'diamonds') == 'diamonds').toList();
              });
            }
          }
        }

        if (gwRaw != null) {
          final Map map = (gwRaw is String) ? jsonDecode(gwRaw) : (gwRaw as Map);
          _gatewayConfig.addAll(Map<String, dynamic>.from(map));
        }
      } catch (e) {
        debugPrint('Failed to load recharge config: $e');
      }

      // If empty, fetch from API or default tiers
      if (_coinPlans.isEmpty) {
        final plans = await _api.getRechargePlans();
        if (plans.isNotEmpty && mounted) {
          setState(() {
            _coinPlans = plans.where((p) => (p['currency'] ?? 'coins') == 'coins').toList();
            _diamondPlans = plans.where((p) => (p['currency'] ?? 'diamonds') == 'diamonds').toList();
          });
        }
      }

      // Fallback default tiers
      if (_coinPlans.isEmpty && mounted) {
        setState(() {
          _coinPlans = [
            {'id': 1, 'amount': 1000, 'price': 1.0, 'bonus': 0, 'currency': 'coins'},
            {'id': 2, 'amount': 5000, 'price': 5.0, 'bonus': 200, 'currency': 'coins'},
            {'id': 3, 'amount': 10000, 'price': 10.0, 'bonus': 500, 'currency': 'coins'},
            {'id': 4, 'amount': 50000, 'price': 50.0, 'bonus': 3000, 'currency': 'coins'},
            {'id': 5, 'amount': 100000, 'price': 100.0, 'bonus': 8000, 'currency': 'coins'},
          ];
          _diamondPlans = [
            {'id': 101, 'amount': 1000, 'price': 1.0, 'bonus': 0, 'currency': 'diamonds'},
            {'id': 102, 'amount': 5000, 'price': 5.0, 'bonus': 0, 'currency': 'diamonds'},
            {'id': 103, 'amount': 10000, 'price': 10.0, 'bonus': 0, 'currency': 'diamonds'},
          ];
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingPlans = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final userProvider = Provider.of<UserProvider>(context);
    final user = userProvider.currentUser;
    final coins = user?.coins ?? 0;
    final diamonds = user?.diamonds ?? 0;
    final dc = DynamicConfigService();

    return ListenableBuilder(
      listenable: dc,
      builder: (context, _) {
        final dc = DynamicConfigService();
        return Scaffold(
          backgroundColor: dc.primaryBg,
          body: Stack(
            children: [
              Positioned.fill(
                child: R.loadAsset(
                  dc.walletBackgroundImage.isNotEmpty
                      ? dc.walletBackgroundImage
                      : R.mineWalletHeaderBg,
                  fit: BoxFit.cover,
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        if (dc.walletHeaderBgImage.isNotEmpty)
                          Positioned.fill(
                            child: R.loadAsset(dc.walletHeaderBgImage, fit: BoxFit.cover),
                          ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () => Navigator.pop(context),
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: R.image(R.backWhite, width: 24, height: 24),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                dc.screenTitles['wallet'] ?? 'المحفظة',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: dc.walletHeaderTextColor,
                                ),
                              ),
                              const Spacer(),
                              GestureDetector(
                                onTap: () {},
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: R.image(R.mineWalletFilterIc, width: 24, height: 24),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Container(
                      color: dc.walletSectionBgImage.isNotEmpty ? null : dc.tabBarColor,
                      decoration: dc.walletSectionBgImage.isNotEmpty
                          ? BoxDecoration(image: DecorationImage(image: R.cachedImage(dc.walletSectionBgImage), fit: BoxFit.cover))
                          : null,
                      child: TabBar(
                        controller: _tabController,
                        labelColor: dc.walletAccentColor,
                        unselectedLabelColor: dc.walletSubTextColor,
                        indicatorColor: dc.walletAccentColor,
                        tabs: [
                          Tab(text: dc.getScreenTitle('coins', 'Coins')),
                          Tab(text: dc.getScreenTitle('diamonds', 'Diamonds')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _loadingPlans
                          ? const Center(child: CircularProgressIndicator())
                          : TabBarView(
                              controller: _tabController,
                              children: [
                                _buildRechargeSection(coins, true),
                                _buildRechargeSection(diamonds, false),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _onRecharge(Map<String, dynamic> plan, bool isCoins) async {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    final amount = (plan['amount'] as int?) ?? 0;
    final price = plan['price']?.toString() ?? '1.0';
    final currencyLabel = isCoins ? 'عملة ذهبية' : 'ألماس';
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1D2A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isAr ? 'اختر طريقة الشحن' : 'Select Payment Gateway',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        isAr ? 'شحن $amount $currencyLabel مقابل \$$price' : 'Recharge $amount $currencyLabel for \$$price',
                        style: const TextStyle(fontSize: 13, color: Color(0xFFFFD54F)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.close, color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Google Play
            if (_gatewayConfig['googlePlayEnabled'] != false)
              _buildGatewayTile(
                icon: Icons.shop_two_outlined,
                iconColor: const Color(0xFF10B981),
                title: 'Google Play Billing',
                subtitle: isAr ? 'الشحن المباشر عبر متجر Google Play' : 'In-App Purchase via Google Play',
                onTap: () {
                  Navigator.pop(ctx);
                  _processGooglePlayRecharge(plan, isCoins);
                },
              ),

            // 2. Vodafone Cash
            if (_gatewayConfig['vodafoneCashEnabled'] != false) ...[
              const SizedBox(height: 10),
              _buildGatewayTile(
                icon: Icons.phone_android_rounded,
                iconColor: const Color(0xFFE60000),
                title: 'Vodafone Cash / فودافون كاش',
                subtitle: isAr ? 'تحويل مباشر لمحفظة فودافون كاش' : 'Direct transfer to Vodafone Cash wallet',
                onTap: () {
                  Navigator.pop(ctx);
                  _showVodafoneCashDialog(plan, isCoins);
                },
              ),
            ],

            // 3. Binance Pay
            if (_gatewayConfig['binanceEnabled'] != false) ...[
              const SizedBox(height: 10),
              _buildGatewayTile(
                icon: Icons.currency_bitcoin,
                iconColor: const Color(0xFFF3BA2F),
                title: 'Binance Pay / USDT Crypto',
                subtitle: isAr ? 'دفع عبر بينانس باي أو شبكة TRC-20' : 'Binance Pay or TRC-20 USDT transfer',
                onTap: () {
                  Navigator.pop(ctx);
                  _showBinancePayDialog(plan, isCoins);
                },
              ),
            ],
            SizedBox(height: MediaQuery.of(context).padding.bottom + 12),
          ],
        ),
      ),
    );
  }

  Widget _buildGatewayTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF262534),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white38, size: 14),
          ],
        ),
      ),
    );
  }

  Future<void> _processGooglePlayRecharge(Map<String, dynamic> plan, bool isCoins) async {
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    final amount = (plan['amount'] as int?) ?? 0;
    final price = plan['price']?.toString() ?? '1.0';
    final currency = isCoins ? 'coins' : 'diamonds';
    final isAr = Localizations.localeOf(context).languageCode == 'ar';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1D2A),
        title: Text(isAr ? 'شحن عبر Google Play' : 'Google Play Billing', style: const TextStyle(color: Colors.white)),
        content: Text(
          isAr ? 'هل تريد شحن $amount $currency مقابل \$$price عبر Google Play؟' : 'Purchase $amount $currency for \$$price via Google Play?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDE880F)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isAr ? 'موافق والدفع' : 'Pay Now', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _creditRecharge(user.uid, amount, isCoins);
    }
  }

  void _showVodafoneCashDialog(Map<String, dynamic> plan, bool isCoins) {
    final amount = (plan['amount'] as int?) ?? 0;
    final price = plan['price']?.toString() ?? '1.0';
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final walletNumber = (_gatewayConfig['vodafoneCashNumber'] ?? '01000000000').toString();
    final instructions = (_gatewayConfig['vodafoneCashInstructions'] ?? '').toString();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1D2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.phone_android, color: Color(0xFFE60000)),
            const SizedBox(width: 8),
            Text(isAr ? 'فودافون كاش' : 'Vodafone Cash', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr ? 'المبلغ المطلوب: \$$price (شحن $amount عملة)' : 'Amount: \$$price (Recharge $amount coins)',
                style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(isAr ? 'رقم محفظة التحويل' : 'Wallet Number', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                          const SizedBox(height: 2),
                          SelectableText(
                            walletNumber,
                            style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Color(0xFFFFD54F), size: 20),
                      tooltip: 'Copy',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: walletNumber));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isAr ? 'تم نسخ الرقم بنجاح' : 'Number copied!'), duration: const Duration(seconds: 1)),
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (instructions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(instructions, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
              const SizedBox(height: 14),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: isAr ? 'رقم الهاتف المحول منه أو رقم العملية' : 'Sender Phone or Transaction ID',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFE60000)),
            onPressed: () async {
              final ref = phoneCtrl.text.trim();
              if (ref.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isAr ? 'يرجى إدخال رقم الهاتف أو رقم العملية' : 'Please enter reference number')),
                );
                return;
              }
              Navigator.pop(ctx);
              final user = context.read<UserProvider>().currentUser;
              if (user != null) {
                await _creditRecharge(user.uid, amount, isCoins);
              }
            },
            child: Text(isAr ? 'تأكيد التحويل' : 'Confirm', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showBinancePayDialog(Map<String, dynamic> plan, bool isCoins) {
    final amount = (plan['amount'] as int?) ?? 0;
    final price = plan['price']?.toString() ?? '1.0';
    final isAr = Localizations.localeOf(context).languageCode == 'ar';
    final binanceId = (_gatewayConfig['binanceId'] ?? '').toString();
    final binanceAddress = (_gatewayConfig['binanceAddress'] ?? '').toString();
    final instructions = (_gatewayConfig['binanceInstructions'] ?? '').toString();
    final txCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1D2A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            const Icon(Icons.currency_bitcoin, color: Color(0xFFF3BA2F)),
            const SizedBox(width: 8),
            Text(isAr ? 'Binance Pay / USDT' : 'Binance Pay / USDT', style: const TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isAr ? 'المطلوب: \$$price USDT (شحن $amount عملة)' : 'Amount: \$$price USDT (Recharge $amount coins)',
                style: const TextStyle(color: Color(0xFFFFD54F), fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (binanceId.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Binance Pay ID', style: TextStyle(color: Colors.white54, fontSize: 10)),
                            SelectableText(binanceId, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Color(0xFFFFD54F), size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: binanceId));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isAr ? 'تم نسخ معرف Binance' : 'Binance ID copied!'), duration: const Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              if (binanceAddress.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('USDT (TRC-20) Address', style: TextStyle(color: Colors.white54, fontSize: 10)),
                            SelectableText(binanceAddress, style: const TextStyle(color: Colors.white, fontSize: 11, fontFamily: 'monospace')),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy, color: Color(0xFFFFD54F), size: 18),
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: binanceAddress));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isAr ? 'تم نسخ العنوان' : 'Address copied!'), duration: const Duration(seconds: 1)),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              if (instructions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(instructions, style: const TextStyle(color: Colors.white70, fontSize: 11)),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: txCtrl,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  hintText: isAr ? 'أدخل رقم المعاملة (TxID)' : 'Enter TxID / Transaction Hash',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Colors.black26,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(isAr ? 'إلغاء' : 'Cancel', style: const TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF3BA2F)),
            onPressed: () async {
              final tx = txCtrl.text.trim();
              if (tx.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(isAr ? 'يرجى إدخال رقم المعاملة' : 'Please enter TxID')),
                );
                return;
              }
              Navigator.pop(ctx);
              final user = context.read<UserProvider>().currentUser;
              if (user != null) {
                await _creditRecharge(user.uid, amount, isCoins);
              }
            },
            child: Text(isAr ? 'تأكيد الدفع' : 'Confirm', style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _creditRecharge(String uid, int amount, bool isCoins) async {
    try {
      if (isCoins) {
        await SupabaseService().addCoins(uid, amount);
      } else {
        final currentDiamonds = context.read<UserProvider>().currentUser?.diamonds ?? 0;
        await Supabase.instance.client.from('users').update({
          'diamonds': currentDiamonds + amount,
        }).eq('uid', uid);
      }
      if (!mounted) return;
      await context.read<UserProvider>().loadUser(uid);
      if (mounted) {
        final isAr = Localizations.localeOf(context).languageCode == 'ar';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAr ? 'تم شحن +$amount بنجاح!' : '+$amount added successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  int _exchangeDiamondAmount = 0;
  bool _exchanging = false;

  Widget _buildExchangeSection(DynamicConfigService dc, int balance) {
    final rate = dc.diamondToCoinRate;
    final maxExchange = (balance ~/ rate) * rate;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dc.walletCardBgColor.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(dc.borderRadius.toDouble()),
        border: Border.all(color: dc.walletCardBorderColor.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              R.image(R.commonDiamondIc, width: 20, height: 20),
              const SizedBox(width: 8),
              Text('تبديل الألماس → كوينز',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: dc.walletTextColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('المعدل: $rate ألماس = 1 كوين',
            style: TextStyle(fontSize: 13, color: dc.walletSubTextColor),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'عدد الألماس',
                    hintStyle: TextStyle(color: dc.walletSubTextColor.withValues(alpha: 0.5)),
                    filled: true,
                    fillColor: dc.walletCardBgColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  style: TextStyle(color: dc.walletTextColor),
                  onChanged: (v) => setState(() => _exchangeDiamondAmount = int.tryParse(v) ?? 0),
                ),
              ),
              const SizedBox(width: 12),
              if (_exchangeDiamondAmount >= rate)
                Text('= ${_exchangeDiamondAmount ~/ rate} كوينز',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: dc.goldColor),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [rate * 10, rate * 50, rate * 100, rate * 500].map((a) {
              if (a > maxExchange) return const SizedBox.shrink();
              return GestureDetector(
                onTap: () => setState(() => _exchangeDiamondAmount = a),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _exchangeDiamondAmount == a ? dc.walletAccentColor : dc.walletCardBgColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: dc.walletAccentColor.withValues(alpha: 0.5)),
                  ),
                  child: Text('$a ♦', style: TextStyle(fontSize: 12, color: _exchangeDiamondAmount == a ? Colors.white : dc.walletTextColor)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _exchangeDiamondAmount >= rate && !_exchanging
                  ? () => _doExchange(dc)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: dc.walletAccentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _exchanging
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text('تبديل', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: dc.walletTextColor)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doExchange(DynamicConfigService dc) async {
    final userProvider = context.read<UserProvider>();
    final user = userProvider.currentUser;
    if (user == null) return;
    setState(() => _exchanging = true);
    try {
      final svc = SupabaseService();
      final result = await svc.exchangeDiamondsToCoins(
        uid: user.uid,
        diamonds: _exchangeDiamondAmount,
        rate: dc.diamondToCoinRate,
      );
      if (result.success) {
        await userProvider.loadUser(user.uid);
        if (mounted) {
          setState(() {
            _exchangeDiamondAmount = 0;
            _exchanging = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('+${result.coinsReceived} كوينز!'), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) {
          setState(() => _exchanging = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result.error ?? 'فشل التبادل'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _exchanging = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildRechargeSection(int balance, bool isCoins) {
    final dc = DynamicConfigService();
    final plans = isCoins ? _coinPlans : _diamondPlans;
    final icon = isCoins ? R.commonGoldIc3 : R.commonDiamondIc;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: dc.walletAccentImage.isNotEmpty ? null : (isCoins ? dc.walletAccentColor.withValues(alpha: 0.1) : dc.walletAccentColor.withValues(alpha: 0.1)),
              borderRadius: BorderRadius.circular(dc.borderRadius.toDouble()),
              image: dc.walletAccentImage.isNotEmpty
                  ? DecorationImage(image: R.cachedImage(dc.walletAccentImage), fit: BoxFit.cover)
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    R.image(icon, width: 32, height: 32),
                    const SizedBox(width: 8),
                    Text(
                      '$balance',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: isCoins ? dc.goldColor : dc.buttonColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Recharge Event Banner
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const RechargeEventScreen(),
                ),
              );
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2C1E0F), Color(0xFF1A1326), Color(0xFF0E0B16)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD700).withValues(alpha: 0.6), width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF9800).withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Royal Item Frame Preview
                  SizedBox(
                    width: 46,
                    height: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Image.asset(
                          'assets/recharge_event/recharge_remind_item_bg.webp',
                          width: 46,
                          height: 52,
                          fit: BoxFit.fill,
                        ),
                        Image.asset(
                          'assets/recharge_event/100K.png',
                          width: 28,
                          height: 28,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Icon(Icons.workspace_premium, color: Colors.amber, size: 24),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '👑 حدث الشحن الملكي الأسطوري',
                          style: TextStyle(
                            color: Color(0xFFFFD700),
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'اشحن كوينز وافتح 14 مستوى من الجوائز ومؤثرات SVGA!',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFFB300), Color(0xFFFF8F00)],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [BoxShadow(color: Color(0x66FF8F00), blurRadius: 4)],
                    ),
                    child: const Text(
                      'دخول ⚡',
                      style: TextStyle(
                        color: Color(0xFF441200),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!isCoins) _buildExchangeSection(dc, balance),
          Text(
            dc.getScreenTitle('recharge', 'Recharge'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: dc.walletTextColor,
            ),
          ),
          const SizedBox(height: 12),
          if (plans.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No plans available', style: TextStyle(color: dc.walletSubTextColor)),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.2,
              ),
              itemCount: plans.length,
              itemBuilder: (context, index) {
                final plan = plans[index];
                final amount = plan['amount'] as int? ?? 0;
                final price = plan['price']?.toString() ?? '\$--';
                final bonus = plan['bonus']?.toString() ?? '';
                return GestureDetector(
                  onTap: () => _onRecharge(plan, isCoins),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: dc.walletCardBgImage.isNotEmpty || dc.walletCardBorderImage.isNotEmpty
                          ? null
                          : dc.walletCardBgColor,
                      border: Border.all(color: dc.walletCardBorderColor.withValues(alpha: 0.2), width: 1),
                      borderRadius: BorderRadius.circular(dc.borderRadius.toDouble()),
                      image: dc.walletCardBgImage.isNotEmpty
                          ? DecorationImage(image: R.cachedImage(dc.walletCardBgImage), fit: BoxFit.cover)
                          : dc.walletCardBorderImage.isNotEmpty
                              ? DecorationImage(image: R.cachedImage(dc.walletCardBorderImage), fit: BoxFit.cover)
                              : null,
                    ),
                    child: Column(
                      children: [
                        if (bonus.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF4444),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(bonus, style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                        const SizedBox(height: 6),
                        R.image(icon, width: 28, height: 28),
                        const SizedBox(height: 2),
                        Text(
                          '$amount',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: dc.walletTextColor),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          decoration: BoxDecoration(
                            color: dc.walletAccentImage.isNotEmpty ? null : dc.walletAccentColor,
                            borderRadius: BorderRadius.circular(8),
                            image: dc.walletAccentImage.isNotEmpty
                                ? DecorationImage(image: R.cachedImage(dc.walletAccentImage), fit: BoxFit.cover)
                                : null,
                          ),
                          child: Text(
                            price,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: dc.walletTextColor),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
