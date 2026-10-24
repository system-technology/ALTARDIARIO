import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/bible_models.dart';
import 'bible_download_service.dart';

class ParsedPassage {
  final String reference;
  final int bookId;
  final String bookName;
  final int chapterStart;
  final int? verseStart;
  final int? chapterEnd;
  final int? verseEnd;

  const ParsedPassage({
    required this.reference,
    required this.bookId,
    required this.bookName,
    required this.chapterStart,
    required this.verseStart,
    required this.chapterEnd,
    required this.verseEnd,
  });
}

class BibleService {
  static List<BibleVersion> get availableVersions {
    return [
      const BibleVersion(id: 'rv1960', name: 'Reina-Valera 1960', lang: 'es'),
    ];
  }

  static const String _seedAsset = 'assets/bible/es_rv1960_complete.json';
  static const String _seedAssetFallback = 'assets/bible/es_rv1909_seed.json';
  static const String _databaseName = 'altar_diario_bible.db';
  static const int _databaseVersion = 1;

  Future<List<BibleVersion>> getAllAvailableVersions() async {
    if (kIsWeb) {
      return List.unmodifiable(availableVersions);
    }
    try {
      final downloaded = await BibleDownloadService().getDownloadedVersions();
      final seen = <String>{};
      final versions = <BibleVersion>[...availableVersions];
      for (final v in availableVersions) {
        seen.add(v.id);
      }
      for (final v in downloaded) {
        if (seen.add(v.id)) {
          versions.add(v);
        }
      }
      return versions;
    } catch (_) {
      return List.unmodifiable(availableVersions);
    }
  }

