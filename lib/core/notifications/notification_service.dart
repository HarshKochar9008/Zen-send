import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import '../supabase_config.dart';
import 'pending_push.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static bool _available = false;
  static String? _userId;
  static bool _initializing = false;
  static Future<void>? _initializeFuture;

  static void setUserId(String? id) => _userId = id;

  static Future<void> initialize() async {
    if (_available) return;
    if (_initializeFuture != null) return _initializeFuture!;
    _initializing = true;
    _initializeFuture = _initializeInternal();
    await _initializeFuture;
    _initializing = false;
    _initializeFuture = null;
  }

  static Future<void> _initializeInternal() async {
    try {
      if (!kIsWeb && Platform.isAndroid) {
        final status = await Permission.notification.request();
        if (status.isDenied && kDebugMode) {
          debugPrint('Notification permission denied');
        }
      }

      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
        announcement: false,
        carPlay: false,
        criticalAlert: false,
      );

      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: iosInit,
        ),
        onDidReceiveNotificationResponse: (details) {
          PendingIncomingTransfer.applyPayload(details.payload);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            PendingIncomingTransfer.tryNavigateToReceive();
          });
        },
      );

      const channel = AndroidNotificationChannel(
        'incoming_transfers',
        'Incoming Transfers',
        description: 'Alerts when a new transfer arrives',
        importance: Importance.max,
      );
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(channel);

      FirebaseMessaging.onMessage.listen((message) async {
        final title = message.notification?.title ??
            (message.data['title'] as String?) ??
            'Incoming transfer';
        final body = message.notification?.body ??
            (message.data['body'] as String?) ??
            'A new transfer is available.';
        await _localNotifications.show(
          id: message.hashCode.abs() % 2000000000,
          title: title,
          body: body,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.max,
              priority: Priority.high,
              styleInformation: BigTextStyleInformation(body),
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      });

      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        PendingIncomingTransfer.setFromRemoteMessage(message.data);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PendingIncomingTransfer.tryNavigateToReceive();
        });
      });

      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        PendingIncomingTransfer.setFromRemoteMessage(initial.data);
      }

      FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        final uid = _userId;
        if (uid == null || uid.isEmpty) return;
        try {
          await SupabaseConfig.client
              .from('users')
              .update({'fcm_token': token}).eq('id', uid);
        } catch (e) {
          if (kDebugMode) {
            debugPrint('FCM token refresh sync failed: $e');
          }
        }
      });

      final launchDetails =
          await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails!.notificationResponse?.payload;
        PendingIncomingTransfer.applyPayload(payload);
      }

      _available = true;
    } catch (e) {
      _available = false;
      if (kDebugMode) {
        debugPrint('Notifications disabled: $e');
      }
    }
  }

  static Future<void> syncFcmToken(String userId) async {
    // Ensure initialization is started, but do not fail token sync if local
    // notification setup had issues. FCM token can still be available.
    if (!_available && !_initializing) {
      await initialize();
    }
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

  /// After the first frame when [rootNavigatorKey] is attached.
  static void handleLaunchAndPendingNavigation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      PendingIncomingTransfer.tryNavigateToReceive();
    });
  }
}
