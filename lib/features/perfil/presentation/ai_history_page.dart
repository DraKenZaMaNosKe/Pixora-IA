import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/auth_service.dart';

/// Grid of all AI-generated images the signed-in user has created. Reads
/// from the `ia_generation_queue` table — same table the AI generate page
/// uses, so what the user sees here matches what they see while generating.
///
/// Schema (relevant columns):
///   - id          int8
///   - user_id     uuid
///   - prompt      text   (the user's prompt)
///   - status      text   ('pending' | 'done' | 'error')
///   - result_url  text   (Supabase storage public URL — only filled when status='done')
///   - created_at  timestamptz
class AIHistoryPage extends StatefulWidget {
  const AIHistoryPage({super.key});

  @override
  State<AIHistoryPage> createState() => _AIHistoryPageState();
}

class _AIHistoryPageState extends State<AIHistoryPage> {
  Future<List<Map<String, dynamic>>>? _future;
  String? _fetchedForUserId;

  @override
  void initState() {
    super.initState();
    AuthService.instance.addListener(_onAuthChanged);
    _refreshIfUserChanged();
  }

  @override
  void dispose() {
    AuthService.instance.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (!mounted) return;
    setState(_refreshIfUserChanged);
  }

  void _refreshIfUserChanged() {
    final uid = AuthService.instance.currentUser?.id;
    if (uid != _fetchedForUserId) {
      _fetchedForUserId = uid;
      _future = _fetch();
    }
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return const [];
    try {
      final rows = await Supabase.instance.client
          .from('ia_generation_queue')
          .select('id, prompt, status, result_url, created_at')
          .eq('user_id', user.id)
          .eq('status', 'done')
          .not('result_url', 'is', null)
          .order('created_at', ascending: false)
          .limit(120);
      return List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Scaffold(
      backgroundColor: h.bg,
      appBar: AppBar(
        backgroundColor: h.bg,
        elevation: 0,
        title: Text(
          'Mis imágenes IA',
          style: TextStyle(
            color: h.text,
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: h.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: h.accent, strokeWidth: 2),
            );
          }
          final rows = snapshot.data ?? const [];
          if (rows.isEmpty) {
            return _Empty(h: h);
          }
          return GridView.builder(
            padding: const EdgeInsets.all(12),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 9 / 16,
            ),
            itemCount: rows.length,
            itemBuilder: (_, i) => _AITile(row: rows[i], h: h),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.h});
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_awesome_outlined, size: 56, color: h.textDim),
          const SizedBox(height: 18),
          Text(
            'Aún no creas con IA',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Fraunces',
              fontStyle: FontStyle.italic,
              fontSize: 22,
              color: h.text,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Ve a la sección AI Create del menú inferior y genera tu primer wallpaper único.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: h.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _AITile extends StatelessWidget {
  const _AITile({required this.row, required this.h});
  final Map<String, dynamic> row;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final url = row['result_url'] as String?;
    final prompt = row['prompt'] as String?;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (url != null)
            CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              // Card historia AI ~200px. Decodificar 400px ahorra memoria.
              memCacheWidth: 400,
              placeholder: (_, __) => Container(color: h.surface),
              errorWidget: (_, __, ___) => Container(
                color: h.surface,
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined, color: h.textDim),
              ),
            )
          else
            Container(color: h.surface),
          // Prompt overlay at the bottom
          if (prompt != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                  ),
                ),
                child: Text(
                  prompt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    height: 1.3,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
