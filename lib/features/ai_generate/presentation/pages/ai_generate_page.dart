import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/design/hud_shapes.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/design/hud_widgets.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/subscription_service.dart';
import '../../../../core/utils/locale_helper.dart';

class AIGeneratePage extends StatefulWidget {
  const AIGeneratePage({super.key});

  @override
  State<AIGeneratePage> createState() => _AIGeneratePageState();
}

class _AIGenerationState {
  final int id;
  final String prompt;
  final String status; // pending | processing | done | failed | cancelled
  final String? resultUrl;
  final String? errorMessage;

  const _AIGenerationState({
    required this.id,
    required this.prompt,
    required this.status,
    this.resultUrl,
    this.errorMessage,
  });
}

class _AIGeneratePageState extends State<AIGeneratePage> {
  static const _nativeChannel = MethodChannel('com.orbix.pixora/wallpaper');

  final _promptController = TextEditingController();
  String? _selectedStyle;
  bool _submitting = false;

  _AIGenerationState? _latest;
  RealtimeChannel? _queueChannel;

  final _styles = const [
    'Anime',
    'Cyberpunk',
    'Fantasy',
    'Minimalist',
    'Nature',
    'Abstract',
    'Pixel Art',
    'Dark',
  ];

  @override
  void initState() {
    super.initState();
    SubscriptionService.instance.refreshStatus();
    _subscribeQueue();
    _loadLastGeneration();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _queueChannel?.unsubscribe();
    super.dispose();
  }

  // ── Data flow (unchanged) ─────────────────────────────────────────────

