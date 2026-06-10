class RosaScore {
  final int final_score;
  final String risk_level;
  final int chair_score;
  final int peripheral_score;
  final int monitor_area_score;
  final int mouse_keyboard_area_score;
  final int seat_height_score;
  final int backrest_score;
  final int armrest_score;
  final int monitor_score;
  final int keyboard_score;
  final int mouse_score;

  const RosaScore({
    required this.final_score,
    required this.risk_level,
    required this.chair_score,
    required this.peripheral_score,
    required this.monitor_area_score,
    required this.mouse_keyboard_area_score,
    required this.seat_height_score,
    required this.backrest_score,
    required this.armrest_score,
    required this.monitor_score,
    required this.keyboard_score,
    required this.mouse_score,
  });

  // 11 is the default "invalid" score, as the valid range is 0-10.
  factory RosaScore.fromMap(Map<String, dynamic> m) => RosaScore(
    final_score:               m['final_score']               as int? ?? 11,
    risk_level:                m['risk_level']                as String? ?? 'Unknown',
    chair_score:               m['chair_score']               as int? ?? 11,
    peripheral_score:          m['peripheral_score']          as int? ?? 11,
    monitor_area_score:        m['monitor_area_score']        as int? ?? 11,
    mouse_keyboard_area_score: m['mouse_keyboard_area_score'] as int? ?? 11,
    seat_height_score:         m['seat_height_score']         as int? ?? 11,
    backrest_score:            m['backrest_score']            as int? ?? 11,
    armrest_score:             m['armrest_score']             as int? ?? 11,
    monitor_score:             m['monitor_score']             as int? ?? 11,
    keyboard_score:            m['keyboard_score']            as int? ?? 11,
    mouse_score:               m['mouse_score']               as int? ?? 11,
  );

  Map<String, dynamic> toMap() => {
    'final_score':               final_score,
    'risk_level':                risk_level,
    'chair_score':               chair_score,
    'peripheral_score':          peripheral_score,
    'monitor_area_score':        monitor_area_score,
    'mouse_keyboard_area_score': mouse_keyboard_area_score,
    'seat_height_score':         seat_height_score,
    'backrest_score':            backrest_score,
    'armrest_score':             armrest_score,
    'monitor_score':             monitor_score,
    'keyboard_score':            keyboard_score,
    'mouse_score':               mouse_score,
  };
}
