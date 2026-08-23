// lib/core/services/billing/product_catalog.dart
import 'purchase_gateway.dart';

/// Maps Pixora-internal logical product IDs to the real SKU registered in
/// each store. In F0 only Play exists and the SKU equals the logical ID.
/// When Samsung is added (F1+), its SKU column is filled here — nothing else
/// in the app needs to change.
class ProductCatalog {
  ProductCatalog._();

  static const String monthly = 'pixora_monthly';

  static Set<String> get allLogicalIds => const {monthly};

  static ProductKind kindFor(String logicalId) {
    switch (logicalId) {
      case monthly:
        return ProductKind.subscription;
      default:
        return ProductKind.subscription;
    }
  }

  /// Real store SKU for a logical ID. Play currently uses the logical ID
  /// verbatim. Samsung SKUs get added to this switch at F1.
  static String skuFor(Store store, String logicalId) {
    switch (store) {
      case Store.play:
        return logicalId; // Play Console SKU == logical ID today
      case Store.samsung:
        return logicalId; // placeholder until Samsung Seller Portal SKUs exist (F1)
    }
  }
}
