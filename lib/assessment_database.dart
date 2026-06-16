import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'package:posture_detector/rosa_score.dart';

/// One saved assessment: a unique [uid], the questionnaire answers, the
/// (averaged) ROSA score, and the filenames of the photos stored for it.
/// The photos live in `<app documents>/assessment_images/<uid>/`.
class AssessmentRecord {
  final int id;
  final String uid;
  final DateTime createdAt;
  final Map<String, dynamic> answers;
  final Map<String, dynamic> score;
  final List<String> images;

  const AssessmentRecord({
    required this.id,
    required this.uid,
    required this.createdAt,
    required this.answers,
    required this.score,
    required this.images,
  });
}

/// Local SQLite store for the history of completed assessments. Each run of the
/// flow appends one row (unique id + questionnaire answers + averaged ROSA score
/// + image filenames) and copies that run's photos into a per-id folder under
/// the app documents directory, so they survive the temp dir being purged or
/// overwritten by later runs. The success screen reads them all back to export.
class AssessmentDatabase {
  AssessmentDatabase._();
  static final AssessmentDatabase instance = AssessmentDatabase._();

  static const _dbName = 'assessment_history.db';
  static const _table = 'assessments';
  static const _imagesRoot = 'assessment_images';

  Database? _db;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    final path = p.join(await getDatabasesPath(), _dbName);
    _db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            uid TEXT NOT NULL,
            created_at TEXT NOT NULL,
            answers_json TEXT NOT NULL,
            score_json TEXT NOT NULL,
            images_json TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE $_table ADD COLUMN uid TEXT NOT NULL DEFAULT ''");
          await db.execute("ALTER TABLE $_table ADD COLUMN images_json TEXT NOT NULL DEFAULT '[]'");
        }
      },
    );
    return _db!;
  }

  /// Appends one completed assessment and persists its photos.
  ///
  /// [answers] is `WorkstationAnswers.toMap()`; [score] is the averaged result;
  /// [photoPaths] are the (temporary) captured-photo paths, which are copied
  /// into this assessment's permanent image folder. Returns the generated [uid].
  Future<String> saveAssessment({
    required Map<String, dynamic> answers,
    required RosaScore score,
    required List<String> photoPaths,
    DateTime? when,
  }) async {
    final db = await _database;
    final uid = _newAssessmentId();
    final storedNames = await _persistImages(uid, photoPaths);
    await db.insert(_table, {
      'uid': uid,
      'created_at': (when ?? DateTime.now()).toIso8601String(),
      'answers_json': jsonEncode(answers),
      'score_json': jsonEncode(score.toMap()),
      'images_json': jsonEncode(storedNames),
    });
    return uid;
  }

  /// All saved assessments, newest first.
  Future<List<AssessmentRecord>> getAll() async {
    final db = await _database;
    final rows = await db.query(_table, orderBy: 'datetime(created_at) DESC, id DESC');
    return rows.map((r) {
      return AssessmentRecord(
        id: r['id'] as int? ?? 0,
        uid: r['uid'] as String? ?? '',
        createdAt: DateTime.tryParse(r['created_at'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        answers: _decodeMap(r['answers_json']),
        score: _decodeMap(r['score_json']),
        images: _decodeList(r['images_json']),
      );
    }).toList();
  }

  /// The on-disk folder holding a given assessment's photos.
  Future<Directory> imagesDirFor(String uid) async {
    final docs = await getApplicationDocumentsDirectory();
    return Directory(p.join(docs.path, _imagesRoot, uid));
  }

  /// Copies each captured photo into `<docs>/assessment_images/<uid>/photo_N.ext`
  /// and returns the stored filenames.
  Future<List<String>> _persistImages(String uid, List<String> photoPaths) async {
    if (photoPaths.isEmpty) return const [];
    final dir = await imagesDirFor(uid);
    await dir.create(recursive: true);

    final names = <String>[];
    for (var i = 0; i < photoPaths.length; i++) {
      final src = File(photoPaths[i]);
      if (!await src.exists()) continue;
      final ext = p.extension(photoPaths[i]);
      final name = 'photo_${i + 1}${ext.isEmpty ? '.jpg' : ext}';
      await src.copy(p.join(dir.path, name));
      names.add(name);
    }
    return names;
  }

  // Unique, sortable, human-traceable id: hex ms-timestamp + random suffix.
  String _newAssessmentId() {
    final rand = Random();
    final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final suffix =
        List.generate(6, (_) => rand.nextInt(16).toRadixString(16)).join();
    return '$ts-$suffix';
  }

  Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  List<String> _decodeList(Object? raw) {
    if (raw is! String || raw.isEmpty) return const [];
    final decoded = jsonDecode(raw);
    return decoded is List ? decoded.map((e) => e.toString()).toList() : const [];
  }
}
