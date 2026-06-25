import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/design/hud_tokens.dart';
import '../../../core/services/auth_service.dart';

/// Lists subscription rows for the signed-in user, pulled from the
/// `user_subscriptions` table. Note: this is NOT a per-charge history —
/// `user_subscriptions` keeps ONE row per (user, product) that gets updated
/// on each renewal. Each renewal updates `renewed_at` and `expires_at`.
///
/// Schema (relevant columns):
///   - user_id           uuid
///   - product_id        text   (pixora_monthly, etc.)
///   - tier              text   (monthly / quarterly / yearly)
///   - status            text   (trial / active / in_grace_period / on_hold /
///                                paused / cancelled / expired / refunded)
///   - started_at        timestamptz
///   - trial_ends_at     timestamptz
///   - expires_at        timestamptz
///   - renewed_at        timestamptz
///   - cancelled_at      timestamptz
///   - order_id          text   (Google Play order id)
///   - metadata          jsonb  (raw Google receipt — includes price)
class PaymentHistoryPage extends StatefulWidget {
  const PaymentHistoryPage({super.key});

  @override
  State<PaymentHistoryPage> createState() => _PaymentHistoryPageState();
}

class _PaymentHistoryPageState extends State<PaymentHistoryPage> {
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
          .from('user_subscriptions')
          .select(
              'id, product_id, tier, status, started_at, trial_ends_at, expires_at, renewed_at, cancelled_at, order_id, metadata')
          .eq('user_id', user.id)
          .order('started_at', ascending: false)
          .limit(50);
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
          'Historial de pagos',
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
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: rows.length,
            separatorBuilder: (_, __) => Divider(color: h.divider, height: 24),
            itemBuilder: (_, i) => _PaymentRow(payment: rows[i], h: h),
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
          Icon(Icons.receipt_long_outlined, size: 56, color: h.textDim),
          const SizedBox(height: 18),
          Text(
            'Sin pagos aún',
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
            'Cuando te suscribas a Pixora Pro, aquí verás cada cargo procesado.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: h.textDim, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.payment, required this.h});
  final Map<String, dynamic> payment;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final productId = (payment['product_id'] as String?) ?? 'pixora_monthly';
    final tier = (payment['tier'] as String?) ?? 'monthly';
    final status = (payment['status'] as String?) ?? 'active';
    final startedAt = payment['started_at'] != null
        ? DateTime.tryParse(payment['started_at'].toString())
        : null;
    // user_subscriptions doesn't keep amount/currency directly — derive from
    // product_id. Adjust here if more SKUs are added.
    // 2026-06-24 — pricing v1.7.37: mensual $199 MXN ($9.99 USD),
    // trimestral $499 (~17% off), anual $1799 (~25% off).
    final (amountMxn, currency) = switch (productId) {
      'pixora_monthly' => (199.0, 'MXN'),
      'pixora_quarterly' => (499.0, 'MXN'),
      'pixora_yearly' => (1799.0, 'MXN'),
      _ => (0.0, 'MXN'),
    };
    final tierLabel = switch (tier) {
      'monthly' => 'mensual',
      'quarterly' => 'trimestral',
      'yearly' => 'anual',
      _ => tier,
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: h.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.credit_card, color: h.accent, size: 18),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pixora Pro · $tierLabel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: h.text,
                    ),
                  ),
                  Text(
                    '\$${amountMxn.toStringAsFixed(2)} $currency',
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: h.accent,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  if (startedAt != null)
                    Text(
                      _formatDate(startedAt),
                      style: TextStyle(fontSize: 12, color: h.textDim),
                    ),
                  const SizedBox(width: 10),
                  _StatusBadge(status: status, h: h),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.h});
  final String status;
  final HudTheme h;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'trial' => ('PRUEBA', const Color(0xFF60A5FA)),
      'active' => ('ACTIVA', const Color(0xFF34D399)),
      'in_grace_period' => ('GRACIA', const Color(0xFFD9B14A)),
      'on_hold' => ('EN ESPERA', const Color(0xFFD9B14A)),
      'paused' => ('PAUSADA', const Color(0xFF999999)),
      'cancelled' => ('CANCELADA', const Color(0xFFD9B14A)),
      'expired' => ('EXPIRADA', const Color(0xFF999999)),
      'refunded' => ('REEMBOLSADA', const Color(0xFFCC4545)),
      _ => (status.toUpperCase(), h.textDim),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
        ),
      ),
    );
  }
}
