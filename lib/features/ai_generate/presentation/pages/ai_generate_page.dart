import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  final _promptController = TextEditingController();
  String? _selectedStyle;
  bool _submitting = false;

  _AIGenerationState? _latest;
  RealtimeChannel? _queueChannel;

  final _styles = [
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
    // Make sure we have fresh subscription + credits state when the page opens.
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

  /// Subscribe to Realtime changes on ia_generation_queue filtered by user.
  /// When a row transitions to processing/done/failed, refresh the visible card.
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

  /// On page open, show the most recent generation (if any) so users see
  /// their history across sessions.
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
      // If the latest is still pending, kick the worker — covers rows orphaned
      // by a previous session crash or pre-worker enqueues.
      if (_latest!.status == 'pending') {
        unawaited(_dispatchWorker(_latest!.id));
      }
    } catch (_) {
      // Non-critical; ignore.
    }
  }

  /// Fire-and-forget call to process_ia_queue. The worker does the Gemini call
  /// and uploads the result; realtime will reflect the status change in the UI.
  Future<void> _dispatchWorker(int queueId) async {
    try {
      await Supabase.instance.client.functions.invoke(
        'process_ia_queue',
        body: {'queue_id': queueId},
      );
    } catch (_) {
      // Worker errors surface in the DB row (status=failed) and are handled by
      // the realtime listener. Swallow here — we don't want to show two errors.
    }
  }

  // ── Gating ──────────────────────────────────────────────────────────

  /// True if the user can enqueue a generation right now.
  /// - Not authenticated: no.
  /// - Has `free_gens_remaining > 0`: yes (they get 2 free trials before paywall).
  /// - Has active subscription with quota left: yes.
  /// - Has active subscription but quota out, with >=30 credits: yes (extra path).
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
          es: 'Inicia sesión para generar', en: 'Sign in to generate');
    }
    if (sub.freeGensRemaining > 0) {
      return LocaleHelper.pick(
        es: 'Generar — ${sub.freeGensRemaining} gratis',
        en: 'Generate — ${sub.freeGensRemaining} free',
      );
    }
    if (!sub.hasAccess) {
      return LocaleHelper.pick(
        es: 'Suscríbete — \$99 MXN/mes',
        en: 'Subscribe — \$99 MXN/month',
      );
    }
    if (sub.generationsRemaining > 0) {
      return LocaleHelper.pick(
        es: 'Generar (${sub.generationsRemaining} restantes este mes)',
        en: 'Generate (${sub.generationsRemaining} left this month)',
      );
    }
    // Out of monthly quota — can use extra credits
    if (CreditService.instance.balance >= 30) {
      return LocaleHelper.pick(
        es: 'Generar — 30 créditos extra',
        en: 'Generate — 30 extra credits',
      );
    }
    return LocaleHelper.pick(
      es: 'Cuota mensual agotada',
      en: 'Monthly quota reached',
    );
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _handleGeneratePressed() async {
    final sub = SubscriptionService.instance;

    if (!AuthService.instance.isLoggedIn) {
      _showLoginPrompt();
      return;
    }

    // No free gens, no subscription → paywall
    if (sub.freeGensRemaining == 0 && !sub.hasAccess) {
      _showPaywall();
      return;
    }

    // Out of monthly quota and insufficient credits → inform
    if (sub.hasAccess &&
        sub.generationsRemaining == 0 &&
        CreditService.instance.balance < 30) {
      _showQuotaExhausted();
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.length < 3) {
      _snack(LocaleHelper.pick(
        es: 'Describe tu imagen (al menos 3 caracteres).',
        en: 'Describe your image (at least 3 characters).',
      ));
      return;
    }

    setState(() => _submitting = true);
    try {
      final response = await Supabase.instance.client.rpc(
        'enqueue_generation',
        params: {
          'p_prompt': prompt,
          'p_style': _selectedStyle,
        },
      );
      // The server has deducted quota/credits atomically. Refresh state so
      // the button label updates and the UI reflects the new counter.
      await Future.wait([
        SubscriptionService.instance.refreshStatus(),
      ]);
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
        // Fire the worker — Gemini call + upload happens server-side, realtime
        // will drive the UI forward.
        unawaited(_dispatchWorker(queueId));
      }
      _snack(
        LocaleHelper.pick(
          es: 'Generando...',
          en: 'Generating...',
        ),
        color: Colors.green.shade700,
      );
      _promptController.clear();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      _snack(_translateError(e.message), color: Colors.red);
    } catch (e) {
      if (!mounted) return;
      _snack(
          LocaleHelper.pick(
            es: 'Error inesperado: $e',
            en: 'Unexpected error: $e',
          ),
          color: Colors.red);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _translateError(String msg) {
    if (msg.contains('prompt_blocked_moderation')) {
      return LocaleHelper.pick(
        es: 'Ese prompt no está permitido.',
        en: 'That prompt is not allowed.',
      );
    }
    if (msg.contains('subscription_required')) {
      return LocaleHelper.pick(
        es: 'Se requiere suscripción activa.',
        en: 'Active subscription required.',
      );
    }
    if (msg.contains('insufficient_credits')) {
      return LocaleHelper.pick(
        es: 'No tienes suficientes créditos.',
        en: 'Not enough credits.',
      );
    }
    if (msg.contains('daily_cap_reached')) {
      return LocaleHelper.pick(
        es: 'Alcanzaste el máximo diario (20 generaciones). Vuelve mañana.',
        en: 'Daily cap reached (20 generations). Come back tomorrow.',
      );
    }
    if (msg.contains('too_many_pending')) {
      return LocaleHelper.pick(
        es: 'Demasiadas generaciones en cola. Espera a que terminen.',
        en: 'Too many pending generations. Wait for them to finish.',
      );
    }
    if (msg.contains('prompt_too_short')) {
      return LocaleHelper.pick(
        es: 'El prompt es muy corto (mínimo 3 caracteres).',
        en: 'Prompt is too short (min 3 chars).',
      );
    }
    if (msg.contains('prompt_too_long')) {
      return LocaleHelper.pick(
        es: 'El prompt es muy largo (máx 1000 caracteres).',
        en: 'Prompt is too long (max 1000 chars).',
      );
    }
    return msg;
  }

  void _snack(String text, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: color),
    );
  }

  void _showLoginPrompt() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: Text(LocaleHelper.pick(
          es: 'Inicia sesión',
          en: 'Sign in required',
        )),
        content: Text(LocaleHelper.pick(
          es: 'Para generar imágenes con IA necesitas una cuenta de Google. Así protegemos tus créditos y tu suscripción a través de dispositivos.',
          en: 'Sign in with Google to generate AI images. This protects your credits and subscription across devices.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleHelper.pick(es: 'Más tarde', en: 'Later')),
          ),
        ],
      ),
    );
  }

  Future<void> _showPaywall() async {
    final sub = SubscriptionService.instance;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14101F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Icon(Icons.auto_awesome,
                  size: 42, color: Color(0xFF00E5FF)),
              const SizedBox(height: 8),
              Text(
                LocaleHelper.pick(es: 'Pixora Plus', en: 'Pixora Plus'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                LocaleHelper.pick(
                  es: 'Generaciones con IA ilimitadas al mes',
                  en: 'AI generations every month',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 24),
              _benefit(
                  Icons.auto_awesome,
                  LocaleHelper.pick(
                      es: '100 imágenes al mes con IA',
                      en: '100 AI images per month')),
              _benefit(
                  Icons.card_giftcard,
                  LocaleHelper.pick(
                      es: '7 días gratis de prueba', en: '7-day free trial')),
              _benefit(
                  Icons.sync_alt,
                  LocaleHelper.pick(
                      es: 'Acceso en todos tus dispositivos',
                      en: 'Access on all your devices')),
              _benefit(
                  Icons.cancel_outlined,
                  LocaleHelper.pick(
                      es: 'Cancela cuando quieras', en: 'Cancel anytime')),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: sub.purchaseInFlight
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          final ok =
                              await SubscriptionService.instance.buyMonthly();
                          if (!ok && mounted) {
                            _snack(LocaleHelper.pick(
                              es: 'No se pudo abrir el flujo de compra. Revisa que tu cuenta Google Play esté activa.',
                              en: 'Could not open purchase flow. Check that your Google Play account is active.',
                            ));
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C4DFF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    LocaleHelper.pick(
                      es: 'Empezar prueba gratuita · \$99 MXN/mes después',
                      en: 'Start free trial · \$99 MXN/month after',
                    ),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                LocaleHelper.pick(
                  es: 'Cobro automático al terminar los 7 días. Cancela desde Google Play antes para no pagar.',
                  en: 'Auto-charged after 7 days. Cancel in Google Play anytime before then to avoid payment.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.white38,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _benefit(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF00E5FF), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  void _showQuotaExhausted() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1a1a1a),
        title: Text(LocaleHelper.pick(
          es: 'Cuota mensual agotada',
          en: 'Monthly quota reached',
        )),
        content: Text(LocaleHelper.pick(
          es: 'Ya usaste las 100 generaciones de este mes. Puedes esperar al próximo ciclo, o gastar 30 créditos (viendo ads) para una generación extra.',
          en: 'You\'ve used this month\'s 100 generations. Wait for next cycle, or spend 30 credits (earned from ads) for an extra generation.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(LocaleHelper.pick(es: 'Entendido', en: 'OK')),
          ),
        ],
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([
          CreditService.instance,
          SubscriptionService.instance,
        ]),
        builder: (context, _) {
          final sub = SubscriptionService.instance;
          final canTap = _canGenerateNow && !_submitting;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(sub),
                const SizedBox(height: 24),
                Text(
                  LocaleHelper.pick(
                    es: 'Describe tu imagen',
                    en: 'Describe your image',
                  ),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _promptController,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    hintText: LocaleHelper.pick(
                      es: 'Un dragón cyberpunk sobre una ciudad neón en la noche...',
                      en: 'A cyberpunk dragon flying over neon city at night...',
                    ),
                    filled: true,
                    fillColor: Colors.white10,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  LocaleHelper.pick(es: 'Estilo', en: 'Style'),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _styles.map((style) {
                    final selected = _selectedStyle == style;
                    return ChoiceChip(
                      label: Text(style),
                      selected: selected,
                      onSelected: (v) {
                        setState(() => _selectedStyle = v ? style : null);
                      },
                      backgroundColor: Colors.white10,
                      selectedColor: const Color(0xFF7C4DFF).withOpacity(0.3),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                if (_latest != null) ...[
                  const SizedBox(height: 8),
                  _buildGenerationCard(_latest!),
                  const SizedBox(height: 16),
                ],
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: canTap
                        ? _handleGeneratePressed
                        : _handleGeneratePressed,
                    // Note: we route through _handleGeneratePressed even when
                    // !canGenerate so users get a contextual modal (paywall,
                    // login prompt, etc) instead of a dead button.
                    icon: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.auto_awesome, size: 20),
                    label: Text(_buttonLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canGenerateNow
                          ? const Color(0xFF7C4DFF)
                          : const Color(0xFF7C4DFF).withOpacity(0.4),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildGenerationCard(_AIGenerationState g) {
    Widget content;
    if (g.status == 'done' && g.resultUrl != null) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: Image.network(
            g.resultUrl!,
            fit: BoxFit.cover,
            loadingBuilder: (ctx, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF00E5FF)),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 200,
              child: Center(
                child: Icon(Icons.broken_image, color: Colors.white38),
              ),
            ),
          ),
        ),
      );
    } else if (g.status == 'failed') {
      content = Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.4)),
        ),
        child: Column(
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(
              LocaleHelper.pick(
                es: 'La generación falló. Tu cuota no se consumió.',
                en: 'Generation failed. Your quota was not consumed.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
            if (g.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                g.errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      );
    } else {
      // pending or processing — show a shimmer-like spinner
      content = Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF00E5FF),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                g.status == 'processing'
                    ? LocaleHelper.pick(
                        es: 'Generando imagen...',
                        en: 'Generating image...',
                      )
                    : LocaleHelper.pick(
                        es: 'En cola...',
                        en: 'Queued...',
                      ),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          LocaleHelper.pick(
            es: 'Última generación',
            en: 'Latest generation',
          ),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 8),
        content,
      ],
    );
  }

  Widget _buildHeader(SubscriptionService sub) {
    final auth = AuthService.instance;
    final credits = CreditService.instance.balance;

    String statusText;
    if (!auth.isLoggedIn) {
      statusText = LocaleHelper.pick(
        es: 'Inicia sesión para generar',
        en: 'Sign in to generate',
      );
    } else if (sub.hasAccess) {
      statusText = LocaleHelper.pick(
        es: 'Pixora Plus · ${sub.generationsRemaining}/${sub.generationsLimit} este mes',
        en: 'Pixora Plus · ${sub.generationsRemaining}/${sub.generationsLimit} this month',
      );
    } else if (sub.freeGensRemaining > 0) {
      statusText = LocaleHelper.pick(
        es: '${sub.freeGensRemaining} generaciones de prueba restantes',
        en: '${sub.freeGensRemaining} trial generations remaining',
      );
    } else {
      statusText = LocaleHelper.pick(
        es: 'Suscríbete para generar con IA',
        en: 'Subscribe to generate with AI',
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2A1655), Color(0xFF0F2A3E)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.auto_awesome, color: Color(0xFF00E5FF), size: 28),
              SizedBox(width: 10),
              Text(
                'AI Generator',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            statusText,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.diamond, size: 20, color: Color(0xFF00E5FF)),
                const SizedBox(width: 8),
                Text(
                  LocaleHelper.pick(
                    es: '$credits diamantes',
                    en: '$credits diamonds',
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
