import 'package:flutter/material.dart';
import 'screens/home_shell.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MhMotionApp());
}

class MhMotionApp extends StatelessWidget {
  const MhMotionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MH Motion Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: const HomeShell(),
    );
  }
}
