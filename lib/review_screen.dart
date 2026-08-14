import 'dart:io';
import 'package:flutter/material.dart';
import 'package:posture_detector/body_angles.dart';
import 'package:posture_detector/image_viewer.dart';
import 'package:posture_detector/rosa_score.dart';
import 'package:posture_detector/success_screen.dart';

class ReviewScreen extends StatelessWidget {
  final List<String> photoPaths;
  final List<RosaScore> rosaScores;
  final List<BodyAngles> bodyAngles;

  /// Front-view derived angles (degrees). Null when no front shot was captured.
  final double? frontAbductionAngle;
  final double? frontWristDeviationAngle;

  const ReviewScreen({
    super.key,
    required this.photoPaths,
    required this.rosaScores,
    this.bodyAngles = const [],
    this.frontAbductionAngle,
    this.frontWristDeviationAngle,
  });

  @override
  Widget build(BuildContext context) {
    final average = RosaScore.average(rosaScores);
    // Photos beyond the scored side shots are the unscored front-view photo(s).
    final scoredCount = rosaScores.length;

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
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: Text(
                'Averaged across all captured photos.',
                style: TextStyle(color: Colors.grey[600], fontSize: 13),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _PhotoStrip(paths: photoPaths, scoredCount: scoredCount),
                  const SizedBox(height: 16),
                  _AverageScoreCard(score: average, photoCount: scoredCount),
                  if (bodyAngles.any((a) => a.hasData) ||
                      frontAbductionAngle != null ||
                      frontWristDeviationAngle != null) ...[
                    const SizedBox(height: 16),
                    _BodyAnglesCard(
                      angles: bodyAngles,
                      frontAbductionAngle: frontAbductionAngle,
                      frontWristDeviationAngle: frontWristDeviationAngle,
                    ),
                  ],
                ],
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

/// Horizontal strip showing every captured photo. Tapping any thumbnail opens
/// the full-screen gallery at that image.
class _PhotoStrip extends StatelessWidget {
  final List<String> paths;

  /// How many leading photos are scored side views; the rest are front views.
  final int scoredCount;

  const _PhotoStrip({required this.paths, required this.scoredCount});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: paths.asMap().entries.map((entry) {
        final index = entry.key;
        
        return GestureDetector(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => GalleryImageViewer(
                images: paths.map((p) => FileImage(File(p))).toList(),
                initial_index: index,
                show_counter: true,
              ),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              children: [
                Image.file(
                  File(paths[index]),
                  width: 150,
                  height: 220,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      index < scoredCount ? 'Photo ${index + 1}' : 'Front view',
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Single card showing the averaged ROSA score and its breakdown.
class _AverageScoreCard extends StatelessWidget {
  final RosaScore score;
  final int photoCount;

  const _AverageScoreCard({required this.score, required this.photoCount});

  @override
  Widget build(BuildContext context) {
    final finalScore = score.final_score <= 10 ? score.final_score : 0;
    final riskLevel = score.risk_level;
    final riskColor = _riskColor(finalScore);
    final valid = finalScore > 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          Container(
            color: valid ? riskColor : Colors.grey,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  valid
                      ? 'Average ROSA Score: $finalScore / 10'
                      : 'Average ROSA Score: —',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                if (valid)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 3,
                    ),
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

          if (valid) ...[
            // ── Sub-scores ─────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _SectionRow(
                    icon: Icons.chair,
                    label: 'Chair',
                    sectionScore: score.chair_score,
                    chips: [
                      _Chip('Seat', score.seat_height_score),
                      _Chip('Back', score.backrest_score),
                      _Chip('Arms', score.armrest_score),
                    ],
                    chipColorFn: _subScoreColor,
                    sectionColorFn: _riskColor,
                  ),
                  const SizedBox(height: 8),
                  _SectionRow(
                    icon: Icons.monitor,
                    label: 'Monitor',
                    sectionScore: score.monitor_area_score,
                    chips: [_Chip('Neck', score.monitor_score)],
                    chipColorFn: _subScoreColor,
                    sectionColorFn: _riskColor,
                  ),
                  const SizedBox(height: 8),
                  _SectionRow(
                    icon: Icons.keyboard,
                    label: 'Keyboard / Mouse',
                    sectionScore: score.mouse_keyboard_area_score,
                    chips: [
                      _Chip('Keys', score.keyboard_score),
                      _Chip('Mouse', score.mouse_score),
                    ],
                    chipColorFn: _subScoreColor,
                    sectionColorFn: _riskColor,
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Divider(height: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 15,
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Averaged from $photoCount captured photos',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Score unavailable',
                style: TextStyle(color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}

/// Card listing the raw body angles the camera measured for each side shot.
class _BodyAnglesCard extends StatelessWidget {
  final List<BodyAngles> angles;
  final double? frontAbductionAngle;
  final double? frontWristDeviationAngle;
  const _BodyAnglesCard({
    required this.angles,
    this.frontAbductionAngle,
    this.frontWristDeviationAngle,
  });

  @override
  Widget build(BuildContext context) {
    final measured = <MapEntry<int, BodyAngles>>[];
    for (var i = 0; i < angles.length; i++) {
      if (angles[i].hasData) measured.add(MapEntry(i, angles[i]));
    }
    final hasFront =
        frontAbductionAngle != null || frontWristDeviationAngle != null;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: const Color(0xFF37474F),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: const Text(
              'Measured Body Angles',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Column(
              children: [
                for (var j = 0; j < measured.length; j++) ...[
                  if (j > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                  _PhotoAngles(
                    photoIndex: measured[j].key,
                    angles: measured[j].value,
                  ),
                ],
                if (hasFront) ...[
                  if (measured.isNotEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(height: 1),
                    ),
                  _FrontAngles(
                    abductionAngle: frontAbductionAngle,
                    wristDeviationAngle: frontWristDeviationAngle,
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: Colors.grey[500]),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Angles read from the side-view captures used for scoring.',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Front-view derived angles: elbow abduction and wrist deviation.
class _FrontAngles extends StatelessWidget {
  final double? abductionAngle;
  final double? wristDeviationAngle;
  const _FrontAngles({this.abductionAngle, this.wristDeviationAngle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Front view',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey[850],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AngleChip(
              label: 'Elbow abduction',
              value: abductionAngle ?? double.nan,
            ),
            _AngleChip(
              label: 'Wrist deviation',
              value: wristDeviationAngle ?? double.nan,
            ),
          ],
        ),
      ],
    );
  }
}

/// One side shot's angle readout: a header line plus the four ROSA angles.
class _PhotoAngles extends StatelessWidget {
  final int photoIndex;
  final BodyAngles angles;
  const _PhotoAngles({required this.photoIndex, required this.angles});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Photo ${photoIndex + 1}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Colors.grey[850],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blueGrey.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${angles.side} side',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.blueGrey[700],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _AngleChip(label: 'Knee', value: angles.kneeAngle),
            _AngleChip(label: 'Trunk', value: angles.trunkAngle),
            _AngleChip(label: 'Elbow', value: angles.elbowAngle),
            _AngleChip(label: 'Neck', value: angles.neckAngle),
          ],
        ),
        if (angles.neckState.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Neck posture: ${angles.neckStateLabel}',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
      ],
    );
  }
}

class _AngleChip extends StatelessWidget {
  final String label;
  final double value;
  const _AngleChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = value.isNaN ? '—' : '${value.round()}°';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.grey.withOpacity(0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withOpacity(0.30)),
      ),
      child: RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: text,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[900],
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color _riskColor(int finalScore) {
  if (finalScore <= 2) return const Color(0xFF43A047); // green
  if (finalScore <= 4) return const Color(0xFFFFA000); // amber
  if (finalScore <= 6) return const Color(0xFFEF6C00); // orange
  return const Color(0xFFC62828); // red
}

Color _subScoreColor(int s) {
  if (s <= 1) return const Color(0xFF43A047);
  if (s <= 2) return const Color(0xFFFFA000);
  return const Color(0xFFC62828);
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
  final Color Function(int) sectionColorFn;

  const _SectionRow({
    required this.icon,
    required this.label,
    required this.sectionScore,
    required this.chips,
    required this.chipColorFn,
    required this.sectionColorFn,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: sectionColorFn(sectionScore).withOpacity(0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sectionColorFn(sectionScore).withOpacity(0.5),
            ),
          ),
          child: Text(
            '$sectionScore',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: sectionColorFn(sectionScore),
            ),
          ),
        ),
        const Spacer(),
        ...chips.map(
          (c) => Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: chipColorFn(c.value).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: chipColorFn(c.value).withOpacity(0.5),
                ),
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
          ),
        ),
      ],
    );
  }
}
