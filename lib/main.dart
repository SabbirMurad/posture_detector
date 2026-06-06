import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Posture Setup',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: const StartScreen(),
    );
  }
}

// ── Start screen ──────────────────────────────────────────────────────────────

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  static const _channel = MethodChannel('posture_detection');
  bool _loading = false;

  Future<void> _onStart() async {
    setState(() => _loading = true);
    try {
      final success = await _channel.invokeMethod<bool>('startDetection');
      if (!mounted) return;
      if (success == true) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const SuccessScreen()),
        );
      }
    } on PlatformException catch (e) {
      debugPrint('Detection error: ${e.message}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.accessibility_new, size: 72, color: Colors.blue),
                const SizedBox(height: 24),
                Text(
                  'Posture Setup',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'We\'ll check your lighting, camera angle,\nand position before we begin.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: _loading ? null : _onStart,
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Start', style: TextStyle(fontSize: 17)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Success screen ─────────────────────────────────────────────────────────────

class SuccessScreen extends StatelessWidget {
  const SuccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle, size: 88, color: Colors.green),
                const SizedBox(height: 24),
                Text(
                  'All Set!',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your setup looks great.\nYou\'re ready to go.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (_) => const StartScreen()),
                    ),
                    child: const Text('Start Again', style: TextStyle(fontSize: 17)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
