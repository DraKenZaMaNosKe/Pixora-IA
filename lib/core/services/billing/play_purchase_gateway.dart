// lib/core/services/billing/play_purchase_gateway.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'product_catalog.dart';
import 'purchase_gateway.dart';

/// Google Play implementation of [PurchaseGateway]. Owns the only
/// `in_app_purchase` usage in the app. Translates Play's `PurchaseDetails`
/// into store-agnostic `StorePurchase` events.
class PlayPurchaseGateway implements PurchaseGateway {
  PlayPurchaseGateway();

  @override
  Store get store => Store.play;

  final _iap = InAppPurchase.instance;
  final _controller = StreamController<StorePurchase>.broadcast();
  StreamSubscription<List<PurchaseDetails>>? _sub;

  // Cache ProductDetails by logicalId (from queryProducts) so buy() can find
  // the object Play needs, and PurchaseDetails by transactionId so finish()
  // can complete the right one — without leaking Play types across the API.
  final Map<String, ProductDetails> _detailsByLogicalId = {};
  final Map<String, PurchaseDetails> _pendingByTxn = {};

  bool _listening = false;

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<bool> isAvailable() async {
    final ok = await _iap.isAvailable();
    if (ok && !_listening) {
      _sub = _iap.purchaseStream.listen(
        _onPlayUpdate,
        onError: (Object e) => debugPrint('[PlayGW] purchaseStream error: $e'),
      );
      _listening = true;
    }
    return ok;
  }

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds) async {
    final skus =
        logicalIds.map((id) => ProductCatalog.skuFor(Store.play, id)).toSet();
    final resp = await _iap.queryProductDetails(skus);
    if (resp.error != null) {
      debugPrint('[PlayGW] queryProductDetails error: ${resp.error}');
    }
    if (resp.notFoundIDs.isNotEmpty) {
      debugPrint('[PlayGW] SKUs not found on Play: ${resp.notFoundIDs} '
          '(unpublished or still propagating, up to 24h)');
    }
    final out = <StoreProduct>[];
    for (final p in resp.productDetails) {
      // In F0 the Play SKU equals the logical ID.
      final logicalId = p.id;
      _detailsByLogicalId[logicalId] = p;
      out.add(StoreProduct(
        logicalId: logicalId,
        storeSku: p.id,
        kind: ProductCatalog.kindFor(logicalId),
        title: p.title,
        formattedPrice: p.price,
        currencyCode: p.currencyCode,
        subscriptionPeriod: null,
      ));
    }
    return out;
  }

  @override
  Future<bool> buy(StoreProduct product) async {
    final details = _detailsByLogicalId[product.logicalId];
    if (details == null) {
      debugPrint('[PlayGW] buy: no ProductDetails cached for '
          '${product.logicalId} — call queryProducts first');
      return false;
    }
    final param = PurchaseParam(productDetails: details);
    // Subscriptions use buyNonConsumable per in_app_purchase docs.
    final shown = await _iap.buyNonConsumable(purchaseParam: param);
    if (!shown) debugPrint('[PlayGW] buyNonConsumable returned false');
    return shown;
  }

  @override
  Future<void> restore() async {
    await _iap.restorePurchases();
  }

  @override
  Future<void> finish(StorePurchase purchase, {required bool consume}) async {
    final details = _pendingByTxn.remove(purchase.transactionId);
    if (details == null) return;
    if (details.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(details);
      } catch (e) {
        debugPrint('[PlayGW] completePurchase failed: $e');
      }
    }
  }

  @override
  Uri? manageSubscriptionUri(String logicalId) {
    final sku = ProductCatalog.skuFor(Store.play, logicalId);
    return Uri.parse(
        'https://play.google.com/store/account/subscriptions?sku=$sku&package=com.orbix.pixora');
  }

  @override
  void dispose() {
    _sub?.cancel();
    _controller.close();
  }

  void _onPlayUpdate(List<PurchaseDetails> list) {
    for (final p in list) {
      _pendingByTxn[p.verificationData.serverVerificationData] = p;
      final state = switch (p.status) {
        PurchaseStatus.pending => PurchaseState.pending,
        PurchaseStatus.purchased => PurchaseState.purchased,
        PurchaseStatus.restored => PurchaseState.purchased,
        PurchaseStatus.canceled => PurchaseState.canceled,
        PurchaseStatus.error => PurchaseState.failed,
      };
      _controller.add(StorePurchase(
        store: Store.play,
        logicalId: p.productID, // Play SKU == logical ID in F0
        transactionId: p.verificationData.serverVerificationData,
        state: state,
        isRestored: p.status == PurchaseStatus.restored,
        errorMessage: p.error?.message,
        verificationBlob: {
          'purchaseToken': p.verificationData.serverVerificationData,
          'productId': p.productID,
          'source': p.verificationData.source,
        },
      ));
    }
  }
}
