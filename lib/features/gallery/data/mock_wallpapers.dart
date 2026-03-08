import 'models/wallpaper.dart';

const mockWallpapers = [
  Wallpaper(
    id: 'aurora_nebula',
    title: 'Aurora Nebula',
    previewUrl: 'https://images.unsplash.com/photo-1446776811953-b23d57bd21aa?auto=format&fit=crop&w=600&q=80',
    assetType: WallpaperAssetType.video,
    sourceUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/butterfly.mp4',
    tags: ['space', 'purple', 'galaxy'],
    durationSeconds: 12,
  ),
  Wallpaper(
    id: 'cyber_city',
    title: 'Cyber City Lights',
    previewUrl: 'https://images.unsplash.com/photo-1469474968028-56623f02e42e?auto=format&fit=crop&w=600&q=80',
    assetType: WallpaperAssetType.video,
    sourceUrl: 'https://flutter.github.io/assets-for-api-docs/assets/videos/bee.mp4',
    tags: ['city', 'neon', 'night'],
    durationSeconds: 9,
  ),
  Wallpaper(
    id: 'prism_flow',
    title: 'Prism Flow',
    previewUrl: 'https://images.unsplash.com/photo-1498050108023-c5249f4df085?auto=format&fit=crop&w=600&q=80',
    assetType: WallpaperAssetType.lottie,
    sourceUrl: 'https://assets10.lottiefiles.com/packages/lf20_u4yrau.json',
    tags: ['abstract', 'loop'],
    durationSeconds: 8,
  ),
];
