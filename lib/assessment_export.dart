import 'dart:io';
import 'dart:ui' show Rect;

import 'package:archive/archive_io.dart';
import 'package:excel/excel.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:posture_detector/assessment_database.dart';

/// A single Excel column: which JSON key it reads and the header to print.
class _Col {
  final String key;
  final String label;
  const _Col(this.key, this.label);
}

// Averaged ROSA score fields (keys match RosaScore.toMap()).
const _scoreColumns = <_Col>[
  _Col('final_score', 'ROSA Final Score'),
  _Col('risk_level', 'Risk Level'),
  _Col('chair_score', 'Chair Score'),
  _Col('peripheral_score', 'Peripheral Score'),
  _Col('monitor_area_score', 'Monitor Area Score'),
  _Col('mouse_keyboard_area_score', 'Mouse/Keyboard Area Score'),
  _Col('seat_height_score', 'Seat Height Score'),
  _Col('backrest_score', 'Backrest Score'),
  _Col('armrest_score', 'Armrest Score'),
  _Col('monitor_score', 'Monitor (Neck) Score'),
  _Col('keyboard_score', 'Keyboard Score'),
  _Col('mouse_score', 'Mouse Score'),
];

// Questionnaire answers (keys match WorkstationAnswers.toMap()).
const _answerColumns = <_Col>[
  _Col('chair_height_non_adjustable', 'Chair height non-adjustable'),
  _Col('insufficient_under_desk_space', 'Insufficient under-desk space'),
  _Col('seat_depth_score', 'Seat depth score (1 ok / 2 poor)'),
  _Col('seat_pan_non_adjustable', 'Seat pan non-adjustable'),
  _Col('armrest_non_adjustable', 'Armrest non-adjustable'),
  _Col('armrest_hard_damaged', 'Armrest hard/damaged'),
  _Col('armrest_too_wide', 'Armrest too wide'),
  _Col('backrest_non_adjustable', 'Backrest non-adjustable'),
  _Col('work_surface_too_high', 'Work surface too high'),
  _Col('monitor_non_adjustable', 'Monitor non-adjustable'),
  _Col('neck_twist_over_30', 'Neck twist > 30°'),
  _Col('monitor_too_far', 'Monitor too far'),
  _Col('screen_glare', 'Screen glare'),
  _Col('no_document_holder', 'No document holder'),
  _Col('phone_score', 'Phone usage score (0-2)'),
  _Col('phone_cradle_neck_shoulder', 'Phone cradled neck/shoulder'),
  _Col('no_hands_free_option', 'No hands-free option'),
  _Col('mouse_keyboard_different_surfaces', 'Mouse/keyboard different surfaces'),
  _Col('mouse_pinch_grip', 'Mouse pinch grip'),
  _Col('mouse_palmrest', 'Mouse palm rest'),
  _Col('mouse_non_adjustable', 'Mouse non-adjustable'),
  _Col('keyboard_deviation', 'Keyboard wrist deviation'),
  _Col('keyboard_too_high', 'Keyboard too high'),
  _Col('reaching_overhead', 'Reaching overhead'),
  _Col('keyboard_platform_non_adjustable', 'Keyboard platform non-adjustable'),
  _Col('duration_modifier', 'Duration modifier (-1/0/+1)'),
];

const _imagesFolder = 'images';

