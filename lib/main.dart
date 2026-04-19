import 'package:flutter/material.dart';
import 'core/supabase_config.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initSupabase();
  SupabaseConfig.startAuthListener();

  runApp(const ZenSendApp());
}
