import 'package:flutter/material.dart';
// DISABLED: assessment history export (SQLite read + zip/Excel share).
// import 'package:posture_detector/assessment_database.dart';
// import 'package:posture_detector/assessment_export.dart';
import 'package:posture_detector/start_screen.dart';

class SuccessScreen extends StatefulWidget {
  const SuccessScreen({super.key});

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  // DISABLED: history download. Paired with the disabled SQLite persistence in
  // start_screen.dart — re-enable both together.
  // bool _exporting = false;
  //
  // Future<void> _downloadHistory() async {
  //   setState(() => _exporting = true);
  //   try {
  //     final records = await AssessmentDatabase.instance.getAll();
  //     if (!mounted) return;
  //     if (records.isEmpty) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(content: Text('No assessment history yet.')),
  //       );
  //       return;
  //     }
  //     // Anchor the share popover for iPad.
  //     final box = context.findRenderObject() as RenderBox?;
  //     final origin = box != null
  //         ? box.localToGlobal(Offset.zero) & box.size
  //         : null;
  //     await shareHistoryZip(records, sharePositionOrigin: origin);
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(content: Text('Export failed: $e')),
  //       );
  //     }
  //   } finally {
  //     if (mounted) setState(() => _exporting = false);
  //   }
  // }

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
                // DISABLED: "Download Assessment History" button.
                // SizedBox(
                //   width: double.infinity,
                //   height: 52,
                //   child: FilledButton.icon(
                //     onPressed: _exporting ? null : _downloadHistory,
                //     icon: _exporting
                //         ? const SizedBox(
                //             width: 20,
                //             height: 20,
                //             child: CircularProgressIndicator(
                //               strokeWidth: 2.5,
                //               color: Colors.white,
                //             ),
                //           )
                //         : const Icon(Icons.download),
                //     label: Text(
                //       _exporting ? 'Preparing…' : 'Download Assessment History',
                //       style: const TextStyle(fontSize: 16),
                //     ),
                //   ),
                // ),
                // const SizedBox(height: 12),
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