/// Builds the styled history `.xlsx` bytes. Each row starts with the
/// assessment's unique id, which is also the name of its photo folder inside
/// the zip (`images/<id>/`), so rows and image folders cross-reference.
///
/// Styling: grouped colored headers (meta / scores / answers), zebra-striped
/// rows, a severity heat-map on the ROSA score columns, and "Yes" problem
/// answers highlighted in red.
List<int> _buildHistoryXlsxBytes(List<AssessmentRecord> records) {
  final excel = Excel.createExcel();
  const sheetName = 'History';
  final defaultSheet = excel.getDefaultSheet();
  if (defaultSheet != null && defaultSheet != sheetName) {
    excel.rename(defaultSheet, sheetName);
  }
  final sheet = excel[sheetName];

  const scoreStart = 3; // after ID / Date / Time
  final scoreEnd = scoreStart + _scoreColumns.length - 1;
  final answerStart = scoreEnd + 1;
  final headers = <String>[
    'Assessment ID',
    'Date',
    'Time',
    ..._scoreColumns.map((c) => c.label),
    ..._answerColumns.map((c) => c.label),
  ];

  // ── Header row ───────────────────────────────────────────────────────────
  for (var col = 0; col < headers.length; col++) {
    final ExcelColor bg = col < scoreStart
        ? ExcelColor.blueGrey700
        : col <= scoreEnd
            ? ExcelColor.indigo600
            : ExcelColor.teal700;
    _put(sheet, col, 0, TextCellValue(headers[col]), _headerStyle(bg));
  }

  // Column widths (long labels wrap in the header).
  sheet.setColumnWidth(0, 22);
  sheet.setColumnWidth(1, 12);
  sheet.setColumnWidth(2, 8);
  for (var col = scoreStart; col <= scoreEnd; col++) {
    sheet.setColumnWidth(col, 18);
  }
  for (var col = answerStart; col < headers.length; col++) {
    sheet.setColumnWidth(col, 26);
  }

  // ── Data rows ────────────────────────────────────────────────────────────
  for (var i = 0; i < records.length; i++) {
    final rec = records[i];
    final row = i + 1;
    final zebra = i.isEven ? ExcelColor.white : ExcelColor.grey100;
    final finalScore = (rec.score['final_score'] as num?)?.toInt() ?? 11;

    _put(sheet, 0, row, TextCellValue(rec.uid), _dataStyle(bg: zebra));
    _put(sheet, 1, row, TextCellValue(_date(rec.createdAt)),
        _dataStyle(bg: zebra, align: HorizontalAlign.Center));
    _put(sheet, 2, row, TextCellValue(_time(rec.createdAt)),
        _dataStyle(bg: zebra, align: HorizontalAlign.Center));

    for (var s = 0; s < _scoreColumns.length; s++) {
      final key = _scoreColumns[s].key;
      final col = scoreStart + s;
      final raw = rec.score[key];
      if (key == 'final_score' || key == 'risk_level') {
        _put(sheet, col, row, _cell(raw),
            _dataStyle(
              bg: _severityFill(finalScore),
              font: ExcelColor.white,
              bold: true,
              align: HorizontalAlign.Center,
            ));
      } else {
        final v = (raw as num?)?.toInt();
        _put(sheet, col, row, _cell(raw),
            _dataStyle(
              bg: v == null ? zebra : _subScoreFill(v),
              align: HorizontalAlign.Center,
            ));
      }
    }

    for (var a = 0; a < _answerColumns.length; a++) {
      final key = _answerColumns[a].key;
      final col = answerStart + a;
      final raw = rec.answers[key];
      if (raw is bool) {
        _put(sheet, col, row, TextCellValue(raw ? 'Yes' : 'No'),
            _dataStyle(
              bg: raw ? ExcelColor.red100 : zebra,
              font: raw ? ExcelColor.red900 : ExcelColor.grey700,
              bold: raw,
              align: HorizontalAlign.Center,
            ));
      } else {
        _put(sheet, col, row, _cell(raw),
            _dataStyle(bg: zebra, align: HorizontalAlign.Center));
      }
    }
  }

  return excel.save() ?? <int>[];
}

void _put(Sheet sheet, int col, int row, CellValue value, CellStyle style) {
  sheet.updateCell(
    CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
    value,
    cellStyle: style,
  );
}

Border _thinBorder() =>
    Border(borderStyle: BorderStyle.Thin, borderColorHex: ExcelColor.grey300);

