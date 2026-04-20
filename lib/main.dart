import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'app.dart';
import 'core/notifications/fcm_background.dart';
import 'core/notifications/notification_service.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase is optional during local/dev setup without google-services files.
  }
  await initSupabase();
  await ThemeController.load();
  await NotificationService.initialize();
  SupabaseConfig.startAuthListener();

  runApp(const ZenSendApp());
}
