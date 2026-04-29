import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../widgets/cached_wallpaper_image.dart';
import '../../data/models/wallpaper.dart';
import '../../providers/wallpaper_providers.dart';
import 'wallpaper_preview_page.dart';

/// Search query provider.
final _searchQueryProvider = StateProvider<String>((ref) => '');

/// Filtered search results based on query.
final _searchResultsProvider = FutureProvider<List<Wallpaper>>((ref) async {
  final query = ref.watch(_searchQueryProvider).toLowerCase().trim();
  if (query.isEmpty) return [];

  final wallpapers = await ref.watch(catalogProvider.future);
  return wallpapers.where((w) {
    return w.name.toLowerCase().contains(query) ||
        w.description.toLowerCase().contains(query) ||
        w.category.toLowerCase().contains(query) ||
        w.tags.any((t) => t.toLowerCase().contains(query));
  }).toList();
});

class WallpaperSearchPage extends ConsumerStatefulWidget {
  const WallpaperSearchPage({super.key});

  @override
  ConsumerState<WallpaperSearchPage> createState() => _WallpaperSearchPageState();
}

class _WallpaperSearchPageState extends ConsumerState<WallpaperSearchPage> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    // Auto-focus the search field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resultsAsync = ref.watch(_searchResultsProvider);
    final query = ref.watch(_searchQueryProvider);

    final h = context.hud;
    return Scaffold(
      backgroundColor: h.bg,
      appBar: AppBar(
        backgroundColor: h.bg,
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: (v) => ref.read(_searchQueryProvider.notifier).state = v,
          style: TextStyle(color: h.text, fontSize: 16),
          decoration: InputDecoration(
            hintText: 'Search wallpapers...',
            hintStyle: TextStyle(color: h.textDim),
            border: InputBorder.none,
          ),
        ),
        actions: [
          if (query.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear, size: 20),
              onPressed: () {
                _controller.clear();
                ref.read(_searchQueryProvider.notifier).state = '';
              },
            ),
        ],
      ),
      body: query.isEmpty
          ? _buildSuggestions()
          : resultsAsync.when(
              data: (results) => results.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off,
                              color: Colors.white.withValues(alpha: 0.2), size: 64),
                          const SizedBox(height: 12),
                          Text(
                            'No results for "$query"',
                            style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.4)),
                          ),
                        ],
                      ),
                    )
                  : _buildResults(results),
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (_, __) => const SizedBox.shrink(),
            ),
    );
  }

  Widget _buildSuggestions() {
    final suggestions = [
      'Anime',
      'Nature',
      'Gaming',
      'Abstract',
      'Panoramic',
      'Dark',
    ];

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Popular searches',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: suggestions.map((s) {
              return GestureDetector(
                onTap: () {
                  _controller.text = s;
                  ref.read(_searchQueryProvider.notifier).state = s;
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    s,
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildResults(List<Wallpaper> results) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.65,
      ),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final w = results[index];
        return _SearchResultCard(wallpaper: w);
      },
    );
  }
}

class _SearchResultCard extends StatelessWidget {
  const _SearchResultCard({required this.wallpaper});
  final Wallpaper wallpaper;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WallpaperPreviewPage(wallpaper: wallpaper),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedWallpaperImage(imageUrl: wallpaper.previewUrl),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                  stops: [0.5, 1.0],
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              right: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    wallpaper.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    wallpaper.category,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
