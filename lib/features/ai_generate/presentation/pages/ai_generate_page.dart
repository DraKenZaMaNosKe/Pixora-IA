import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/design/hud_shapes.dart';
import '../../../../core/design/hud_tokens.dart';
import '../../../../core/design/hud_widgets.dart';
import '../../../../core/services/ad_service.dart';
import '../../../../core/services/auth_service.dart';
import '../../../../core/services/credit_service.dart';
import '../../../../core/services/ia_quota_service.dart';
import '../../../../core/services/subscription_service.dart';
import '../../../../core/services/report_service.dart';
import '../../../../core/services/wallpaper_stats_service.dart';
import '../../../../core/utils/locale_helper.dart';
import '../../../../core/widgets/report_content_modal.dart';
import '../../data/prompt_validator.dart';

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

class _AIGeneratePageState extends State<AIGeneratePage>
    with SingleTickerProviderStateMixin {
  static const _nativeChannel = MethodChannel('com.orbix.pixora/wallpaper');

  // Holographic Forge palette — picked 2026-05-16 (matches Inkwell header
  // + Ember nav + Pixora identity foil).
  static const _bg = Color(0xFF1F1B17);
  static const _ivory = Color(0xFFE8E6E0);
  static const _ivoryDim = Color(0x99E8E6E0);
  // Single source of truth — see HudTokens.foilPalette.
  static const _holoColors = HudTokens.foilPalette;

  final _promptController = TextEditingController();
  String? _selectedStyle;
  bool _submitting = false;

  _AIGenerationState? _latest;
  List<_AIGenerationState> _history = const [];
  RealtimeChannel? _queueChannel;
  StreamSubscription<AuthState>? _authSub;
  String? _currentUid;
  final _scrollController = ScrollController();
  late final AnimationController _foilCtrl;

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
    _foilCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat();
    SubscriptionService.instance.refreshStatus();
    _currentUid = Supabase.instance.client.auth.currentUser?.id;
    _subscribeQueue();
    _loadLastGeneration();
    _loadHistory();
    // Listen for sign-in / sign-out so we never show one user's generation
    // to another user. On any user change we fully reset local state and
    // rebind the queue + reload the new user's last generation AND history.
    _authSub = AuthService.instance.authStateChanges.listen((_) {
      final newUid = Supabase.instance.client.auth.currentUser?.id;
      if (newUid == _currentUid) return;
      _currentUid = newUid;
      _queueChannel?.unsubscribe();
      _queueChannel = null;
      if (mounted) {
        setState(() {
          _latest = null;
          _history = const [];
        });
      }
      if (newUid != null) {
        _subscribeQueue();
        _loadLastGeneration();
        _loadHistory();
      }
    });
  }

  @override
  void dispose() {
    _foilCtrl.dispose();
    _promptController.dispose();
    _scrollController.dispose();
    _queueChannel?.unsubscribe();
    _authSub?.cancel();
    super.dispose();
  }

  // ── Data flow (unchanged) ─────────────────────────────────────────────

  void _subscribeQueue() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    // Listen to BOTH insert + update events. Listening only to UPDATE meant
    // that if the user generated something from another device (or even
    // submitted from this device with a race), the new row wouldn't appear
    // here until the user manually refreshed (audit Sprint 1 fix #8).
    void handleChange(payload) {
      final row = payload.newRecord;
      final id = row['id'] as int?;
      if (id == null) return;
      final updated = _AIGenerationState(
        id: id,
        prompt: (row['prompt'] as String?) ?? '',
        status: (row['status'] as String?) ?? 'pending',
        resultUrl: row['result_url'] as String?,
        errorMessage: row['error_message'] as String?,
      );
      setState(() {
        if (_latest != null && _latest!.id == id) {
          _latest = updated;
        }
        if (updated.status == 'done' && updated.resultUrl != null) {
          final already = _history.any((e) => e.id == id);
          if (!already) {
            _history = [updated, ..._history];
          }
        }
      });
    }

    _queueChannel = Supabase.instance.client
        .channel('ia_gen_$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'ia_generation_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: handleChange,
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ia_generation_queue',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: uid,
          ),
          callback: handleChange,
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
    } catch (e) {
      debugPrint('[AIGenerate] _loadLastGeneration failed: $e');
    }
  }

  /// Loads every successful generation the current user ever made, newest
  /// first. Source of truth is `ia_generation_queue`; we only pull rows with
  /// `status='done'` and a non-null `result_url` so broken rows never reach
  /// the grid.
  Future<void> _loadHistory() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await Supabase.instance.client
          .from('ia_generation_queue')
          .select('id, prompt, status, result_url, error_message')
          .eq('user_id', uid)
          .eq('status', 'done')
          .not('result_url', 'is', null)
          .order('created_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _history = (rows as List)
            .map((r) => _AIGenerationState(
                  id: r['id'] as int,
                  prompt: (r['prompt'] as String?) ?? '',
                  status: (r['status'] as String?) ?? 'done',
                  resultUrl: r['result_url'] as String?,
                  errorMessage: r['error_message'] as String?,
                ))
            .toList(growable: false);
      });
    } catch (e) {
      debugPrint('[AIGenerate] _loadHistory failed: $e');
    }
  }

  /// Promotes a history item to the result panel and scrolls to the top so
  /// the user sees the full-size image + action buttons (save / wallpaper /
  /// share). Reuses the existing preview plumbing end-to-end.
  void _selectFromHistory(_AIGenerationState item) {
    setState(() => _latest = item);
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _dispatchWorker(int queueId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'process_ia_queue',
        body: {'queue_id': queueId},
      );
    } catch (e) {
      debugPrint('[AIGenerate] _dispatchWorker failed: $e');
    }
  }

  // ── Gating ────────────────────────────────────────────────────────────

  String get _buttonLabel {
    final sub = SubscriptionService.instance;
    if (!AuthService.instance.isLoggedIn) {
      return LocaleHelper.pick(
        es: 'INICIA SESIÓN PARA GENERAR',
        en: 'SIGN IN TO GENERATE',
      );
    }
    // 2026-06-24 — IaQuotaService rules:
    //   Free:    2000💎/img, cap 1/día
    //   Premium:  30💎/img, cap 5/día + 150💎ddiariosauto
    final q = IaQuotaService.instance;
    final cost = q.currentCost;
    final remaining = q.remainingToday;
    final cap = q.currentDailyCap;
    final balance = CreditService.instance.balance;

    if (remaining <= 0) {
      return LocaleHelper.pick(
        es: 'LÍMITE DIARIO ALCANZADO ($cap/$cap)',
        en: 'DAILY LIMIT REACHED ($cap/$cap)',
      );
    }
    if (balance < cost) {
      if (sub.hasAccess) {
        return 'NECESITAS $cost 💎';
      }
      // Free user sin diamantes suficientes — hard sell
      return LocaleHelper.pick(
        es: 'NECESITAS $cost 💎  ·  o SUSCRÍBETE',
        en: 'NEED $cost 💎  ·  or SUBSCRIBE',
      );
    }
    // Puede generar — muestra costo + cuántas le quedan hoy
    return 'GENERAR · $cost 💎  ·  $remaining/$cap HOY';
  }

  // ── Actions ───────────────────────────────────────────────────────────

  Future<void> _handleGeneratePressed() async {
    final sub = SubscriptionService.instance;

    if (!AuthService.instance.isLoggedIn) {
      _showLoginPrompt();
      return;
    }
    // 2026-06-24 — IaQuotaService gating.
    final q = IaQuotaService.instance;
    if (q.remainingToday <= 0) {
      _showQuotaExhausted();
      return;
    }
    if (CreditService.instance.balance < q.currentCost) {
      if (sub.hasAccess) {
        _snack(LocaleHelper.pick(
          es: 'Necesitas ${q.currentCost} 💎. Mira ads para ganar más.',
          en: 'Need ${q.currentCost} 💎. Watch ads to earn more.',
        ));
      } else {
        _showPaywall();
      }
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

    // 2026-06-20 — Pre-flight content check (Google Play AI policy).
    // Bloquea NSFW / violencia / odio / drogas / celebridades+marcas
    // ANTES de mandar al worker para no quemar créditos del user en un
    // prompt que el modelo va a rechazar igual server-side.
    final blockReason = LocaleHelper.isSpanish
        ? PromptValidator.checkSpanish(prompt)
        : PromptValidator.checkEnglish(prompt);
    if (blockReason != null) {
      _snack(blockReason, color: context.hud.accent);
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
        // 2026-06-24 — cobrar diamantes + record cuota diaria.
        // Spend wrapped en try-catch: si falla server, igual se
        // dispara la generación (server tiene su propio gating).
        try {
          await CreditService.instance.spend(
            IaQuotaService.instance.currentCost,
            reason: 'ia_generation',
          );
        } catch (e) {
          debugPrint('[AIGenerate] spend failed: $e');
        }
        unawaited(IaQuotaService.instance.recordGeneration());
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
      // Timeout 30s — imágenes generadas pueden ser pesadas (~5 MB) y la
      // red del user puede ser lenta. Sin timeout, http.get cuelga forever.
      final resp =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
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
    if (!mounted) return;
    if (file == null) {
      _snack('ERROR: no se pudo descargar', color: context.hud.accent);
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Pixora · Generación ${_latest!.id}',
      ),
    );
  }

  Future<void> _onWallpaper() async {
    // Route through AdService — alternates ad/no-ad, awards credits on
    // dismissal, and is the single point that respects active subscriptions.
    AdService.instance.showInterstitialAd(
        placement: 'ai_generate',
        onAdDismissed: () {
          if (mounted) _doApplyWallpaper();
        });
  }

  Future<void> _doApplyWallpaper() async {
    final file = await _downloadResult();
    if (!mounted) return;
    if (file == null) {
      _snack('ERROR: no se pudo descargar', color: context.hud.accent);
      return;
    }
    try {
      await _nativeChannel.invokeMethod<void>(
        'setWallpaper',
        {'path': file.path},
      );
      // Track install in analytics — bucket all AI-generated wallpapers
      // under a single id so the dashboard shows total AI installs.
      WallpaperStatsService.instance.trackInstall('ai_generated');
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
    if (!mounted) return;
    if (file == null) {
      _snack('ERROR: no se pudo descargar', color: context.hud.accent);
      return;
    }
    WallpaperStatsService.instance.trackShare('ai_generated');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: 'Mira lo que generé con Pixora IA',
      ),
    );
  }

  /// 2026-06-20 — Reporte de contenido IA. Requerido por la política
  /// de contenido generado por IA de Google Play. El modal se encarga
  /// del flujo completo (categorías + descripción + envío + confirmación).
  Future<void> _onReport(_AIGenerationState g) async {
    await showReportContentModal(
      context,
      wallpaperId: 'ai_gen_${g.id}',
      kind: ReportableKind.aiGenerated,
      wallpaperMeta: {
        'gen_id': g.id,
        'prompt': g.prompt,
        'result_url': g.resultUrl,
        'status': g.status,
      },
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
                  es: 'Para generar imágenes con IA necesitas una cuenta de Google. Así protegemos tus diamantes y tu suscripción a través de dispositivos.',
                  en: 'Sign in with Google to generate AI images. This protects your diamonds and subscription across devices.',
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
                  es: '5 IMÁGENES IA AL DÍA · SIN ANUNCIOS',
                  en: '5 AI IMAGES PER DAY · NO ADS',
                ),
                style: HudTokens.mono(
                  size: 11,
                  color: h.accent2,
                  letterSpacing: 0.15,
                ),
              ),
              const SizedBox(height: HudTokens.sp6),
              _benefit('◆', '5 IMÁGENES IA AL DÍA'),
              _benefit('◆', 'SIN ANUNCIOS EN TODA LA APP'),
              _benefit('◆', 'DIAMANTES DIARIOS AUTOMÁTICOS'),
              _benefit('◆', 'SYNC CROSS-DEVICE'),
              _benefit('◆', 'CANCELA CUANDO QUIERAS'),
              const SizedBox(height: HudTokens.sp6),
              HudPrimaryButton(
                label: 'SUSCRIBIRSE',
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
                  es: 'Renovación automática mensual. Cancela cuando quieras desde Google Play.',
                  en: 'Auto-renewing monthly. Cancel anytime from Google Play.',
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
                  es: 'Ya usaste tus 5 generaciones de hoy. Vuelve mañana — tu cuota se renueva cada 24 h.',
                  en: 'You\'ve used today\'s 5 generations. Come back tomorrow — your quota refreshes every 24h.',
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
    return Scaffold(
      backgroundColor: _bg,
      body: ListenableBuilder(
        listenable: Listenable.merge([
          CreditService.instance,
          SubscriptionService.instance,
        ]),
        builder: (context, _) {
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeroCard(),
                if (_latest != null) ...[
                  const SizedBox(height: 22),
                  _buildResultPanel(_latest!),
                ],
                const SizedBox(height: 22),
                _buildPromptInput(),
                const SizedBox(height: 18),
                _buildStyleGrid(),
                const SizedBox(height: 22),
                _HoloForgeButton(
                  controller: _foilCtrl,
                  label: _buttonLabel,
                  busy: _submitting,
                  onPressed: _handleGeneratePressed,
                ),
                if (AuthService.instance.isLoggedIn && _history.isNotEmpty) ...[
                  const SizedBox(height: 32),
                  _buildHistoryGrid(),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeroCard() {
    final sub = SubscriptionService.instance;
    final credits = CreditService.instance.balance;
    final auth = AuthService.instance;

    String statusLine;
    if (!auth.isLoggedIn) {
      statusLine = '> AUTH_REQUIRED · INICIA SESIÓN PARA FORJAR';
    } else if (sub.hasAccess) {
      statusLine =
          '> CUOTA: ${sub.generationsRemaining}/${sub.generationsLimit} ESTE MES';
    } else if (sub.freeGensRemaining > 0) {
      statusLine = '> ${sub.freeGensRemaining} FORJADAS GRATIS RESTANTES';
    } else {
      statusLine = '> SUSCRÍBETE PARA DESBLOQUEAR';
    }

    return _HoloFrame(
      controller: _foilCtrl,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mono eyebrow + model selector chip
          Row(
            children: [
              Text(
                '// PIXORA · AI FORGE',
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE0B47A),
                  letterSpacing: 2.2,
                ),
              ),
              const Spacer(),
              _HoloPill(
                controller: _foilCtrl,
                child: Text(
                  'NANO_BANANA',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: _ivory,
                    letterSpacing: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Iridescent title "Forja un wallpaper"
          AnimatedBuilder(
            animation: _foilCtrl,
            builder: (_, __) {
              final shift = _foilCtrl.value;
              return ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment(-1 + shift * 2, 0),
                  end: Alignment(1 + shift * 2, 0),
                  colors: _holoColors,
                ).createShader(rect),
                blendMode: BlendMode.srcIn,
                child: Text(
                  'Forja un\nwallpaper.',
                  style: GoogleFonts.fraunces(
                    fontSize: 32,
                    fontStyle: FontStyle.italic,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -0.6,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            statusLine,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _ivoryDim,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          // Cost row — your diamonds + cost per forge
          Row(
            children: [
              _HoloPill(
                controller: _foilCtrl,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('💎', style: TextStyle(fontSize: 12)),
                    const SizedBox(width: 4),
                    Text('$credits',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ivory,
                          letterSpacing: 0.5,
                        )),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HoloPill(
                controller: _foilCtrl,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('COSTO',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: _ivoryDim,
                          letterSpacing: 1.6,
                        )),
                    const SizedBox(width: 6),
                    Text('30 💎',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _ivory,
                          letterSpacing: 0.5,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromptInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '// PROMPT',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE0B47A),
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 6),
        // 2026-06-20 — Disclaimer requerido por la política de
        // contenido generado por IA de Google Play. Texto subtle
        // pero claro para que el user sepa qué NO se permite.
        Text(
          LocaleHelper.pick(
            es: 'No generamos contenido sexual, violento, con drogas, odio, marcas registradas ni personas reales.',
            en: 'We do not generate sexual, violent, drug-related, hateful, trademark or real-person content.',
          ),
          style: GoogleFonts.jetBrainsMono(
            fontSize: 9,
            color: _ivoryDim,
            height: 1.4,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 8),
        _HoloFrame(
          controller: _foilCtrl,
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: _promptController,
            maxLines: 3,
            maxLength: 1000,
            style: GoogleFonts.fraunces(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: _ivory,
              height: 1.4,
            ),
            cursorColor: const Color(0xFF67E8F9),
            decoration: InputDecoration(
              hintText:
                  'un dragón cyberpunk sobre una ciudad neón en la noche…',
              hintStyle: GoogleFonts.fraunces(
                fontSize: 15,
                fontStyle: FontStyle.italic,
                color: _ivoryDim,
              ),
              border: InputBorder.none,
              counterStyle: GoogleFonts.jetBrainsMono(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: _ivoryDim,
                letterSpacing: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '// ESTILO',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFFE0B47A),
            letterSpacing: 2.2,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _styles.map((style) {
            final selected = _selectedStyle == style;
            return _HoloStyleChip(
              controller: _foilCtrl,
              label: style,
              selected: selected,
              onTap: () =>
                  setState(() => _selectedStyle = selected ? null : style),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// Classic Grid — 2-col history of every successful generation. Tap a cell
  /// to promote it into the result panel above (reuses save / wallpaper /
  /// share actions). Newest first.
  Widget _buildHistoryGrid() {
    final h = context.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              '// MIS_CREACIONES',
              style: HudTokens.display(
                size: 12,
                color: h.accent,
                letterSpacing: 0.1,
              ),
            ),
            const Spacer(),
            HudBadge(
              text: '${_history.length}',
              color: h.surface,
              onColor: h.accent2,
            ),
          ],
        ),
        const SizedBox(height: HudTokens.sp3),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: HudTokens.sp2,
            crossAxisSpacing: HudTokens.sp2,
            childAspectRatio: 3 / 4,
          ),
          itemCount: _history.length,
          itemBuilder: (context, index) {
            final item = _history[index];
            final isSelected = _latest?.id == item.id;
            return _HistoryCell(
              item: item,
              isSelected: isSelected,
              onTap: () => _selectFromHistory(item),
            );
          },
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
        cacheWidth: 640,
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
          // 2026-06-20 — Botón "Reportar" requerido por política de
          // contenido generado por IA de Google Play (v1.7.28 fue
          // rechazada por NO tener esta función). Estilo subtle —
          // solo texto + flag — para no competir con los CTAs de
          // arriba; el rol del botón es defensivo, no comercial.
          const SizedBox(height: HudTokens.sp2),
          Center(
            child: TextButton.icon(
              onPressed: () => _onReport(g),
              icon: const Icon(
                Icons.flag_outlined,
                size: 14,
                color: Color(0xFF98989D),
              ),
              label: Text(
                LocaleHelper.pick(
                  es: 'Reportar contenido',
                  en: 'Report content',
                ),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: const Color(0xFF98989D),
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: const Size(0, 32),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// One tile in the Classic Grid history. Isolated widget so repaint stays
/// local and the grid can lazy-render hundreds of cells without jank.
class _HistoryCell extends StatelessWidget {
  const _HistoryCell({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  final _AIGenerationState item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final h = context.hud;
    final url = item.resultUrl;
    return GestureDetector(
      onTap: onTap,
      child: RepaintBoundary(
        child: Container(
          decoration: BoxDecoration(
            color: h.surface,
            border: Border.all(
              color: isSelected ? h.accent2 : h.divider,
              width: isSelected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: url == null
              ? Center(
                  child: Icon(Icons.broken_image, color: h.textDim, size: 24),
                )
              : Image.network(
                  url,
                  fit: BoxFit.cover,
                  cacheWidth: 280,
                  loadingBuilder: (ctx, child, progress) {
                    if (progress == null) return child;
                    return Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: h.accent,
                          strokeWidth: 1.5,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, __, ___) => Center(
                    child: Icon(Icons.broken_image, color: h.textDim, size: 24),
                  ),
                ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════
//  Holographic Forge widgets — iridescent foil family.
// ═════════════════════════════════════════════════════════════════════

// Single source of truth — see HudTokens.foilPalette.
const _holoColorsModule = HudTokens.foilPalette;

const _bgModule = Color(0xFF1F1B17);
const _surfaceModule = Color(0xFF2A2418);

/// Box with an animated 1.5px foil-gradient border that shifts continuously.
class _HoloFrame extends StatelessWidget {
  const _HoloFrame({
    required this.controller,
    required this.child,
    this.padding = EdgeInsets.zero,
  });
  final AnimationController controller;
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final shift = controller.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              begin: Alignment(-1 + shift * 2, 0),
              end: Alignment(1 + shift * 2, 0),
              colors: _holoColorsModule,
            ),
          ),
          padding: const EdgeInsets.all(1.5),
          child: Container(
            decoration: BoxDecoration(
              color: _surfaceModule,
              borderRadius: BorderRadius.circular(9),
            ),
            padding: padding,
            child: child,
          ),
        );
      },
    );
  }
}

/// Small pill wrapper with iridescent border (mono labels, badges).
class _HoloPill extends StatelessWidget {
  const _HoloPill({required this.controller, required this.child});
  final AnimationController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, __) {
        final shift = controller.value;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(
              begin: Alignment(-1 + shift * 2, 0),
              end: Alignment(1 + shift * 2, 0),
              colors: _holoColorsModule,
            ),
          ),
          padding: const EdgeInsets.all(1),
          child: Container(
            decoration: BoxDecoration(
              color: _bgModule,
              borderRadius: BorderRadius.circular(999),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: child,
          ),
        );
      },
    );
  }
}

/// Style chip: inactive = foil border only, active = full foil fill.
class _HoloStyleChip extends StatelessWidget {
  const _HoloStyleChip({
    required this.controller,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final AnimationController controller;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final shift = controller.value;
          final foil = LinearGradient(
            begin: Alignment(-1 + shift * 2, 0),
            end: Alignment(1 + shift * 2, 0),
            colors: _holoColorsModule,
          );
          if (selected) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: foil,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFE0B47A).withValues(alpha: 0.45),
                    blurRadius: 12,
                    spreadRadius: -2,
                  ),
                ],
              ),
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1F1B17),
                  letterSpacing: 1.4,
                ),
              ),
            );
          }
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: foil,
            ),
            padding: const EdgeInsets.all(1),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: _bgModule,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                label.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFFE8E6E0),
                  letterSpacing: 1.4,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The big "✦ FORJAR ✦" CTA — full iridescent rectangle with shadow.
class _HoloForgeButton extends StatelessWidget {
  const _HoloForgeButton({
    required this.controller,
    required this.label,
    required this.busy,
    required this.onPressed,
  });
  final AnimationController controller;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onPressed,
      child: AnimatedBuilder(
        animation: controller,
        builder: (_, __) {
          final shift = controller.value;
          return Container(
            height: 58,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                begin: Alignment(-1 + shift * 2, 0),
                end: Alignment(1 + shift * 2, 0),
                colors: _holoColorsModule,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE0B47A).withValues(alpha: 0.5),
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: const Offset(0, 6),
                ),
                BoxShadow(
                  color: const Color(0xFF6EE7B7).withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: -4,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: busy
                ? const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xFF1F1B17),
                    ),
                  )
                : FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '✦  ${label.toUpperCase()}  ✦',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                      style: GoogleFonts.fraunces(
                        fontSize: 17,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF1F1B17),
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
