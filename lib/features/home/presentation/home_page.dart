import 'package:flutter/material.dart';
import '../../favorites/presentation/favorites_page.dart';
import '../../icon_rooms/presentation/pages/icon_rooms_page.dart';
import '../../settings/presentation/settings_page.dart';
import '../../stories/presentation/pages/stories_page.dart';
import '../../wallpapers/presentation/pages/wallpapers_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  static const _pages = [
    WallpapersPage(),
    IconRoomsPage(),
    StoriesPage(),
    FavoritesPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _buildTitle(),
        actions: [
          if (_currentIndex == 0)
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () {
                // TODO: Search
              },
            ),
        ],
      ),
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildTitle() {
    switch (_currentIndex) {
      case 1:
        return _buildSpecialTitle(
          'Icon Rooms',
          const [Color(0xFF7C4DFF), Color(0xFF00E5FF)],
          Icons.dashboard_customize,
        );
      case 2:
        return _buildSpecialTitle(
          'Stories',
          const [Color(0xFFFF6090), Color(0xFFFFD740)],
          Icons.auto_stories,
        );
      case 3:
        return const Text('Favorites');
      case 4:
        return const Text('Settings');
      default:
        return const Text('Pixora IA');
    }
  }

  Widget _buildSpecialTitle(
      String text, List<Color> colors, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: colors,
          ).createShader(bounds),
          child: Icon(icon, color: Colors.white, size: 24),
        ),
        const SizedBox(width: 8),
        ShaderMask(
          shaderCallback: (bounds) => LinearGradient(
            colors: colors,
          ).createShader(bounds),
          child: Text(
            text,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.white10, width: 0.5),
        ),
      ),
      child: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        type: BottomNavigationBarType.fixed,
        selectedFontSize: 11,
        unselectedFontSize: 10,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.wallpaper),
            label: 'Wallpapers',
          ),
          BottomNavigationBarItem(
            icon: _buildGradientIcon(
              Icons.dashboard_customize,
              const [Color(0xFF7C4DFF), Color(0xFF00E5FF)],
              isSelected: _currentIndex == 1,
            ),
            label: 'Icon Rooms',
          ),
          BottomNavigationBarItem(
            icon: _buildGradientIcon(
              Icons.auto_stories,
              const [Color(0xFFFF6090), Color(0xFFFFD740)],
              isSelected: _currentIndex == 2,
            ),
            label: 'Stories',
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

  Widget _buildGradientIcon(
      IconData icon, List<Color> colors, {required bool isSelected}) {
    if (!isSelected) return Icon(icon);
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        colors: colors,
      ).createShader(bounds),
      child: Icon(icon, color: Colors.white),
    );
  }
}
