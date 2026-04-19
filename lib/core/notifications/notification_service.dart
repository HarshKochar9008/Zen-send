import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../supabase_config.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background handler required for terminated/background pushes.
}

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _available = false;

  static Future<void> initialize() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        settings:
            const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessage.listen((message) async {
        final title = message.notification?.title ?? 'Incoming transfer';
        final body =
            message.notification?.body ?? 'A new transfer is available.';
        await _localNotifications.show(
          id: message.hashCode,
          title: title,
          body: body,
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'incoming_transfers',
              'Incoming Transfers',
              channelDescription: 'Alerts when a new transfer arrives',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(),
          ),
        );
      });
      _available = true;
    } catch (e) {
      _available = false;
      if (kDebugMode) {
        debugPrint('Notifications disabled: $e');
      }
    }
  }

  static Future<void> syncFcmToken(String userId) async {
    if (!_available) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;
      await SupabaseConfig.client
          .from('users')
          .update({'fcm_token': token}).eq('id', userId);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('FCM token sync failed: $e');
      }
    }
  }
}