CellStyle _headerStyle(ExcelColor bg) => CellStyle(
      bold: true,
      fontColorHex: ExcelColor.white,
      backgroundColorHex: bg,
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
      textWrapping: TextWrapping.WrapText,
      leftBorder: _thinBorder(),
      rightBorder: _thinBorder(),
      topBorder: _thinBorder(),
      bottomBorder: _thinBorder(),
    );

CellStyle _dataStyle({
  ExcelColor? bg,
  ExcelColor? font,
  bool bold = false,
  HorizontalAlign align = HorizontalAlign.Left,
}) =>
    CellStyle(
      bold: bold,
      fontColorHex: font ?? ExcelColor.black,
      backgroundColorHex: bg ?? ExcelColor.none,
      horizontalAlign: align,
      verticalAlign: VerticalAlign.Center,
      leftBorder: _thinBorder(),
      rightBorder: _thinBorder(),
      topBorder: _thinBorder(),
      bottomBorder: _thinBorder(),
    );

// Final-score / risk-level fill (matches the app's risk thresholds).
ExcelColor _severityFill(int finalScore) {
  if (finalScore > 10) return ExcelColor.grey400; // invalid
  if (finalScore <= 2) return ExcelColor.green600;
  if (finalScore <= 4) return ExcelColor.amber700;
  if (finalScore <= 6) return ExcelColor.orange800;
  return ExcelColor.red800;
}

// Light heat-map tint for the individual sub-scores.
ExcelColor _subScoreFill(int s) {
  if (s > 10) return ExcelColor.grey200; // invalid
  if (s <= 1) return ExcelColor.green100;
  if (s <= 2) return ExcelColor.amber100;
  return ExcelColor.red100;
}

/// Builds a `.zip` containing `history.xlsx` plus an `images/<id>/` folder per
/// assessment, and writes it to a temp file.
Future<XFile> buildHistoryZip(List<AssessmentRecord> records) async {
  final dir = await getTemporaryDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final zipPath = p.join(dir.path, 'posture_assessment_history_$stamp.zip');

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);

  // Spreadsheet at the zip root.
  final xlsxPath = p.join(dir.path, 'history_$stamp.xlsx');
  final xlsxFile = File(xlsxPath);
  await xlsxFile.writeAsBytes(_buildHistoryXlsxBytes(records));
  encoder.addFile(xlsxFile, 'history.xlsx');

  // images/<id>/photo_N.jpg per assessment.
  for (final rec in records) {
    if (rec.images.isEmpty) continue;
    final imgDir = await AssessmentDatabase.instance.imagesDirFor(rec.uid);
    for (final name in rec.images) {
      final f = File(p.join(imgDir.path, name));
      if (await f.exists()) {
        encoder.addFile(f, '$_imagesFolder/${rec.uid}/$name');
      }
    }
  }

  encoder.close();
  await xlsxFile.delete().catchError((_) => xlsxFile);

  return XFile(
    zipPath,
    mimeType: 'application/zip',
    name: 'posture_assessment_history.zip',
  );
}

/// Builds the zip and opens the OS share/save sheet so the user can save it to
/// Files, email it, etc. [sharePositionOrigin] anchors the popover on iPad.
Future<void> shareHistoryZip(
  List<AssessmentRecord> records, {
  Rect? sharePositionOrigin,
}) async {
  final file = await buildHistoryZip(records);
  await SharePlus.instance.share(ShareParams(
    files: [file],
    subject: 'Posture Assessment History',
    text: 'Posture assessment history (${records.length} assessments)',
    sharePositionOrigin: sharePositionOrigin,
  ));
}

CellValue _cell(Object? value) {
  if (value == null) return TextCellValue('');
  if (value is bool) return TextCellValue(value ? 'Yes' : 'No');
  if (value is int) return IntCellValue(value);
  if (value is double) return DoubleCellValue(value);
  return TextCellValue(value.toString());
}

String _date(DateTime d) => '${d.year}-${_2(d.month)}-${_2(d.day)}';
String _time(DateTime d) => '${_2(d.hour)}:${_2(d.minute)}';
String _2(int n) => n.toString().padLeft(2, '0');