  Future<void> ensureDefaultDownloaded({
    void Function(int current, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      await _loadWebRV1960(onProgress: onProgress);
      return;
    }
    // En nativo, la Biblia completa ya viene embebida en el asset.
    // El seeding ocurre automáticamente en _seedIfNeeded() al abrir la DB.
    // Solo verificamos que esté poblada.
    try {
      final db = await _db;
      final count = Sqflite.firstIntValue(
        await db.rawQuery(
          'SELECT COUNT(*) FROM bible_verses WHERE version = ?',
          ['rv1960'],
        ),
      );
      if (count != null && count > 0) {
        onProgress?.call(1, 1);
        return;
      }
    } catch (_) {
      // Si la DB no se pudo abrir, el seed se hará en el próximo intento
    }
  }

  static const String _bollsBase = 'https://bolls.life';
  static const String _apiSlugRV1960 = 'RV1960';

  Future<void> _loadWebRV1960({
    void Function(int current, int total)? onProgress,
  }) async {
    if (_webLoadedRV1960) return;

    final bookNames = await _fetchWebBookNames();
    if (bookNames.isEmpty) return;

    final response = await http.get(
      Uri.parse('$_bollsBase/static/translations/$_apiSlugRV1960.json'),
    );
    if (response.statusCode != 200) return;

    final verses = jsonDecode(response.body) as List<dynamic>;
    final total = verses.length;

    for (var i = 0; i < total; i++) {
      final v = verses[i] as Map<String, dynamic>;
      final bookId = v['book'] as int;
      final chapter = v['chapter'] as int;
      final verse = v['verse'] as int;
      final text = _stripHtml(v['text'] as String);
      final bookName = bookNames[bookId] ?? 'Book $bookId';
      final key = 'rv1960:$bookId:$chapter:$verse';
      _memoryVerses[key] = [
        {
          'version': 'rv1960',
          'book_id': bookId,
          'book_name': bookName,
          'chapter': chapter,
          'verse': verse,
          'text': text,
        },
      ];
      if (i % 1000 == 0 || i == total - 1) {
        onProgress?.call(i + 1, total);
      }
    }
    _webLoadedRV1960 = true;
  }

  Future<Map<int, String>> _fetchWebBookNames() async {
    final response = await http.get(
      Uri.parse('$_bollsBase/get-books/$_apiSlugRV1960/'),
    );
    if (response.statusCode != 200) return {};
    final books = jsonDecode(response.body) as List<dynamic>;
    return {
      for (final b in books.cast<Map<String, dynamic>>())
        b['bookid'] as int: b['name'] as String,
    };
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static const Map<String, int> _bookMap = {
    'genesis': 1,
    'génesis': 1,
    'exodo': 2,
    'éxodo': 2,
    'levitico': 3,
    'levítico': 3,
    'numeros': 4,
    'números': 4,
    'deuteronomio': 5,
    'josue': 6,
    'josué': 6,
    'jueces': 7,
    'rut': 8,
    '1 samuel': 9,
    '2 samuel': 10,
    '1 reyes': 11,
    '2 reyes': 12,
    '1 cronicas': 13,
    '1 crónicas': 13,
    '2 cronicas': 14,
    '2 crónicas': 14,
    'esdras': 15,
    'nehemias': 16,
    'nehemías': 16,
    'ester': 17,
    'job': 18,
    'salmo': 19,
    'salmos': 19,
    'proverbios': 20,
    'eclesiastes': 21,
    'eclesiastés': 21,
    'cantares': 22,
    'isaias': 23,
    'isaías': 23,
    'jeremias': 24,
    'jeremías': 24,
    'lamentaciones': 25,
    'ezequiel': 26,
    'daniel': 27,
    'oseas': 28,
    'joel': 29,
    'amos': 30,
    'amós': 30,
    'abdias': 31,
    'abdías': 31,
    'jonas': 32,
    'jonás': 32,
    'miqueas': 33,
    'nahum': 34,
    'nahúm': 34,
    'habacuc': 35,
    'sofonias': 36,
    'sofonías': 36,
    'hageo': 37,
    'zacarias': 38,
    'zacarías': 38,
    'malaquias': 39,
    'malaquías': 39,
    'mateo': 40,
    'marcos': 41,
    'lucas': 42,
    'juan': 43,
    'jn': 43,
    'hechos': 44,
    'romanos': 45,
    '1 corintios': 46,
    '2 corintios': 47,
    'galatas': 48,
    'gálatas': 48,
    'efesios': 49,
    'filipenses': 50,
    'colosenses': 51,
    '1 tesalonicenses': 52,
    '2 tesalonicenses': 53,
    '1 timoteo': 54,
    '2 timoteo': 55,
    'tito': 56,
    'filemon': 57,
    'filemón': 57,
    'hebreos': 58,
    'santiago': 59,
    '1 pedro': 60,
    '2 pedro': 61,
    '1 juan': 62,
    '2 juan': 63,
    '3 juan': 64,
    'judas': 65,
    'apocalipsis': 66,
  };

  static final RegExp _passageRegex = RegExp(
    r'^(.+?)\s+(\d+)(?::(\d+))?(?:\s*[-–—]\s*(?:(\d+):)?(\d+))?$',
    caseSensitive: false,
  );

  Database? _database;
  static bool _memoryMode = false;

  // Almacenamiento en memoria para web (estático para persistir entre instancias)
  static final _memoryVerses = <String, List<Map<String, Object?>>>{};
  static final _memoryHighlights = <BibleHighlight>[];
  static final _memoryNotes = <BibleNote>[];
  static bool _webLoadedRV1960 = false;

  Future<List<BiblePassage>> getPassageText(
    String query, {
    String version = 'rv1960',
  }) async {
    await _initialized;
    final passages =
        query.split(';').map((p) => p.trim()).where((p) => p.isNotEmpty);
    final results = <BiblePassage>[];

    for (final passage in passages) {
      final parsed = parsePassage(passage);
      if (parsed == null) {
        results.add(
          BiblePassage(
            reference: passage,
            verses: const [],
            message: 'Formato de pasaje no soportado.',
          ),
        );
        continue;
      }

      var rows = _memoryMode
          ? _queryPassageMemory(parsed, version)
          : await _queryPassage(await _db, parsed, version);

      if (!_memoryMode && rows.isEmpty && version != 'rv1960') {
        rows = await _queryPassage(await _db, parsed, 'rv1960');
      }

      if (_memoryMode && rows.isEmpty) {
        rows = await _fetchWebChapterOnline(parsed, version);
        if (rows.isEmpty && version != 'rv1960') {
          rows = await _fetchWebChapterOnline(parsed, 'rv1960');
        }
      }

      results.add(
        BiblePassage(
          reference: passage,
          verses: rows.map(BibleVerse.fromMap).toList(),
          message: rows.isEmpty ? 'Este pasaje aún no está disponible.' : null,
        ),
      );
    }

    return results.toList();
  }

  Future<List<Map<String, Object?>>> _fetchWebChapterOnline(
    ParsedPassage passage,
    String versionId,
  ) async {
    final apiSlug = versionId.toUpperCase();
    final results = <Map<String, Object?>>[];

    final startCh = passage.chapterStart;
    final endCh = passage.chapterEnd ?? startCh;

    for (var ch = startCh; ch <= endCh; ch++) {
      final url = '$_bollsBase/get-text/$apiSlug/${passage.bookId}/$ch/';
      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode != 200) continue;
        final verses = jsonDecode(response.body) as List<dynamic>;
        for (final v in verses) {
          final item = v as Map<String, dynamic>;
          final verseNum = item['verse'] as int;

          if (ch == startCh &&
              passage.verseStart != null &&
              verseNum < passage.verseStart!) {
            continue;
          }
          if (ch == endCh &&
              passage.verseEnd != null &&
              verseNum > passage.verseEnd!) {
            continue;
          }

          final text = _stripHtml(item['text'] as String);
          final map = <String, Object?>{
            'version': versionId,
            'book_id': passage.bookId,
            'book_name': passage.bookName,
            'chapter': ch,
            'verse': verseNum,
            'text': text,
          };
          final key = '$versionId:${passage.bookId}:$ch:$verseNum';
          _memoryVerses[key] = [map];
          results.add(map);
        }
      } catch (_) {
        continue;
      }
    }
    return results;
  }

