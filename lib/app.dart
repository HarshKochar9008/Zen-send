import 'package:flutter/material.dart';
import 'core/theme.dart';
import 'features/home/home_screen.dart';

class ZenSendApp extends StatelessWidget {
  const ZenSendApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ZenSend Share',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const HomeScreen(),
    );
  }
}
