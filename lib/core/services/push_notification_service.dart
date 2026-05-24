import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../features/events/data/events_service.dart';
import 'app_strings_service.dart';
import 'catalog_service.dart';
import 'day_cycle_catalog_service.dart';
import 'live_wallpaper_catalog_service.dart';
import 'ringtone_service.dart';
import 'story_catalog_service.dart';

/// Top-level handler required by FCM for background messages.
/// Must be a top-level function (not a class method) because it runs in
/// an isolated Dart isolate when the app is in background or terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // This handler is invoked when the user receives a notification while
  // the app is NOT in foreground. Firebase auto-renders the system
  // notification — we don't need to do anything else here unless we
  // want to update local state, mark as read, etc.
  // Keep it lightweight — long work here can be killed by Android.
  debugPrint('[PixoraFCM bg] ${message.notification?.title}');
}

/// Singleton service for Firebase Cloud Messaging.
///
/// Subscribes every user to the `new_content` topic so they receive
/// notifications whenever Eduardo publishes new wallpapers from the
/// Firebase Console (no per-user token database needed).
///
/// Usage from main.dart:
///   await PushNotificationService.instance.init();
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    debugPrint('[PixoraFCM] init() called');
    if (_initialized) {
      debugPrint('[PixoraFCM] already initialized, skipping');
      return;
    }
    try {
      debugPrint('[PixoraFCM] calling Firebase.initializeApp()');
      await Firebase.initializeApp();
      debugPrint('[PixoraFCM] Firebase.initializeApp() OK');
      _initialized = true;

      // Background handler must be registered before any other listener
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // Local notifications channel (Android 8+) — needed to display
      // foreground notifications with custom sound / icon.
      const channel = AndroidNotificationChannel(
        'pixora_new_content',
        'Pixora · Nuevo contenido',
        description: 'Avisos cuando hay nuevos wallpapers',
        importance: Importance.high,
      );
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);
      await _local.initialize(initSettings);
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      // Request OS-level permission (Android 13+ requires POST_NOTIFICATIONS)
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      debugPrint(
          '[PixoraFCM] Permission: ${settings.authorizationStatus.name}');

      // Subscribe to broadcast topic — every user gets new_content pushes
      // when Eduardo sends from Firebase Console.
      await FirebaseMessaging.instance.subscribeToTopic('new_content');
      debugPrint('[PixoraFCM] Subscribed to topic: new_content');

      // Subscribe to the Text CMS invalidation topic. wp_admin_server.py
      // sends a data-only push to this topic on every string upsert, so the
      // app can refresh its local cache without waiting for TTL or pull.
      await FirebaseMessaging.instance.subscribeToTopic('text_cms_update');
      debugPrint('[PixoraFCM] Subscribed to topic: text_cms_update');

      // Foreground handler — handles two cases:
      // 1. Data-only push with type='text_cms_invalidate' → refresh CMS cache silently
      // 2. Normal notification → re-display via flutter_local_notifications
      //    (Android does NOT show system notif in foreground by default).
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
        // Case 1: silent Text CMS invalidation push.
        if (msg.data['type'] == 'text_cms_invalidate') {
          debugPrint(
              '[PixoraFCM] text_cms_invalidate received — refreshing AppStringsService');
          AppStringsService.instance.refresh();
          return;
        }
        // Case 2: silent Catalog invalidation push.
        // Payload: {type: 'catalog_invalidate', scope: 'wallpapers'|'live'|
        // 'stories'|'day_cycle'|'ringtones'|'events'|'all'}
        // Dispatched by wp_admin_server.py when Eduardo publishes content
        // (Tier 3, 2026-05-18). Clears the matching service's cache; the
        // next user scroll / pull-to-refresh hits the network → fresh data.
        if (msg.data['type'] == 'catalog_invalidate') {
          final scope = msg.data['scope'] ?? 'all';
          debugPrint('[PixoraFCM] catalog_invalidate scope=$scope');
          _handleCatalogInvalidate(scope.toString());
          return;
        }
        // Case 3: user-visible notification.
        final notification = msg.notification;
        final android = notification?.android;
        if (notification != null && android != null) {
          _local.show(
            notification.hashCode,
            notification.title,
            notification.body,
            NotificationDetails(
              android: AndroidNotificationDetails(
                channel.id,
                channel.name,
                channelDescription: channel.description,
                icon: '@mipmap/ic_launcher',
                importance: Importance.high,
                priority: Priority.high,
              ),
            ),
          );
        }
      });

      // Print the FCM token (handy for testing single-device pushes
      // from Firebase Console)
      final token = await FirebaseMessaging.instance.getToken();
      debugPrint('[PixoraFCM] Token: $token');
    } catch (e, st) {
      debugPrint('[PixoraFCM] Init failed: $e');
      debugPrint('[PixoraFCM] Stack: $st');
    }
  }

  /// Manually re-subscribe to topic (called from settings if user wants
  /// to opt back in after opting out).
  Future<void> subscribeToNewContent() async {
    await FirebaseMessaging.instance.subscribeToTopic('new_content');
  }

  /// Opt out from notifications (called from settings).
  Future<void> unsubscribeFromNewContent() async {
    await FirebaseMessaging.instance.unsubscribeFromTopic('new_content');
  }

  /// Dispatches a `catalog_invalidate` push to the right service(s).
  /// Scope can be a single catalog (`'wallpapers'`, `'live'`, `'stories'`,
  /// `'day_cycle'`, `'ringtones'`, `'events'`) or `'all'`.
  /// Unknown scopes are treated as no-ops with a debug log.
  Future<void> _handleCatalogInvalidate(String scope) async {
    Future<void> wallpapers() => CatalogService.instance.clearCache();
    Future<void> live() => LiveWallpaperCatalogService.instance.clearCache();
    Future<void> stories() => StoryCatalogService.instance.clearCache();
    Future<void> dayCycle() => DayCycleCatalogService.instance.clearCache();
    Future<void> ringtones() => RingtoneService.instance.clearCache();
    Future<void> events() => EventsService.instance.clearCache();

    switch (scope) {
      case 'wallpapers':
        await wallpapers();
        break;
      case 'live':
        await live();
        break;
      case 'stories':
        await stories();
        break;
      case 'day_cycle':
        await dayCycle();
        break;
      case 'ringtones':
        await ringtones();
        break;
      case 'events':
        await events();
        break;
      case 'all':
        await Future.wait([
          wallpapers(),
          live(),
          stories(),
          dayCycle(),
          ringtones(),
          events(),
        ]);
        break;
      default:
        debugPrint('[PixoraFCM] unknown catalog scope: $scope');
    }
  }
}
