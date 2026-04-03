class ShaderWallpaper {
  final String id;
  final String name;
  final String description;
  final String shaderFile; // e.g., "aurora_borealis" (without .glsl)
  final String glowColor;
  final String category;
  final String previewAsset; // local asset for preview image
  final List<String> tags;

  const ShaderWallpaper({
    required this.id,
    required this.name,
    required this.description,
    required this.shaderFile,
    required this.glowColor,
    this.category = 'SHADER',
    this.previewAsset = '',
    this.tags = const [],
  });
}

/// Built-in shader catalog (no network needed — runs 100% local)
const builtInShaders = [
  ShaderWallpaper(
    id: 'green_dot',
    name: 'Green Dot',
    description: 'A single green dot centered on screen — the most basic shader test',
    shaderFile: 'green_dot',
    glowColor: '#00FF00',
    category: 'DEBUG',
    tags: ['test', 'basic', 'dot'],
  ),
];
