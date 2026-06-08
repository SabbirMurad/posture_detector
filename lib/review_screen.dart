import 'dart:io';
import 'package:flutter/material.dart';
import 'package:posture_detector/image_viewer.dart';
import 'package:posture_detector/rosa_score.dart';
import 'package:posture_detector/success_screen.dart';

class ReviewScreen extends StatelessWidget {
  final List<String> photoPaths;
  final List<RosaScore> rosaScores;

  const ReviewScreen({
    super.key,
    required this.photoPaths,
    required this.rosaScores,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
              child: Text(
                'ROSA Assessment',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Scores are calculated from each captured photo.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: photoPaths.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, index) {
                  final score = index < rosaScores.length ? rosaScores[index] : null;
                  return _PhotoScoreCard(
                    path: photoPaths[index],
                    index: index,
                    score: score,
                    allPaths: photoPaths,
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const SuccessScreen()),
                  ),
                  child: const Text('Continue', style: TextStyle(fontSize: 17)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoScoreCard extends StatelessWidget {
  final String path;
  final int index;
  final RosaScore? score;
  final List<String> allPaths;

  const _PhotoScoreCard({
    required this.path,
    required this.index,
    required this.score,
    required this.allPaths,
  });

  static Color _riskColor(int finalScore) {
    if (finalScore <= 2) return const Color(0xFF43A047); // green
    if (finalScore <= 4) return const Color(0xFFFFA000); // amber
    if (finalScore <= 6) return const Color(0xFFEF6C00); // orange
    return const Color(0xFFC62828);                      // red
  }

  static Color _subScoreColor(int s) {
    if (s <= 1) return const Color(0xFF43A047);
    if (s <= 2) return const Color(0xFFFFA000);
    return const Color(0xFFC62828);
  }

  @override
  Widget build(BuildContext context) {
    final finalScore = score?.final_score ?? 0;
    final riskLevel  = score?.risk_level  ?? '—';
    final riskColor  = _riskColor(finalScore);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Photo ──────────────────────────────────────────────────────────
          Stack(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GalleryImageViewer(
                    images: allPaths.map((p) => FileImage(File(p))).toList(),
                    initial_index: index,
                    show_counter: true,
                  ),
                )),
                child: Image.file(
                  File(path),
                  width: double.infinity,
                  height: 240,
                  fit: BoxFit.cover,
                ),
              ),
              // Score badge
              if (finalScore > 0)
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: riskColor.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$finalScore / 10',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              // Photo label
              Positioned(
                top: 10,
                left: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Photo ${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),

          // ── Score breakdown ────────────────────────────────────────────────
          if (score != null) ...[
            // Header
            Container(
              color: riskColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Text(
                    'ROSA Score: $finalScore / 10',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      riskLevel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Sub-scores
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _SectionRow(
                    icon: Icons.chair,
                    label: 'Chair',
                    sectionScore: score!.chair_score,
                    chips: [
                      _Chip('Seat', score!.seat_height_score),
                      _Chip('Back', score!.backrest_score),
                      _Chip('Arms', score!.armrest_score),
                    ],
                    chipColorFn: _subScoreColor,
                  ),
                  const SizedBox(height: 8),
                  _SectionRow(
                    icon: Icons.monitor,
                    label: 'Monitor',
                    sectionScore: score!.monitor_score,
                    chips: [
                      _Chip('Neck', score!.monitor_score),
                    ],
                    chipColorFn: _subScoreColor,
                  ),
                  const SizedBox(height: 8),
                  _SectionRow(
                    icon: Icons.keyboard,
                    label: 'Keyboard / Mouse',
                    sectionScore: score!.peripheral_score,
                    chips: [
                      _Chip('Keys',  score!.keyboard_score),
                      _Chip('Mouse', score!.mouse_score),
                    ],
                    chipColorFn: _subScoreColor,
                  ),
                ],
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Score unavailable', style: TextStyle(color: Colors.grey)),
            ),
        ],
      ),
    );
  }
}

class _Chip {
  final String label;
  final int value;
  const _Chip(this.label, this.value);
}

class _SectionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int sectionScore;
  final List<_Chip> chips;
  final Color Function(int) chipColorFn;

  const _SectionRow({
    required this.icon,
    required this.label,
    required this.sectionScore,
    required this.chips,
    required this.chipColorFn,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800])),
        const Spacer(),
        ...chips.map((c) => Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: chipColorFn(c.value).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: chipColorFn(c.value).withOpacity(0.5)),
                ),
                child: Text(
                  '${c.label} ${c.value}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: chipColorFn(c.value),
                  ),
                ),
              ),
            )),
      ],
    );
  }
}
