import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/design/hud_shapes.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/design/hud_widgets.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/credit_service.dart';
import '../../../core/services/subscription_service.dart';
import '../../ai_generate/presentation/pages/ai_generate_page.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../../settings/presentation/settings_page.dart';
import '../../stories/presentation/pages/stories_page.dart';
import '../../day_cycle/presentation/pages/day_cycle_page.dart';
import '../../hot_wallpapers/presentation/pages/hot_wallpapers_page.dart';
import '../../aura/presentation/pages/aura_page.dart';
import '../../ringtones/presentation/pages/ringtones_page.dart';
import '../../wallpapers/presentation/pages/wallpaper_search_page.dart';
import '../../wallpapers/presentation/pages/wallpapers_page.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  int _currentIndex = 0;

  static final _pages = [
    const WallpapersPage(),
    if (!Platform.isIOS) const HotWallpapersPage(),
    if (!Platform.isIOS) const AuraPage(),
    if (!Platform.isIOS) const StoriesPage(),
    if (!Platform.isIOS) const DayCyclePage(),
    if (!Platform.isIOS) const RingtonesPage(),
    if (!Platform.isIOS) const AIGeneratePage(),
    const FavoritesPage(),
    const SettingsPage(),
  ];

  bool get _isWallpapersTab => _currentIndex == 0;

  String get _title {
    final titles = [
      'PIXORA',
      if (!Platform.isIOS) 'LIVE',
      if (!Platform.isIOS) 'AURA',
      if (!Platform.isIOS) 'STORIES',
      if (!Platform.isIOS) 'DAY CYCLE',
      if (!Platform.isIOS) 'TONES',
      if (!Platform.isIOS) 'AI CREATE',
      'FAVORITES',
      'SETTINGS',
    ];
    return titles[_currentIndex];
  }

  void _onAvatarTap() {
    final auth = AuthService.instance;

    if (auth.isLoggedIn) {
      setState(() => _currentIndex = _pages.length - 1);
      return;
    }
    _showLoginSheet();
  }

  void _showLoginSheet() {
    final h = context.hud;
    showModalBottomSheet(
      context: context,
      backgroundColor: h.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(HudTokens.rSharp)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(
            HudTokens.sp6, HudTokens.sp5, HudTokens.sp6, HudTokens.sp6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '// SYNC_CLOUD',
              style: HudTokens.display(
                  size: 12, color: h.accent, letterSpacing: 0.1),
            ),
            const SizedBox(height: HudTokens.sp3),
            Text(
              'SIGN IN TO PIXORA',
              style: HudTokens.display(
                  size: 20, color: h.text, letterSpacing: 0.02),
            ),
            const SizedBox(height: HudTokens.sp2),
            Text(
              'Sync favorites across devices and track your downloads',
              style: HudTokens.body(size: 13, color: h.textDim),
            ),
            const SizedBox(height: HudTokens.sp5),
            HudPrimaryButton(
              label: 'CONTINUE WITH GOOGLE',
              icon: Icons.g_mobiledata,
              onPressed: () async {
                Navigator.pop(ctx);
                final success = await AuthService.instance.signInWithGoogle();
                if (success && mounted) {
                  setState(() {});
                  ref.read(favoritesProvider.notifier).syncWithCloud();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '// WELCOME · FAVORITES SYNCED',
                        style: HudTokens.mono(
                          size: 11,
                          color: Colors.white,
                          weight: FontWeight.w700,
                          letterSpacing: 0.1,
                        ),
                      ),
                      backgroundColor: HudTokens.okGreen,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: HudTokens.sp3),
            Text(
              '> OPTIONAL · APP WORKS WITHOUT ACCOUNT',
              textAlign: TextAlign.center,
              style: HudTokens.mono(
                  size: 9, color: h.textDim, letterSpacing: 0.15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final auth = AuthService.instance;
    final h = context.hud;
    final child = auth.isLoggedIn && auth.avatarUrl != null
        ? CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(auth.avatarUrl!),
            backgroundColor: h.surface,
          )
        : CircleAvatar(
            radius: 16,
            backgroundColor: h.surface,
            child: Icon(Icons.person, size: 18, color: h.textDim),
          );
    return GestureDetector(
      onTap: _onAvatarTap,
      child: Padding(
        padding: const EdgeInsets.only(left: HudTokens.sp3),
        child: _PlusHaloAvatar(child: child),
      ),
    );
  }

  void _showCreditsSheet() {
    final h = context.hud;
    final credits = CreditService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: h.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(HudTokens.rSharp)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: credits,
        builder: (ctx, _) => Padding(
          padding: const EdgeInsets.fromLTRB(
              HudTokens.sp6, HudTokens.sp5, HudTokens.sp6, HudTokens.sp6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('// DIAMONDS_WALLET',
                  style: HudTokens.display(
                      size: 12, color: h.accent, letterSpacing: 0.1)),
              const SizedBox(height: HudTokens.sp4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.diamond, size: 38, color: h.accent2),
                  const SizedBox(width: HudTokens.sp2),
                  Text('${credits.balance}',
                      style: HudTokens.display(
                          size: 44, color: h.text, letterSpacing: -0.02)),
                ],
              ),
              const SizedBox(height: HudTokens.sp2),
              Center(
                child: Text('BALANCE',
                    style: HudTokens.mono(
                        size: 10, color: h.textDim, letterSpacing: 0.3)),
              ),
              const SizedBox(height: HudTokens.sp5),
              ClipPath(
                clipper: const CornerCutClipper(cut: HudTokens.cornerCutSm),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: HudTokens.sp4),
                  decoration: BoxDecoration(
                    color: h.surfaceHi,
                    border: Border.all(color: h.divider, width: 1),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _creditStat('EARNED', '${credits.totalEarned}'),
                      Container(width: 1, height: 30, color: h.divider),
                      _creditStat('ADS', '${credits.adsWatched}'),
                      Container(width: 1, height: 30, color: h.divider),
                      _creditStat('PER AD', '+${CreditService.creditsPerAd}'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: HudTokens.sp4),
              Text(
                '> WATCH ADS TO EARN DIAMONDS AUTOMATICALLY',
                textAlign: TextAlign.center,
                style: HudTokens.mono(
                    size: 10, color: h.textDim, letterSpacing: 0.15),
              ),
              const SizedBox(height: HudTokens.sp3),
            ],
          ),
        ),
      ),
    );
  }

  Widget _creditStat(String label, String value) {
    final h = context.hud;
    return Column(
      children: [
        Text(value,
            style: HudTokens.display(
                size: 18, color: h.accent2, letterSpacing: -0.01)),
        const SizedBox(height: 2),
        Text(label,
            style:
                HudTokens.mono(size: 9, color: h.textDim, letterSpacing: 0.2)),
      ],
    );
  }

  Widget _buildCreditsBadge() {
    return ListenableBuilder(
      listenable: CreditService.instance,
      builder: (context, _) {
        final h = context.hud;
        final credits = CreditService.instance.balance;
        return GestureDetector(
          onTap: _showCreditsSheet,
          child: ClipPath(
            clipper: const CornerCutClipper(cut: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: HudTokens.sp3, vertical: 5),
              decoration: BoxDecoration(
                color: h.surface,
                border: Border.all(color: h.accent, width: 1.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.diamond, size: 14, color: h.accent2),
                  const SizedBox(width: 5),
                  Text('$credits',
                      style: HudTokens.mono(
                          size: 13,
                          weight: FontWeight.w700,
                          color: h.text,
                          letterSpacing: 0.05)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final h = context.hud;
    final transparent = _isWallpapersTab;
    return AppBar(
      backgroundColor: transparent ? Colors.transparent : h.bg,
      elevation: 0,
      leading: _buildAvatar(),
      leadingWidth: 56,
      title: Text(
        _title,
        style: HudTokens.display(
          size: 18,
          color: h.text,
          letterSpacing: 0.04,
        ),
      ),
      actions: [
        _buildCreditsBadge(),
        const SizedBox(width: HudTokens.sp2),
        if (_isWallpapersTab)
          IconButton(
            icon: Icon(Icons.search, color: h.text, size: 22),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const WallpaperSearchPage(),
                ),
              );
            },
          ),
        const SizedBox(width: HudTokens.sp1),
      ],
    );
  }

  Widget _buildBottomNav() {
    final h = context.hud;
    final items = <_NavItemData>[
      _NavItemData(Icons.image_outlined, 'WALL'),
      if (!Platform.isIOS) _NavItemData(Icons.play_arrow_rounded, 'LIVE'),
      if (!Platform.isIOS) _NavItemData(Icons.spa_outlined, 'AURA'),
      if (!Platform.isIOS) _NavItemData(Icons.auto_stories_outlined, 'STOR'),
      if (!Platform.isIOS) _NavItemData(Icons.wb_twilight_outlined, 'DAY'),
      if (!Platform.isIOS) _NavItemData(Icons.music_note_outlined, 'TON'),
      if (!Platform.isIOS) _NavItemData(Icons.auto_awesome_outlined, 'IA'),
      _NavItemData(Icons.favorite_outline, 'FAV'),
      _NavItemData(Icons.settings_outlined, 'SET'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: h.bg,
        border: Border(
            top: BorderSide(color: h.accent, width: HudTokens.borderMed)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: _NavItem(
                  data: items[i],
                  active: _currentIndex == i,
                  onTap: () => setState(() => _currentIndex = i),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Scaffold(
      backgroundColor: h.bg,
      extendBodyBehindAppBar: _isWallpapersTab,
      appBar: _buildAppBar(),
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  const _NavItemData(this.icon, this.label);
}

class _NavItem extends StatelessWidget {
  const _NavItem(
      {required this.data, required this.active, required this.onTap});
  final _NavItemData data;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final color = active ? h.accent : h.textDim;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: active ? h.accent.withOpacity(0.08) : null,
          border: active
              ? Border(
                  top: BorderSide(color: h.accent2, width: HudTokens.borderMed),
                )
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(data.icon, color: color, size: 18),
            const SizedBox(height: 3),
            Text(
              data.label,
              style: HudTokens.mono(
                size: 8,
                weight: FontWeight.w700,
                color: color,
                letterSpacing: 0.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Plus-subscriber halo avatar ───────────────────────────────────
// Wraps the 32px avatar with a breathing gold ring when the user has an
// active Plus subscription. Listens to SubscriptionService so the halo
// appears/disappears reactively when status changes.
class _PlusHaloAvatar extends StatefulWidget {
  const _PlusHaloAvatar({required this.child});
  final Widget child;

  @override
  State<_PlusHaloAvatar> createState() => _PlusHaloAvatarState();
}

class _PlusHaloAvatarState extends State<_PlusHaloAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: SubscriptionService.instance,
      builder: (context, _) {
        final hasPlus = SubscriptionService.instance.status.hasAccess;
        if (!hasPlus) return widget.child;
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value; // 0..1..0 reversing
            final blur = 6.0 + 8.0 * t;
            final ringOpacity = 0.55 + 0.25 * t;
            return Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: SweepGradient(
                  colors: [
                    HudTokens.goldDeep,
                    HudTokens.gold,
                    HudTokens.goldBright,
                    HudTokens.gold,
                    HudTokens.goldDeep,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: HudTokens.gold.withOpacity(ringOpacity * 0.5),
                    blurRadius: blur,
                    spreadRadius: 0.5,
                  ),
                ],
              ),
              child: widget.child,
            );
          },
        );
      },
    );
  }
}
