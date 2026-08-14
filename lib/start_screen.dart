import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:posture_detector/assessment_database.dart';
import 'package:posture_detector/body_angles.dart';
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

      // Native emits a grouped contract:
      //   { side_captures: [ {image_path, rosa_score, body_angles} ... ],
      //     front_capture: {image_path, abduction_angle, wrist_deviation_angle} }
      final sideCaptures = (result['side_captures'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      final frontCapture = result['front_capture'] == null
          ? null
          : Map<String, dynamic>.from(result['front_capture'] as Map);

      // Photo strip = the side shots in order, then the front shot last.
      final photoPaths = <String>[
        for (final c in sideCaptures)
          if (c['image_path'] is String) c['image_path'] as String,
        if (frontCapture?['image_path'] is String)
          frontCapture!['image_path'] as String,
      ];
      final rosaScores = sideCaptures
          .map((c) => RosaScore.fromMap(
              Map<String, dynamic>.from((c['rosa_score'] as Map?) ?? const {})))
          .toList();
      final bodyAngles = sideCaptures
          .map((c) => BodyAngles.fromMap(
              Map<String, dynamic>.from((c['body_angles'] as Map?) ?? const {})))
          .toList();
      final frontAbductionAngle = (frontCapture?['abduction_angle'] as num?)?.toDouble();
      final frontWristDeviationAngle =
          (frontCapture?['wrist_deviation_angle'] as num?)?.toDouble();

      // DISABLED: persisting the completed assessment (questionnaire answers +
      // averaged score + photos) to SQLite. Paired with the disabled history
      // export on the success screen — re-enable both together.
      if (rosaScores.isNotEmpty) {
        await AssessmentDatabase.instance.saveAssessment(
          answers: answers.toMap(),
          score: RosaScore.average(rosaScores),
          photoPaths: photoPaths,
        );
      }
      // The native side reuses the same temp filenames each run, so Flutter's
      // image cache (keyed on the file path) would otherwise show the previous
      // capture. Evict them so the new files are decoded fresh from disk.
      for (final path in photoPaths) {
        await FileImage(File(path)).evict();
      }
      if (!mounted) return;

      if (photoPaths.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ReviewScreen(
              photoPaths: photoPaths,
              rosaScores: rosaScores,
              bodyAngles: bodyAngles,
              frontAbductionAngle: frontAbductionAngle,
              frontWristDeviationAngle: frontWristDeviationAngle,
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