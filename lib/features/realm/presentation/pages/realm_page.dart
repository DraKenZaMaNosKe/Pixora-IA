import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/models/shader_wallpaper.dart';

class RealmPage extends StatelessWidget {
  const RealmPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFF9370DB), Color(0xFF00CED1), Color(0xFFFFD700)],
                  ).createShader(bounds),
                  child: const Text(
                    'REALM',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '✨',
                  style: TextStyle(fontSize: 24),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Real-time GPU shaders. Zero storage. Infinite art.',
              style: TextStyle(fontSize: 12, color: Colors.white38),
            ),
          ),

          // Info banner
          const SizedBox(height: 12),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF9370DB).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF9370DB).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.memory, color: Colors.purple.shade300, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Generated in real-time by your GPU. No downloads needed. Minimal battery usage.',
                    style: TextStyle(fontSize: 11, color: Colors.purple.shade200),
                  ),
                ),
              ],
            ),
          ),

          // Shader grid
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Shader Collection',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.75,
              ),
              itemCount: builtInShaders.length,
              itemBuilder: (_, i) => _ShaderCard(shader: builtInShaders[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShaderCard extends StatelessWidget {
  final ShaderWallpaper shader;
  const _ShaderCard({required this.shader});

  Color get _glowColor {
    try {
      final hex = shader.glowColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return Colors.purple;
    }
  }

  IconData get _icon {
    switch (shader.id) {
      case 'aurora_borealis': return Icons.ac_unit;
      case 'nebula_cosmos': return Icons.blur_on;
      case 'matrix_rain': return Icons.code;
      case 'fire_inferno': return Icons.local_fire_department;
      case 'cyber_grid': return Icons.grid_on;
      default: return Icons.auto_awesome;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showPreviewDialog(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _glowColor.withOpacity(0.3),
              _glowColor.withOpacity(0.05),
              const Color(0xFF0A0A0F),
            ],
          ),
          border: Border.all(color: _glowColor.withOpacity(0.2)),
        ),
        child: Stack(
          children: [
            // Animated-looking icon
            Center(
              child: Icon(_icon, size: 60, color: _glowColor.withOpacity(0.15)),
            ),

            // SHADER badge
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _glowColor,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  'SHADER',
                  style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),

            // 0KB badge
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: const Text(
                  '0 KB',
                  style: TextStyle(fontSize: 8, color: Colors.white70),
                ),
              ),
            ),

            // Bottom info
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shader.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      shader.description,
                      style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.5)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPreviewDialog(BuildContext context) {
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
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 16),
            Icon(_icon, size: 48, color: _glowColor),
            const SizedBox(height: 12),
            Text(shader.name,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(shader.description,
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(0.5)),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: shader.tags.map((t) => Chip(
                label: Text(t, style: TextStyle(fontSize: 10, color: _glowColor)),
                backgroundColor: _glowColor.withOpacity(0.1),
                side: BorderSide(color: _glowColor.withOpacity(0.3)),
                padding: EdgeInsets.zero,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              )).toList(),
            ),
            const SizedBox(height: 6),
            Text('Real-time GPU • 0 KB download • ~1% battery/hr',
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3))),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  const channel = MethodChannel('com.orbix.pixora/wallpaper');
                  try {
                    await channel.invokeMethod('setShaderWallpaper', {
                      'shaderName': shader.shaderFile,
                      'glowColor': shader.glowColor,
                    });
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('${shader.name} shader activated!'),
                          backgroundColor: _glowColor,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _glowColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_awesome, size: 20),
                    SizedBox(width: 8),
                    Text('Activate Shader', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
