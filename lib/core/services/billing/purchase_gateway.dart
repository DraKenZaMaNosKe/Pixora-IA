// lib/core/services/billing/purchase_gateway.dart
//
// Store-agnostic purchase abstraction. No Play/Samsung SDK types leak across
// this boundary — the opaque `verificationBlob` is the deliberate exception,
// interpreted only server-side. See the F0 plan / Samsung Galaxy Store spec.

enum Store { play, samsung }

enum ProductKind { consumable, nonConsumable, subscription }

enum PurchaseState { pending, purchased, canceled, failed }

class StoreProduct {
  const StoreProduct({
    required this.logicalId,
    required this.storeSku,
    required this.kind,
    required this.title,
    required this.formattedPrice,
    required this.currencyCode,
    this.subscriptionPeriod,
  });

  final String logicalId; // Pixora-internal ID, e.g. 'pixora_monthly'
  final String storeSku; // real ID registered in that store
  final ProductKind kind;
  final String title;
  final String formattedPrice; // store-localized; NEVER parse
  final String currencyCode;
  final String? subscriptionPeriod; // ISO-8601, e.g. 'P1M'
}

class StorePurchase {
  const StorePurchase({
    required this.store,
    required this.logicalId,
    required this.transactionId,
    required this.state,
    required this.verificationBlob,
    this.isRestored = false,
    this.errorMessage,
  });

  final Store store;
  final String logicalId;
  final String transactionId; // purchaseToken (Play) | purchaseId (Samsung)
  final PurchaseState state;
  final Map<String, dynamic> verificationBlob; // opaque; server-only
  final bool isRestored;
  final String? errorMessage;
}

abstract class PurchaseGateway {
  Store get store;

  Future<bool> isAvailable();

  /// Fetch store details for the given Pixora logical IDs.
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds);

  /// The ONLY channel for purchase results: new buys, resolved pendings,
  /// and restores (isRestored=true).
  Stream<StorePurchase> get purchases;

  /// Launch the store purchase flow. Returns true if the purchase flow was
  /// successfully launched — NOT that the purchase completed. The real
  /// purchase result always arrives asynchronously via [purchases]. Returns
  /// false if the store declined to show the sheet (client busy, stale
  /// product, etc.).
  Future<bool> buy(StoreProduct product);

  /// Unifies acknowledge/consume/completePurchase. Call only AFTER the
  /// server has verified the purchase.
  Future<void> finish(StorePurchase purchase, {required bool consume});

  /// Re-emits owned products via [purchases] with isRestored=true.
  Future<void> restore();

  /// Deep link to the store's "manage subscription" screen, or null.
  Uri? manageSubscriptionUri(String logicalId);

  void dispose();
}
