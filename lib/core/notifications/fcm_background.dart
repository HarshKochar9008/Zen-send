import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Runs in a separate isolate when a message arrives while the app is backgrounded or terminated.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}

  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    ),
  );

  const channel = AndroidNotificationChannel(
    'incoming_transfers',
    'Incoming Transfers',
    description: 'Alerts when a new transfer arrives',
    importance: Importance.max,
  );

  final androidPlugin = plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(channel);

  // Android already shows system notifications for FCM "notification" payloads.
  // Data-only messages need an explicit local notification here.
  final sysTitle = message.notification?.title;
  final isAndroid = !kIsWeb && Platform.isAndroid;
  if (isAndroid && sysTitle != null && sysTitle.isNotEmpty) {
    return;
  }

  final title = sysTitle ??
      (message.data['title'] as String?)?.trim() ??
      'Incoming transfer';
  final body = message.notification?.body ??
      (message.data['body'] as String?)?.trim() ??
      'Tap to view and download your files.';

  final rawId = message.messageId ?? message.sentTime?.toIso8601String() ?? '';
  final id = rawId.isEmpty ? message.hashCode : rawId.hashCode;
  final notificationId = id.abs() % 2000000000;

  await plugin.show(
    id: notificationId,
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
}