  void _subscribeQueue() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    _queueChannel = Supabase.instance.client
        .channel('ia_gen_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ia_generation_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: (payload) {
            final row = payload.newRecord;
            final id = row['id'] as int?;
            if (id == null) return;
            if (_latest != null && _latest!.id != id) return;
            setState(() {
              _latest = _AIGenerationState(
                id: id,
                prompt: (row['prompt'] as String?) ?? '',
                status: (row['status'] as String?) ?? 'pending',
                resultUrl: row['result_url'] as String?,
                errorMessage: row['error_message'] as String?,
              );
            });
          },
        )
        .subscribe();
  }

  Future<void> _loadLastGeneration() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('ia_generation_queue')
          .select('id, prompt, status, result_url, error_message')
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(1);
      if (!mounted || rows.isEmpty) return;
      final r = rows.first;
      setState(() {
        _latest = _AIGenerationState(
          id: r['id'] as int,
          prompt: (r['prompt'] as String?) ?? '',
          status: (r['status'] as String?) ?? 'pending',
          resultUrl: r['result_url'] as String?,
          errorMessage: r['error_message'] as String?,
        );
      });
      if (_latest!.status == 'pending') {
        unawaited(_dispatchWorker(_latest!.id));
      }
    } catch (_) {}
  }

  Future<void> _dispatchWorker(int queueId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'process_ia_queue',
        body: {'queue_id': queueId},
      );
    } catch (_) {}
  }

  // ── Gating ────────────────────────────────────────────────────────────

  bool get _canGenerateNow {
    final sub = SubscriptionService.instance;
    if (sub.freeGensRemaining > 0) return true;
    if (!sub.hasAccess) return false;
    if (sub.generationsRemaining > 0) return true;
    return CreditService.instance.balance >= 30;
  }

  String get _buttonLabel {
    final sub = SubscriptionService.instance;
    if (!AuthService.instance.isLoggedIn) {
      return LocaleHelper.pick(
        es: 'INICIA SESIÓN PARA GENERAR',
        en: 'SIGN IN TO GENERATE',
      );
    }
    if (sub.freeGensRemaining > 0) {
      return LocaleHelper.pick(
        es: 'GENERATE · ${sub.freeGensRemaining} FREE',
        en: 'GENERATE · ${sub.freeGensRemaining} FREE',
      );
    }
    if (!sub.hasAccess) {
      return LocaleHelper.pick(
        es: 'SUSCRIBIRSE · \$99/MES',
        en: 'SUBSCRIBE · \$99/MO',
      );
    }
    if (sub.generationsRemaining > 0) {
      return 'GENERATE · ${sub.generationsRemaining} LEFT';
    }
    if (CreditService.instance.balance >= 30) {
      return 'GENERATE · 30 ◆';
    }
    return LocaleHelper.pick(
      es: 'CUOTA AGOTADA',
      en: 'QUOTA EMPTY',
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _handleGeneratePressed() async {
    final sub = SubscriptionService.instance;

    if (!AuthService.instance.isLoggedIn) {
      _showLoginPrompt();
      return;
    }
    if (sub.freeGensRemaining == 0 && !sub.hasAccess) {
      _showPaywall();
      return;
    }
    if (sub.hasAccess &&
        sub.generationsRemaining == 0 &&
        CreditService.instance.balance < 30) {
      _showQuotaExhausted();
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.length < 3) {
      _snack(LocaleHelper.pick(
        es: 'Describe tu imagen (mínimo 3 caracteres).',
        en: 'Describe your image (3 chars min).',
      ));
      return;
    }

    setState(() => _submitting = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'enqueue_generation',
        params: {'p_prompt': prompt, 'p_style': _selectedStyle},
      );
      await SubscriptionService.instance.refreshStatus();
      if (!mounted) return;
      final queueId = (response as Map?)?['queue_id'] as int?;
      if (queueId != null) {
        setState(() {
          _latest = _AIGenerationState(
            id: queueId,
            prompt: prompt,
            status: 'pending',
          );
        });
        unawaited(_dispatchWorker(queueId));
      }
      _snack(
        LocaleHelper.pick(es: '// PROCESANDO...', en: '// PROCESSING...'),
        color: context.hud.accent2,
      );
      _promptController.clear();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack(_translateError(e.message), color: context.hud.accent);
    } catch (e) {
      if (!mounted) return;
      _snack('ERROR: $e', color: context.hud.accent);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── Save / Wallpaper / Share ──────────────────────────────────────────

  Future<File?> _downloadResult() async {
    final url = _latest?.resultUrl;
    if (url == null) return null;
    try {
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode != 200) return null;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/pixora_gen_${_latest!.id}.png');
      await file.writeAsBytes(resp.bodyBytes);
      return file;
    } catch (_) {
      return null;
    }
  }

  Future<void> _onSave() async {
    final file = await _downloadResult();
    if (file == null) {
      _snack('ERROR: no se pudo descargar', color: context.hud.accent);
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      subject: 'Pixora · Generación ${_latest!.id}',
    );
  }

  Future<void> _onWallpaper() async {
    final file = await _downloadResult();
    if (file == null) {
      _snack('ERROR: no se pudo descargar', color: context.hud.accent);
      return;
    }
    try {
      await _nativeChannel.invokeMethod<void>(
        'setWallpaper',
        {'path': file.path},
      );
      if (mounted) {
        _snack('▲ WALLPAPER APLICADO', color: context.hud.accent2);
      }
    } on PlatformException catch (e) {
      if (mounted) {
        _snack('ERROR: ${e.message}', color: context.hud.accent);
      }
    }
  }

  Future<void> _onShare() async {
    final file = await _downloadResult();
    if (file == null) {
      _snack('ERROR: no se pudo descargar', color: context.hud.accent);
      return;
    }
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Mira lo que generé con Pixora IA',
    );
  }

  // ── Small helpers ─────────────────────────────────────────────────────

  String _translateError(String msg) {
    if (msg.contains('prompt_blocked_moderation')) {
      return 'PROMPT BLOQUEADO · NO PERMITIDO';
    }
    if (msg.contains('subscription_required')) {
      return 'SE REQUIERE SUSCRIPCIÓN ACTIVA';
    }
    if (msg.contains('insufficient_credits')) {
      return 'CRÉDITOS INSUFICIENTES';
    }
    if (msg.contains('daily_cap_reached')) {
      return 'MÁXIMO DIARIO ALCANZADO (20/DÍA)';
    }
    if (msg.contains('too_many_pending')) {
      return 'DEMASIADAS EN COLA · ESPERA';
    }
    if (msg.contains('prompt_too_short')) return 'PROMPT MUY CORTO (MIN 3)';
    if (msg.contains('prompt_too_long')) return 'PROMPT MUY LARGO (MAX 1000)';
    return msg;
  }

  void _snack(String text, {Color? color}) {
    final h = context.hud;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text.toUpperCase(),
          style: HudTokens.mono(
            size: 11,
            weight: FontWeight.w700,
            color: Colors.white,
            letterSpacing: 0.1,
          ),
        ),
        backgroundColor: color ?? h.surfaceHi,
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HudTokens.rSharp)),
        ),
      ),
    );
  }

  void _showLoginPrompt() {
    final h = context.hud;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: h.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HudTokens.rSharp)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HudTokens.sp6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '// AUTH_REQUIRED',
                style: HudTokens.display(
                  size: 14,
                  color: h.accent,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: HudTokens.sp3),
              Text(
                LocaleHelper.pick(
                  es: 'Para generar imágenes con IA necesitas una cuenta de Google. Así protegemos tus créditos y tu suscripción a través de dispositivos.',
                  en: 'Sign in with Google to generate AI images. This protects your credits and subscription across devices.',
                ),
                style: HudTokens.body(size: 13, color: h.text),
              ),
              const SizedBox(height: HudTokens.sp5),
              HudGhostButton(
                label: LocaleHelper.pick(es: 'ENTENDIDO', en: 'OK'),
                icon: '✓',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showPaywall() async {
    final h = context.hud;
    final sub = SubscriptionService.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: h.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HudTokens.rSmall),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            HudTokens.sp6,
            HudTokens.sp5,
            HudTokens.sp6,
            HudTokens.sp6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    color: h.accent,
                    alignment: Alignment.center,
                    child: Text(
                      'P+',
                      style: HudTokens.display(
                        size: 13,
                        color: Colors.white,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  const SizedBox(width: HudTokens.sp3),
                  Text(
                    'PIXORA PLUS',
                    style: HudTokens.display(
                      size: 20,
                      color: h.text,
                      letterSpacing: 0.05,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: HudTokens.sp3),
              Text(
                LocaleHelper.pick(
                  es: '100 GENERACIONES IA AL MES · 7 DÍAS GRATIS',
                  en: '100 AI GENERATIONS / MONTH · 7-DAY TRIAL',
                ),
                style: HudTokens.mono(
                  size: 11,
                  color: h.accent2,
                  letterSpacing: 0.15,
                ),
              ),
              const SizedBox(height: HudTokens.sp6),
              _benefit('◆', 'SYNC CROSS-DEVICE'),
              _benefit('◆', 'ACCESO A MODELOS PREMIUM'),
              _benefit('◆', 'CANCELA CUANDO QUIERAS'),
              const SizedBox(height: HudTokens.sp6),
              HudPrimaryButton(
                label: 'EMPEZAR PRUEBA GRATUITA',
                busy: sub.purchaseInFlight,
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  final ok = await SubscriptionService.instance.buyMonthly();
                  if (!ok && mounted) {
                    _snack(
                      LocaleHelper.pick(
                        es: 'NO SE PUDO ABRIR COMPRA',
                        en: 'COULD NOT OPEN PURCHASE',
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: HudTokens.sp3),
              Text(
                LocaleHelper.pick(
                  es: 'Cobro automático tras 7 días. Cancela desde Google Play antes de vencer.',
                  en: 'Auto-charged after 7 days. Cancel in Google Play anytime before.',
                ),
                textAlign: TextAlign.center,
                style: HudTokens.mono(
                  size: 9,
                  color: h.textDim,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefit(String icon, String text) {
    final h = context.hud;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HudTokens.sp2),
      child: Row(
        children: [
          Text(icon, style: TextStyle(color: h.accent2, fontSize: 16)),
          const SizedBox(width: HudTokens.sp3),
          Text(
            text,
            style: HudTokens.mono(size: 11, color: h.text, letterSpacing: 0.1),
          ),
        ],
      ),
    );
  }

  void _showQuotaExhausted() {
    final h = context.hud;
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: h.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(HudTokens.rSharp)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(HudTokens.sp6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '// QUOTA_EXHAUSTED',
                style: HudTokens.display(
                  size: 14,
                  color: h.accent,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: HudTokens.sp3),
              Text(
                LocaleHelper.pick(
                  es: 'Ya usaste las 100 generaciones de este mes. Espera al próximo ciclo o gasta 30 diamantes (de ads) para una extra.',
                  en: 'You\'ve used this month\'s 100. Wait for next cycle or spend 30 diamonds for an extra.',
                ),
                style: HudTokens.body(size: 13, color: h.text),
              ),
              const SizedBox(height: HudTokens.sp5),
              HudGhostButton(
                label: LocaleHelper.pick(es: 'ENTENDIDO', en: 'OK'),
                icon: '✓',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    return Scaffold(
      backgroundColor: h.bg,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          CreditService.instance,
          SubscriptionService.instance,
        ]),
        builder: (context, _) {
          return CustomPaint(
            painter: ScanLinesPainter(color: h.text),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                HudTokens.sp5,
                HudTokens.sp5,
                HudTokens.sp5,
                HudTokens.sp8,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeroCard(),
                  if (_latest != null) ...[
                    const SizedBox(height: HudTokens.sp6),
                    _buildResultPanel(_latest!),
                  ],
                  const SizedBox(height: HudTokens.sp6),
                  _buildPromptInput(),
                  const SizedBox(height: HudTokens.sp5),
                  _buildStyleGrid(),
                  const SizedBox(height: HudTokens.sp6),
                  HudPrimaryButton(
                    label: _buttonLabel,
                    busy: _submitting,
                    onPressed: _handleGeneratePressed,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroCard() {
    final h = context.hud;
    final sub = SubscriptionService.instance;
    final credits = CreditService.instance.balance;
    final auth = AuthService.instance;

    String statusLine;
    if (!auth.isLoggedIn) {
      statusLine = '> AUTH_REQUIRED';
    } else if (sub.hasAccess) {
      statusLine =
          '> QUOTA: ${sub.generationsRemaining}/${sub.generationsLimit} · MONTH';
    } else if (sub.freeGensRemaining > 0) {
      statusLine = '> TRIAL: ${sub.freeGensRemaining} FREE GENS REMAINING';
    } else {
      statusLine = '> SUBSCRIBE_TO_UNLOCK';
    }

    return ClipPath(
      clipper: const CornerCutClipper(cut: HudTokens.cornerCutLg),
      child: Container(
        padding: const EdgeInsets.all(HudTokens.sp5),
        decoration: BoxDecoration(
          color: h.surfaceHi,
          border: Border.all(color: h.accent, width: HudTokens.borderMed),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '// IA GENERATOR',
                  style: HudTokens.display(
                    size: 12,
                    color: h.accent,
                    letterSpacing: 0.1,
                  ),
                ),
                const Spacer(),
                HudBadge(
                  text: 'NANO_BANANA',
                  color: h.surface,
                  onColor: h.accent2,
                ),
              ],
            ),
            const SizedBox(height: HudTokens.sp3),
            Text(
              'PIXORA\nIA',
              style: HudTokens.display(
                size: 36,
                color: h.text,
                letterSpacing: -0.01,
              ),
            ),
            const SizedBox(height: HudTokens.sp4),
            Text(
              statusLine,
              style: HudTokens.mono(
                size: 11,
                color: h.textDim,
                letterSpacing: 0.1,
              ),
            ),
            const SizedBox(height: HudTokens.sp4),
            Row(
              children: [
                HudStatChip(label: '◆', value: '$credits'),
                const SizedBox(width: HudTokens.sp5),
                HudStatChip(
                  label: 'COST',
                  value: '30 ◆',
                  color: h.accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptInput() {
    final h = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '> PROMPT_',
          style: HudTokens.mono(
            size: 11,
            color: h.accent,
            weight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(height: HudTokens.sp2),
        ClipPath(
          clipper: const CornerCutClipper(cut: HudTokens.cornerCutSm),
          child: Container(
            color: h.surface,
            padding: const EdgeInsets.all(HudTokens.sp3),
            child: TextField(
              controller: _promptController,
              maxLines: 3,
              maxLength: 1000,
              style: HudTokens.body(size: 14, color: h.text),
              cursorColor: h.accent,
              decoration: InputDecoration(
                hintText:
                    'un dragón cyberpunk sobre una ciudad neón en la noche...',
                hintStyle: HudTokens.body(size: 14, color: h.textDim),
                border: InputBorder.none,
                counterStyle: HudTokens.mono(
                  size: 9,
                  color: h.textDim,
                  letterSpacing: 0.1,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleGrid() {
    final h = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '> STYLE_',
          style: HudTokens.mono(
            size: 11,
            color: h.accent,
            weight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
        const SizedBox(height: HudTokens.sp2),
        Wrap(
          spacing: HudTokens.sp2,
          runSpacing: HudTokens.sp2,
          children: _styles.map((style) {
            final selected = _selectedStyle == style;
            return GestureDetector(
              onTap: () =>
                  setState(() => _selectedStyle = selected ? null : style),
              child: ClipPath(
                clipper: const CornerCutClipper(cut: 6),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: HudTokens.sp3,
                    vertical: HudTokens.sp2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? h.accent : h.surface,
                    border: Border.all(
                      color: selected ? h.accent : h.divider,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    style.toUpperCase(),
                    style: HudTokens.mono(
                      size: 11,
                      weight: FontWeight.w700,
                      color: selected ? Colors.white : h.text,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildResultPanel(_AIGenerationState g) {
    final h = context.hud;
    final isDone = g.status == 'done' && g.resultUrl != null;
    final isFailed = g.status == 'failed';

    Widget inner;
    if (isDone) {
      inner = Image.network(
        g.resultUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (ctx, child, progress) {
          if (progress == null) return child;
          return AspectRatio(
            aspectRatio: 9 / 16,
            child: Center(
              child: CircularProgressIndicator(color: h.accent, strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, __, ___) => AspectRatio(
          aspectRatio: 9 / 16,
          child: Container(
            color: h.surface,
            child: Icon(Icons.broken_image, color: h.textDim),
          ),
        ),
      );
    } else if (isFailed) {
      inner = AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          color: h.surface,
          padding: const EdgeInsets.all(HudTokens.sp6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '× FAILED',
                style: HudTokens.display(
                  size: 20,
                  color: h.accent,
                  letterSpacing: 0.1,
                ),
              ),
              const SizedBox(height: HudTokens.sp3),
              Text(
                LocaleHelper.pick(
                  es: 'TU CUOTA NO SE CONSUMIÓ',
                  en: 'YOUR QUOTA WAS REFUNDED',
                ),
                textAlign: TextAlign.center,
                style: HudTokens.mono(
                  size: 11,
                  color: h.textDim,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // pending or processing
      inner = AspectRatio(
        aspectRatio: 9 / 16,
        child: Container(
          color: h.surface,
          padding: const EdgeInsets.all(HudTokens.sp6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 32,
                height: 32,
                child: CircularProgressIndicator(
                  color: h.accent,
                  strokeWidth: 2,
                ),
              ),
              const SizedBox(height: HudTokens.sp4),
              Text(
                g.status == 'processing' ? '> GENERATING...' : '> QUEUED...',
                style: HudTokens.display(
                  size: 12,
                  color: h.accent2,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '// GEN_${g.id.toString().padLeft(3, '0')}',
              style: HudTokens.display(
                size: 12,
                color: h.accent2,
                letterSpacing: 0.1,
              ),
            ),
            const Spacer(),
            HudStatusTag(
              text: g.status.toUpperCase(),
              color: isDone
                  ? HudTokens.okGreen
                  : isFailed
                      ? h.accent
                      : h.accent2,
            ),
          ],
        ),
        const SizedBox(height: HudTokens.sp3),
        ClipPath(
          clipper: const CornerCutClipper(cut: HudTokens.cornerCutMd),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: h.accent, width: HudTokens.borderMed),
            ),
            child: inner,
          ),
        ),
        if (isDone) ...[
          const SizedBox(height: HudTokens.sp3),
          Row(
            children: [
              Expanded(
                child: HudGhostButton(
                  label: LocaleHelper.pick(es: 'GUARDAR', en: 'SAVE'),
                  icon: '▼',
                  onPressed: _onSave,
                ),
              ),
              const SizedBox(width: HudTokens.sp2),
              Expanded(
                child: HudGhostButton(
                  label: 'WALLPAPER',
                  icon: '◉',
                  onPressed: _onWallpaper,
                ),
              ),
              const SizedBox(width: HudTokens.sp2),
              Expanded(
                child: HudGhostButton(
                  label: LocaleHelper.pick(es: 'ENVIAR', en: 'SHARE'),
                  icon: '↗',
                  onPressed: _onShare,
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