  Future<List<BibleHighlight>> getHighlightsForPassages(
    List<BiblePassage> passages, {
    String? userId,
  }) async {
    await _initialized;
    final anchors = _chapterAnchors(passages);
    if (anchors.isEmpty) return const [];

    if (_memoryMode) {
      final highlights = <BibleHighlight>[];
      final anchorKeys = anchors.map((a) => a.key).toSet();
      for (final h in _memoryHighlights) {
        if (anchorKeys.contains(h.anchor)) {
          highlights.add(h);
        }
      }
      return highlights;
    }

    final db = await _db;
    final highlights = <BibleHighlight>[];
    for (final anchor in anchors) {
      final rows = await db.query(
        'bible_highlights',
        where:
            'version = ? AND book_id = ? AND chapter = ? AND (user_id = ? OR user_id IS NULL)',
        whereArgs: [anchor.version, anchor.bookId, anchor.chapter, userId],
        orderBy: 'updated_at DESC',
      );
      highlights.addAll(rows.map(BibleHighlight.fromMap));
    }
    return highlights;
  }

  Future<void> upsertSyncedHighlights(List<BibleHighlight> highlights) async {
    if (highlights.isEmpty) return;
    await _initialized;
    if (_memoryMode) {
      for (final highlight in highlights) {
        _memoryHighlights.removeWhere((h) => h.id == highlight.id);
        _memoryHighlights.add(highlight);
      }
      return;
    }
    final db = await _db;
    final batch = db.batch();
    for (final highlight in highlights) {
      batch.insert(
        'bible_highlights',
        highlight.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<BibleNote>> getNotesForPassages(
    List<BiblePassage> passages, {
    String? userId,
  }) async {
    await _initialized;
    final anchors = _chapterAnchors(passages);
    if (anchors.isEmpty) return const [];

    if (_memoryMode) {
      final notes = <BibleNote>[];
      final anchorKeys = anchors.map((a) => a.key).toSet();
      for (final n in _memoryNotes) {
        if (anchorKeys.contains(n.anchor)) {
          notes.add(n);
        }
      }
      return notes;
    }

    final db = await _db;
    final notes = <BibleNote>[];
    for (final anchor in anchors) {
      final rows = await db.query(
        'bible_notes',
        where:
            'version = ? AND book_id = ? AND chapter = ? AND (user_id = ? OR user_id IS NULL)',
        whereArgs: [anchor.version, anchor.bookId, anchor.chapter, userId],
        orderBy: 'updated_at DESC',
      );
      notes.addAll(rows.map(BibleNote.fromMap));
    }
    return notes;
  }

  Future<void> upsertSyncedNotes(List<BibleNote> notes) async {
    if (notes.isEmpty) return;
    await _initialized;
    if (_memoryMode) {
      for (final note in notes) {
        _memoryNotes.removeWhere((n) => n.id == note.id);
        _memoryNotes.add(note);
      }
      return;
    }
    final db = await _db;
    final batch = db.batch();
    for (final note in notes) {
      batch.insert(
        'bible_notes',
        note.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<BibleHighlight> saveHighlight({
    required BibleVerse verse,
    required String colorHex,
    String? userId,
  }) async {
    await _initialized;
    final now = DateTime.now();
    final highlight = BibleHighlight(
      id: _localId('highlight'),
      userId: userId,
      version: verse.version,
      bookId: verse.bookId,
      chapter: verse.chapter,
      verseStart: verse.verse,
      verseEnd: verse.verse,
      colorHex: colorHex,
      createdAt: now,
      updatedAt: now,
      syncStatus: userId == null ? 'local' : 'pending',
    );
    if (_memoryMode) {
      _memoryHighlights.removeWhere(
        (h) =>
            h.anchor == highlight.anchor &&
            h.verseStart == highlight.verseStart,
      );
      _memoryHighlights.add(highlight);
      return highlight;
    }
    final db = await _db;
    await db.delete(
      'bible_highlights',
      where:
          'version = ? AND book_id = ? AND chapter = ? AND verse_start <= ? AND verse_end >= ? AND (user_id = ? OR user_id IS NULL)',
      whereArgs: [
        verse.version,
        verse.bookId,
        verse.chapter,
        verse.verse,
        verse.verse,
        userId,
      ],
    );
    await db.insert(
      'bible_highlights',
      highlight.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return highlight;
  }

  Future<void> deleteHighlight(String highlightId) async {
    await _initialized;
    if (_memoryMode) {
      _memoryHighlights.removeWhere((h) => h.id == highlightId);
      return;
    }
    final db = await _db;
    await db.delete(
      'bible_highlights',
      where: 'id = ?',
      whereArgs: [highlightId],
    );
  }

  Future<BibleNote> saveNote({
    required BibleVerse verse,
    required String body,
    String? userId,
    BibleNote? existingNote,
  }) async {
    await _initialized;
    final now = DateTime.now();
    final note = BibleNote(
      id: existingNote?.id ?? _localId('note'),
      userId: userId,
      version: verse.version,
      bookId: verse.bookId,
      bookName: verse.bookName,
      chapter: verse.chapter,
      verse: verse.verse,
      body: body.trim(),
      createdAt: existingNote?.createdAt ?? now,
      updatedAt: now,
      syncStatus: userId == null ? 'local' : 'pending',
    );
    if (_memoryMode) {
      _memoryNotes.removeWhere((n) => n.id == note.id);
      _memoryNotes.add(note);
      return note;
    }
    final db = await _db;
    await db.insert(
      'bible_notes',
      note.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return note;
  }

  Future<void> deleteNote(String noteId) async {
    await _initialized;
    if (_memoryMode) {
      _memoryNotes.removeWhere((n) => n.id == noteId);
      return;
    }
    final db = await _db;
    await db.delete('bible_notes', where: 'id = ?', whereArgs: [noteId]);
  }

  Future<void> markHighlightSynced(String highlightId) async {
    await _initialized;
    if (_memoryMode) return;
    final db = await _db;
    await db.update(
      'bible_highlights',
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [highlightId],
    );
  }

  Future<void> markNoteSynced(String noteId) async {
    await _initialized;
    if (_memoryMode) return;
    final db = await _db;
    await db.update(
      'bible_notes',
      {'sync_status': 'synced'},
      where: 'id = ?',
      whereArgs: [noteId],
    );
  }

  Future<List<BibleHighlight>> getPendingHighlights() async {
    await _initialized;
    if (_memoryMode) return const [];
    final db = await _db;
    final rows = await db.query(
      'bible_highlights',
      where: 'sync_status = ? AND user_id IS NOT NULL',
      whereArgs: ['pending'],
    );
    return rows.map(BibleHighlight.fromMap).toList();
  }

  Future<List<BibleNote>> getPendingNotes() async {
    await _initialized;
    if (_memoryMode) return const [];
    final db = await _db;
    final rows = await db.query(
      'bible_notes',
      where: 'sync_status = ? AND user_id IS NOT NULL',
      whereArgs: ['pending'],
    );
    return rows.map(BibleNote.fromMap).toList();
  }

  ParsedPassage? parsePassage(String raw) {
    final match = _passageRegex.firstMatch(raw.trim());
    if (match == null) return null;

    final bookName = match.group(1)!.trim();
    final bookId = _mapBookToId(bookName);
    if (bookId == -1) return null;

    final chapterStart = int.parse(match.group(2)!);
    final verseStart =
        match.group(3) == null ? null : int.parse(match.group(3)!);
    final endChapterOrVerse =
        match.group(4) == null ? null : int.parse(match.group(4)!);
    final endVerse = match.group(5) == null ? null : int.parse(match.group(5)!);

    return ParsedPassage(
      reference: raw.trim(),
      bookId: bookId,
      bookName: getBookNameFromId(bookId),
      chapterStart: chapterStart,
      verseStart: verseStart,
      chapterEnd: verseStart == null ? endVerse : endChapterOrVerse,
      verseEnd: verseStart == null ? null : endVerse,
    );
  }

  List<String> getBookNames() {
    final seen = <int>{};
    final books = _bookMap.entries
        .where((entry) => seen.add(entry.value))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    return books.map((entry) => getBookNameFromId(entry.value)).toList();
  }

  List<BibleChapterAnchor> getChapterAnchors(List<BiblePassage> passages) {
    return _chapterAnchors(passages);
  }

  String getBookNameFromId(int id) {
    const names = {
      1: 'Génesis',
      2: 'Éxodo',
      3: 'Levítico',
      4: 'Números',
      5: 'Deuteronomio',
      6: 'Josué',
      7: 'Jueces',
      8: 'Rut',
      9: '1 Samuel',
      10: '2 Samuel',
      11: '1 Reyes',
      12: '2 Reyes',
      13: '1 Crónicas',
      14: '2 Crónicas',
      15: 'Esdras',
      16: 'Nehemías',
      17: 'Ester',
      18: 'Job',
      19: 'Salmos',
      20: 'Proverbios',
      21: 'Eclesiastés',
      22: 'Cantares',
      23: 'Isaías',
      24: 'Jeremías',
      25: 'Lamentaciones',
      26: 'Ezequiel',
      27: 'Daniel',
      28: 'Oseas',
      29: 'Joel',
      30: 'Amós',
      31: 'Abdías',
      32: 'Jonás',
      33: 'Miqueas',
      34: 'Nahúm',
      35: 'Habacuc',
      36: 'Sofonías',
      37: 'Hageo',
      38: 'Zacarías',
      39: 'Malaquías',
      40: 'Mateo',
      41: 'Marcos',
      42: 'Lucas',
      43: 'Juan',
      44: 'Hechos',
      45: 'Romanos',
      46: '1 Corintios',
      47: '2 Corintios',
      48: 'Gálatas',
      49: 'Efesios',
      50: 'Filipenses',
      51: 'Colosenses',
      52: '1 Tesalonicenses',
      53: '2 Tesalonicenses',
      54: '1 Timoteo',
      55: '2 Timoteo',
      56: 'Tito',
      57: 'Filemón',
      58: 'Hebreos',
      59: 'Santiago',
      60: '1 Pedro',
      61: '2 Pedro',
      62: '1 Juan',
      63: '2 Juan',
      64: '3 Juan',
      65: 'Judas',
      66: 'Apocalipsis',
    };
    return names[id] ?? 'Libro $id';
  }

  Future<bool> get _initialized async {
    if (kIsWeb) {
      if (!_memoryMode) await _initMemoryStore();
      return _memoryMode;
    }
    await _db;
    return true;
  }

  Future<Database> get _db async {
    if (_database != null) return _database!;
    if (kIsWeb) throw UnsupportedError('Use in-memory storage on web');
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, _databaseName),
      version: _databaseVersion,
      onCreate: _createSchema,
      onOpen: _seedIfNeeded,
    );
    return _database!;
  }

  Future<void> _initMemoryStore() async {
    if (_memoryMode) return;
    _memoryMode = true;

    final rawJson = await rootBundle.loadString(_seedAsset);
    final data = jsonDecode(rawJson) as Map<String, dynamic>;
    final version = data['version'] as String;

    for (final book in data['books'] as List<dynamic>) {
      final bookMap = book as Map<String, dynamic>;
      final bookId = bookMap['id'] as int;
      final bookName = bookMap['name'] as String;
      for (final chapter in bookMap['chapters'] as List<dynamic>) {
        final chapterMap = chapter as Map<String, dynamic>;
        final chapterNumber = chapterMap['number'] as int;
        for (final verse in chapterMap['verses'] as List<dynamic>) {
          final verseMap = verse as Map<String, dynamic>;
          final verseNumber = verseMap['number'] as int;
          final verseText = verseMap['text'] as String;
          final key = '$version:$bookId:$chapterNumber:$verseNumber';
          _memoryVerses[key] = [
            {
              'version': version,
              'book_id': bookId,
              'book_name': bookName,
              'chapter': chapterNumber,
              'verse': verseNumber,
              'text': verseText,
            },
          ];
        }
      }
    }
  }

  Future<void> _createSchema(Database db, int version) async {
    await db.execute('''
      CREATE TABLE bible_verses (
        version TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        book_name TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        text TEXT NOT NULL,
        PRIMARY KEY (version, book_id, chapter, verse)
      )
    ''');
    await db.execute('''
      CREATE TABLE bible_highlights (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        version TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        chapter INTEGER NOT NULL,
        verse_start INTEGER NOT NULL,
        verse_end INTEGER NOT NULL,
        color_hex TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE bible_notes (
        id TEXT PRIMARY KEY,
        user_id TEXT,
        version TEXT NOT NULL,
        book_id INTEGER NOT NULL,
        book_name TEXT NOT NULL,
        chapter INTEGER NOT NULL,
        verse INTEGER NOT NULL,
        body TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        sync_status TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_bible_highlights_anchor ON bible_highlights(version, book_id, chapter)',
    );
    await db.execute(
      'CREATE INDEX idx_bible_notes_anchor ON bible_notes(version, book_id, chapter, verse)',
    );
  }

  Future<void> _seedIfNeeded(Database db) async {
    final count = Sqflite.firstIntValue(
      await db.rawQuery('SELECT COUNT(*) FROM bible_verses'),
    );
    if ((count ?? 0) > 0) return;

    String rawJson;
    try {
      rawJson = await rootBundle.loadString(_seedAsset);
    } catch (_) {
      rawJson = await rootBundle.loadString(_seedAssetFallback);
    }
    final data = jsonDecode(rawJson) as Map<String, dynamic>;
    final version = data['version'] as String;
    var batch = db.batch();
    var inserted = 0;

    for (final book in data['books'] as List<dynamic>) {
      final bookMap = book as Map<String, dynamic>;
      final bookId = bookMap['id'] as int;
      final bookName = bookMap['name'] as String;
      for (final chapter in bookMap['chapters'] as List<dynamic>) {
        final chapterMap = chapter as Map<String, dynamic>;
        final chapterNumber = chapterMap['number'] as int;
        for (final verse in chapterMap['verses'] as List<dynamic>) {
          final verseMap = verse as Map<String, dynamic>;
          batch.insert(
            'bible_verses',
            BibleVerse(
              version: version,
              bookId: bookId,
              bookName: bookName,
              chapter: chapterNumber,
              verse: verseMap['number'] as int,
              text: verseMap['text'] as String,
            ).toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );

          inserted++;
          if (inserted % 1000 == 0) {
            await batch.commit(noResult: true);
            batch = db.batch();
          }
        }
      }
    }

    if (inserted % 1000 != 0) {
      await batch.commit(noResult: true);
    }
  }

  Future<List<Map<String, Object?>>> _queryPassage(
    Database db,
    ParsedPassage passage,
    String version,
  ) {
    if (passage.verseStart == null) {
      return db.query(
        'bible_verses',
        where: 'version = ? AND book_id = ? AND chapter BETWEEN ? AND ?',
        whereArgs: [
          version,
          passage.bookId,
          passage.chapterStart,
          passage.chapterEnd ?? passage.chapterStart,
        ],
        orderBy: 'chapter ASC, verse ASC',
      );
    }

    if (passage.chapterEnd != null && passage.verseEnd != null) {
      return db.query(
        'bible_verses',
        where: '''
          version = ? AND book_id = ? AND (
            (chapter = ? AND verse >= ?) OR
            (chapter > ? AND chapter < ?) OR
            (chapter = ? AND verse <= ?)
          )
        ''',
        whereArgs: [
          version,
          passage.bookId,
          passage.chapterStart,
          passage.verseStart,
          passage.chapterStart,
          passage.chapterEnd,
          passage.chapterEnd,
          passage.verseEnd,
        ],
        orderBy: 'chapter ASC, verse ASC',
      );
    }

    return db.query(
      'bible_verses',
      where:
          'version = ? AND book_id = ? AND chapter = ? AND verse BETWEEN ? AND ?',
      whereArgs: [
        version,
        passage.bookId,
        passage.chapterStart,
        passage.verseStart,
        passage.verseEnd ?? passage.verseStart,
      ],
      orderBy: 'verse ASC',
    );
  }

  List<Map<String, Object?>> _queryPassageMemory(
    ParsedPassage passage,
    String version,
  ) {
    final results = <Map<String, Object?>>[];

    if (passage.verseStart == null) {
      final start = passage.chapterStart;
      final end = passage.chapterEnd ?? start;
      for (var ch = start; ch <= end; ch++) {
        final prefix = '$version:${passage.bookId}:$ch:';
        _memoryVerses.forEach((key, verses) {
          if (key.startsWith(prefix)) {
            results.addAll(verses);
          }
        });
      }
    } else if (passage.chapterEnd != null && passage.verseEnd != null) {
      final chEnd = passage.chapterEnd!;
      for (var ch = passage.chapterStart; ch <= chEnd; ch++) {
        final prefix = '$version:${passage.bookId}:$ch:';
        _memoryVerses.forEach((key, verses) {
          if (key.startsWith(prefix)) {
            for (final v in verses) {
              final vn = v['verse'] as int;
              if (ch == passage.chapterStart && vn < passage.verseStart!) {
                continue;
              }
              if (ch == passage.chapterEnd && vn > passage.verseEnd!) {
                continue;
              }
              results.add(v);
            }
          }
        });
      }
    } else {
      final prefix = '$version:${passage.bookId}:${passage.chapterStart}:';
      _memoryVerses.forEach((key, verses) {
        if (key.startsWith(prefix)) {
          for (final v in verses) {
            final vn = v['verse'] as int;
            if (vn >= passage.verseStart! &&
                (passage.verseEnd == null || vn <= passage.verseEnd!)) {
              results.add(v);
            }
          }
        }
      });
    }

    results.sort((a, b) {
      final chA = a['chapter'] as int;
      final chB = b['chapter'] as int;
      if (chA != chB) return chA.compareTo(chB);
      return (a['verse'] as int).compareTo(b['verse'] as int);
    });

    return results;
  }

  int getBookIdFromName(String name) => _mapBookToId(name);

  int getMaxChapter(int bookId) {
    if (_memoryMode) {
      int max = 0;
      for (final key in _memoryVerses.keys) {
        final parts = key.split(':');
        if (parts.length >= 3 && parts[0] == 'rv1960') {
          final bId = int.tryParse(parts[1]) ?? 0;
          if (bId == bookId) {
            final ch = int.tryParse(parts[2]) ?? 0;
            if (ch > max) max = ch;
          }
        }
      }
      return max;
    }
    return 150;
  }

  int _mapBookToId(String name) {
    final normalized = name.toLowerCase().trim().replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
    return _bookMap[normalized] ?? -1;
  }

  List<BibleChapterAnchor> _chapterAnchors(List<BiblePassage> passages) {
    final seen = <String>{};
    final anchors = <BibleChapterAnchor>[];
    for (final passage in passages) {
      for (final verse in passage.verses) {
        final key = '${verse.version}:${verse.bookId}:${verse.chapter}';
        if (seen.add(key)) {
          anchors.add(
            BibleChapterAnchor(
              version: verse.version,
              bookId: verse.bookId,
              chapter: verse.chapter,
            ),
          );
        }
      }
    }
    return anchors;
  }

  String _localId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }
}
