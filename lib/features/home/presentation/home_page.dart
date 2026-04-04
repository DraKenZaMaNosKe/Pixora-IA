import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/credit_service.dart';
import '../../ai_generate/presentation/pages/ai_generate_page.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../favorites/providers/favorites_provider.dart';
import '../../settings/presentation/settings_page.dart';
import '../../stories/presentation/pages/stories_page.dart';
import '../../day_cycle/presentation/pages/day_cycle_page.dart';
import '../../hot_wallpapers/presentation/pages/hot_wallpapers_page.dart';
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
      'Pixora IA',
      if (!Platform.isIOS) 'HOT',
      if (!Platform.isIOS) 'Stories',
      if (!Platform.isIOS) 'Day Cycle',
      if (!Platform.isIOS) 'Tones',
      if (!Platform.isIOS) 'AI Create',
      'Favorites',
      'Settings',
    ];
    return titles[_currentIndex];
  }

  void _onAvatarTap() {
    final auth = AuthService.instance;

    if (auth.isLoggedIn) {
      // Go to settings tab
      setState(() {
        _currentIndex = _pages.length - 1; // Settings is last
      });
      return;
    }

    // Show login bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_sync, size: 48, color: Colors.white.withOpacity(0.3)),
            const SizedBox(height: 16),
            const Text(
              'Sign in to Pixora',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 6),
            Text(
              'Sync favorites across devices and track your downloads',
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final success = await AuthService.instance.signInWithGoogle();
                  if (success && mounted) {
                    setState(() {});
                    ref.read(favoritesProvider.notifier).syncWithCloud();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Welcome! Favorites synced.'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: const Text('Continue with Google', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Optional — app works fully without an account',
              style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final auth = AuthService.instance;

    if (auth.isLoggedIn && auth.avatarUrl != null) {
      return GestureDetector(
        onTap: _onAvatarTap,
        child: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: CircleAvatar(
            radius: 16,
            backgroundImage: NetworkImage(auth.avatarUrl!),
            backgroundColor: const Color(0xFF7C4DFF),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _onAvatarTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: CircleAvatar(
          radius: 16,
          backgroundColor: Colors.white.withOpacity(0.15),
          child: Icon(
            Icons.person,
            size: 18,
            color: Colors.white.withOpacity(0.6),
          ),
        ),
      ),
    );
  }

  void _showCreditsSheet() {
    final credits = CreditService.instance;
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: credits,
        builder: (ctx, _) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              // Balance
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.diamond, size: 32, color: Color(0xFF7C4DFF)),
                  const SizedBox(width: 10),
                  Text(
                    '${credits.balance}',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Credits',
                style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.5)),
              ),
              const SizedBox(height: 20),
              // Stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _creditStat('Earned', '${credits.totalEarned}'),
                    Container(width: 1, height: 30, color: Colors.white12),
                    _creditStat('Ads Watched', '${credits.adsWatched}'),
                    Container(width: 1, height: 30, color: Colors.white12),
                    _creditStat('Per Ad', '+${CreditService.creditsPerAd}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Promo banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color(0xFF7C4DFF).withOpacity(0.2),
                      const Color(0xFF00B4D8).withOpacity(0.2),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF7C4DFF).withOpacity(0.3)),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.auto_awesome, size: 18, color: Color(0xFF00B4D8)),
                        SizedBox(width: 8),
                        Text(
                          'AI Wallpapers — Coming Soon',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Save credits now! Generate wallpapers and ringtones with AI when it launches.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.6),
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // How to earn
              Text(
                'Watch ads while using the app to earn credits automatically',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.35)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _creditStat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: _isWallpapersTab,
      appBar: _isWallpapersTab
          ? AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              leading: _buildAvatar(),
              title: const Text(
                'Pixora IA',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              actions: [
                // Credits badge
                ListenableBuilder(
                  listenable: CreditService.instance,
                  builder: (context, _) {
                    final credits = CreditService.instance.balance;
                    return GestureDetector(
                      onTap: () => _showCreditsSheet(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFF7C4DFF), width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF7C4DFF).withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 1,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.diamond, size: 16, color: Color(0xFF00E5FF)),
                            const SizedBox(width: 5),
                            Text(
                              '$credits',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const WallpaperSearchPage(),
                      ),
                    );
                  },
                ),
              ],
            )
          : AppBar(
              title: Text(_title),
            ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.wallpaper),
            label: 'Wallpapers',
          ),
          if (!Platform.isIOS)
            const BottomNavigationBarItem(
              icon: Icon(Icons.local_fire_department),
              label: 'HOT',
            ),
          if (!Platform.isIOS)
            const BottomNavigationBarItem(
              icon: Icon(Icons.auto_stories),
              label: 'Stories',
            ),
          if (!Platform.isIOS)
            const BottomNavigationBarItem(
              icon: Icon(Icons.wb_twilight),
              label: 'Day Cycle',
            ),
          if (!Platform.isIOS)
            const BottomNavigationBarItem(
              icon: Icon(Icons.music_note),
              label: 'Tones',
            ),
          if (!Platform.isIOS)
            const BottomNavigationBarItem(
              icon: Icon(Icons.auto_awesome),
              label: 'AI',
            ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Favorites',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
