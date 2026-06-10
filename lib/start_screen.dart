import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posture_detector/review_screen.dart';
import 'package:posture_detector/rosa_score.dart';
import 'package:posture_detector/workstation_answers.dart';
import 'package:posture_detector/workstation_questionnaire.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  static const _channel = MethodChannel('posture_detection');
  bool _loading = false;

  Future<void> _onStart() async {
    final answers = await Navigator.of(context).push<WorkstationAnswers>(
      MaterialPageRoute(builder: (_) => const WorkstationQuestionnaire()),
    );
    if (answers == null || !mounted) return;

    setState(() => _loading = true);
    try {
      final result = await _channel.invokeMethod<Map>('startDetection', answers.toMap());
      if (!mounted) return;
      if (result == null) return;
      final photoPaths = List<String>.from(result['photo_paths'] as List? ?? []);
      final rosaScores = (result['rosa_scores'] as List? ?? [])
          .map((e) => RosaScore.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();

      if (photoPaths.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              photoPaths: photoPaths,
              rosaScores: rosaScores,
            ),
          ),
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