/// Body angles measured by the native pose module for a single side-view shot.
/// These are the raw ROSA geometry readings (knee, trunk, elbow, neck), surfaced
/// on the review screen so the user can see what the camera actually measured.
class BodyAngles {
  /// "Left" / "Right" — which side's landmarks were used. Empty when this entry
  /// carries no measurement (e.g. a shot where pose landmarks were unavailable).
  final String side;
  final double kneeAngle; // degrees
  final double trunkAngle; // degrees from vertical
  final double elbowAngle; // degrees (shoulder→elbow→wrist)
  final double neckAngle; // degrees from vertical
  final String neckState; // raw enum name, e.g. FORWARD_HEAD
  final String lowerBodyConfidence; // HIGH / LOW

  const BodyAngles({
    required this.side,
    required this.kneeAngle,
    required this.trunkAngle,
    required this.elbowAngle,
    required this.neckAngle,
    required this.neckState,
    required this.lowerBodyConfidence,
  });

  /// True when this entry actually holds a measurement. Null/empty native
  /// entries deserialize with a blank [side] and NaN angles.
  bool get hasData => side.isNotEmpty && !kneeAngle.isNaN;

  static double _d(Object? v) =>
      v is num ? v.toDouble() : double.nan;

  factory BodyAngles.fromMap(Map<String, dynamic> m) => BodyAngles(
        side: m['side'] as String? ?? '',
        kneeAngle: _d(m['knee_angle']),
        trunkAngle: _d(m['trunk_angle']),
        elbowAngle: _d(m['elbow_angle']),
        neckAngle: _d(m['neck_angle']),
        neckState: m['neck_state'] as String? ?? '',
        lowerBodyConfidence: m['lower_body_confidence'] as String? ?? '',
      );

  /// Human-readable neck posture, mapping the native enum names to labels.
  String get neckStateLabel {
    switch (neckState) {
      case 'NEUTRAL':
        return 'Neutral';
      case 'FORWARD_HEAD':
        return 'Forward head';
      case 'MILD_FLEXION':
        return 'Mild flexion';
      case 'SEVERE_FLEXION':
        return 'Severe flexion';
      case 'HEAD_BACK':
        return 'Head back';
      default:
        return neckState;
    }
  }
}
