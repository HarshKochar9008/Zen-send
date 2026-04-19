import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/notifications/notification_service.dart';
import 'core/supabase_config.dart';
import 'core/theme.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
