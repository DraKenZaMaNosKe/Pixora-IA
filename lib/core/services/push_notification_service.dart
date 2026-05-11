import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
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

      // Foreground handler — when the user receives a push while looking
      // at the app, Android does NOT show the system notification by
      // default. We re-display it with flutter_local_notifications.
      FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
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
    } catch (e) {
      debugPrint('[PixoraFCM] Init failed: $e');
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
}
