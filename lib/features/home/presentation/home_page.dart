import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/services/auth_service.dart';
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
