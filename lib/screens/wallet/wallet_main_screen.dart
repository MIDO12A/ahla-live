import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/r.dart';
import '../../providers/user_provider.dart';
import '../../services/api_service.dart';
import '../../services/dynamic_config_service.dart';
import '../../services/supabase_service.dart';
import '../../core/supabase_compat.dart';
import '../payment/google_pay_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    try {
      final plans = await _api.getRechargePlans();
      if (mounted) {
        setState(() {
          _coinPlans = plans.where((p) => (p['currency'] ?? 'coins') == 'coins').toList();
          _diamondPlans = plans.where((p) => (p['currency'] ?? 'diamonds') == 'diamonds').toList();
          _loadingPlans = false;
        });
      }
    } catch (_) {
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
    final planId = (plan['id'] as int?) ?? 0;
    final currency = isCoins ? 'coins' : 'diamonds';

    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GooglePayScreen()),
    );
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recharge'),
        content: Text('Add $amount $currency for \$${plan['price']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirm')),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.createOrder(planId);
        if (isCoins) {
          await SupabaseService().addCoins(user.uid, amount);
        } else {
          await Supabase.instance.client.from('users').update({
            'diamonds': (user.diamonds ?? 0) + amount,
          }).eq('uid', user.uid);
        }
        await context.read<UserProvider>().loadUser(user.uid);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('+$amount $currency added!'), backgroundColor: Colors.green),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF9800), Color(0xFFFF5722), Color(0xFFE91E63)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF5722).withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      shape: BoxShape.circle,
                    ),
                    child: Image.asset(
                      'assets/recharge_event/100K.png',
                      width: 32,
                      height: 32,
                      errorBuilder: (_, __, ___) => const Icon(Icons.military_tech, color: Colors.amber, size: 30),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          '⚡ حدث الشحن الأسطوري',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
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
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'دخول',
                      style: TextStyle(
                        color: Color(0xFFD81B60),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
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
