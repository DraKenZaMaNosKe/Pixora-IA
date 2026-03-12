import 'dart:io';
import 'package:flutter/material.dart';
import '../../favorites/presentation/favorites_page.dart';
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

  static final _pages = [
    const WallpapersPage(),
    if (!Platform.isIOS) const StoriesPage(),
    const FavoritesPage(),
    const SettingsPage(),
  ];

  static final _titles = [
    'Pixora IA',
    if (!Platform.isIOS) 'Stories',
    'Favorites',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
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
              icon: Icon(Icons.auto_stories),
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
}
