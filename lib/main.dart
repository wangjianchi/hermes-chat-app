import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const HermesChatApp());
}

class HermesChatApp extends StatelessWidget {
  const HermesChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hermes 聊天',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C63FF),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F1A),
      ),
      home: const HomeScreen(),
    );
  }
}
