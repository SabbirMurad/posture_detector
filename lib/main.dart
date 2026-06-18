import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posture_detector/start_screen.dart';

// Black status bar background with light (white) icons, app-wide. On Android
// this paints the status bar black; on iOS the bar is transparent so only the
// icon brightness applies.
const _statusBarStyle = SystemUiOverlayStyle(
  statusBarColor: Color(0xFF181818),
  statusBarIconBrightness: Brightness.light, // Android icon color
  statusBarBrightness: Brightness.dark, // iOS icon color (light icons)
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(_statusBarStyle);
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Posture Setup',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.blue,
        useMaterial3: true,
        // Keep the black status bar even on screens with an AppBar (which would
        // otherwise impose its own overlay style).
        appBarTheme: const AppBarTheme(systemOverlayStyle: _statusBarStyle),
      ),
      home: const StartScreen(),
    );
  }
}
