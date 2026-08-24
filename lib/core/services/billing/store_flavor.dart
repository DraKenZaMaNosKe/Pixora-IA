// lib/core/services/billing/store_flavor.dart
//
// Maps the compiled Gradle flavor (Flutter's `appFlavor`) to a Store and
// builds the matching purchase gateway. `appFlavor` is null on iOS and on a
// no-flavor debug run — default to Store.play so those paths never break.
import 'package:flutter/services.dart' show appFlavor;

import 'disabled_purchase_gateway.dart';
import 'play_purchase_gateway.dart';
import 'purchase_gateway.dart';

Store get currentStore =>
    switch (appFlavor) { 'samsung' => Store.samsung, _ => Store.play };

/// Builds the purchase gateway for the current flavor. Play uses the real
/// Google Play gateway; Samsung uses a disabled gateway (purchases OFF) until
/// the real SamsungPurchaseGateway lands in F3.
PurchaseGateway createPurchaseGateway() => switch (currentStore) {
      Store.play => PlayPurchaseGateway(),
      Store.samsung => DisabledPurchaseGateway(),
    };
