// lib/core/services/billing/disabled_purchase_gateway.dart
import 'dart:async';

import 'purchase_gateway.dart';

/// A no-op gateway for a flavor whose store billing isn't wired yet. Used by
/// the `samsung` flavor until F3 ships the real SamsungPurchaseGateway. It is
/// "purchases OFF": the store is never available, no products load, buy()
/// reports the sheet was not launched, and nothing is ever emitted.
class DisabledPurchaseGateway implements PurchaseGateway {
  DisabledPurchaseGateway();

  @override
  Store get store => Store.samsung;

  final _controller = StreamController<StorePurchase>.broadcast();

  @override
  Stream<StorePurchase> get purchases => _controller.stream;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<List<StoreProduct>> queryProducts(Set<String> logicalIds) async =>
      const <StoreProduct>[];

  @override
  Future<bool> buy(StoreProduct product) async => false;

  @override
  Future<void> finish(StorePurchase purchase, {required bool consume}) async {}

  @override
  Future<void> restore() async {}

  @override
  Uri? manageSubscriptionUri(String logicalId) => null;

  @override
  void dispose() {
    _controller.close();
  }
}
