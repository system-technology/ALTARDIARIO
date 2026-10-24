import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../models/bible_models.dart';

class AvailableTranslation {
  final String slug;
  final String name;
  final String language;
  final bool isDownloaded;
  final int? sizeBytes;

  const AvailableTranslation({
    required this.slug,
    required this.name,
    required this.language,
    this.isDownloaded = false,
    this.sizeBytes,
  });
}

class BibleDownloadService {
  static const String _baseUrl = 'https://bolls.life';
  static const String _databaseName = 'altar_diario_bible.db';
  static const int _batchSize = 1000;
  static const String _webDownloadedKey = 'web_downloaded_bible_versions';

  // Mapa de ID de versión → slug de API (bolls.life es sensible a mayúsculas)
  // Solo versiones con licencia clara: rv1960 (decisión Owner), rv1909 (dominio público),
  // web (dominio público), kjv (dominio público)
  static const Map<String, String> _apiSlugs = {
    'rv1960': 'RV1960',
    'rv1909': 'RV1909',
    'web': 'WEB',
    'kjv': 'KJV',
  };

  String _apiSlug(String versionId) => _apiSlugs[versionId] ?? versionId;

  Database? _database;

  Future<Database> get _db async {
    if (_database != null) return _database!;
    if (kIsWeb) throw UnsupportedError('Downloads not supported on web');
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, _databaseName),
      readOnly: false,
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<Set<String>> _getWebDownloadedSlugs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_webDownloadedKey) ??
          ['rv1960', 'rv1909', 'web', 'kjv'];
      return list.toSet();
    } catch (_) {
      return {'rv1960', 'rv1909', 'web', 'kjv'};
    }
  }

  Future<void> _addWebDownloadedSlug(String slug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = (prefs.getStringList(_webDownloadedKey) ??
              ['rv1960', 'rv1909', 'web', 'kjv'])
          .toSet();
      current.add(slug);
      current.add(slug.toLowerCase());
      await prefs.setStringList(_webDownloadedKey, current.toList());
    } catch (_) {}
  }

  Future<void> _removeWebDownloadedSlug(String slug) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = (prefs.getStringList(_webDownloadedKey) ??
              ['rv1960', 'rv1909', 'web', 'kjv'])
          .toSet();
      current.remove(slug);
      current.remove(slug.toLowerCase());
      await prefs.setStringList(_webDownloadedKey, current.toList());
    } catch (_) {}
  }

  // Conjunto de slugs permitidos (coincide con _apiSlugs y LICENCIAS.md)
  static const Set<String> _allowedSlugs = {'rv1960', 'rv1909', 'web', 'kjv'};

  Future<List<AvailableTranslation>> fetchAvailableTranslations() async {
    final response = await http.get(
      Uri.parse('$_baseUrl/static/bolls/app/views/languages.json'),
    );
    if (response.statusCode != 200) {
      throw Exception('Error al obtener traducciones: ${response.statusCode}');
    }

    final downloadedIds = await getDownloadedVersionIds();
    final downloadedLower = downloadedIds.map((id) => id.toLowerCase()).toSet();

    final data = jsonDecode(response.body) as List<dynamic>;
    final translations = <AvailableTranslation>[];
    for (final langGroup in data.cast<Map<String, dynamic>>()) {
      final language = langGroup['language'] as String;
      for (final t
          in (langGroup['translations'] as List).cast<Map<String, dynamic>>()) {
        final slug = (t['short_name'] as String).toLowerCase();
        // Filtrar: solo versiones con licencia clara
        if (!_allowedSlugs.contains(slug)) continue;
        final name = _versionName(slug) ?? t['full_name'] as String;
        // Obtener tamaño estimado para versiones no descargadas
        int? sizeBytes;
        if (!downloadedLower.contains(slug)) {
          sizeBytes = await fetchVersionSize(slug);
        }
        translations.add(
          AvailableTranslation(
            slug: slug,
            name: name,
            language: language,
            isDownloaded: downloadedLower.contains(slug),
            sizeBytes: sizeBytes,
          ),
        );
      }
    }
    return translations;
  }

  /// Obtiene el tamaño estimado en bytes de una versión usando HEAD request
  /// para leer el Content-Length del JSON de la traducción completa.
  /// Retorna null si no se puede determinar.
  Future<int?> fetchVersionSize(String versionId) async {
    final apiSlug = _apiSlug(versionId);
    final url = '$_baseUrl/static/translations/$apiSlug.json';
    try {
      final response = await http.head(Uri.parse(url));
      if (response.statusCode == 200) {
        final contentLength = response.headers['content-length'];
        if (contentLength != null) {
          return int.tryParse(contentLength);
        }
      }
    } catch (_) {
      // Ignorar errores y retornar null
    }
    return null;
  }

  Future<Set<String>> getDownloadedVersionIds() async {
    if (kIsWeb) {
      return await _getWebDownloadedSlugs();
    }
    try {
      final db = await _db;
      final rows = await db.rawQuery(
        'SELECT DISTINCT version FROM bible_verses',
      );
      return rows.map((r) => r['version'] as String).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<List<BibleVersion>> getDownloadedVersions() async {
    if (kIsWeb) {
      final slugs = await _getWebDownloadedSlugs();
      return slugs.map((id) {
        final name = _versionName(id) ?? id.toUpperCase();
        return BibleVersion(id: id, name: name, lang: 'es');
      }).toList();
    }
    try {
      final db = await _db;
      final rows = await db.rawQuery(
        'SELECT DISTINCT version FROM bible_verses',
      );
      final versions = <BibleVersion>[];
      for (final row in rows) {
        final id = row['version'] as String;
        final name = _versionName(id) ?? id;
        versions.add(BibleVersion(id: id, name: name, lang: ''));
      }
      return versions;
    } catch (_) {
      return [];
    }
  }

  Future<Map<int, String>> _fetchBookNames(String versionId) async {
    final apiSlug = _apiSlug(versionId);
    final response = await http.get(Uri.parse('$_baseUrl/get-books/$apiSlug/'));
    if (response.statusCode != 200) return {};

    final books = jsonDecode(response.body) as List<dynamic>;
    return {
      for (final b in books.cast<Map<String, dynamic>>())
        b['bookid'] as int: b['name'] as String,
    };
  }

  Future<void> downloadVersion(
    String versionId, {
    void Function(int current, int total)? onProgress,
  }) async {
    if (kIsWeb) {
      onProgress?.call(1, 4);
      final apiSlug = _apiSlug(versionId);
      final response = await http.get(
        Uri.parse('$_baseUrl/get-books/$apiSlug/'),
      );
      if (response.statusCode != 200) {
        throw Exception('No se pudo verificar la versión en la red');
      }
      onProgress?.call(4, 4);
      await _addWebDownloadedSlug(versionId);
      return;
    }

    final apiSlug = _apiSlug(versionId);
    final bookNames = await _fetchBookNames(versionId);
    if (bookNames.isEmpty) {
      throw Exception('No se pudieron obtener los libros de esta versión');
    }

    final response = await http.get(
      Uri.parse('$_baseUrl/static/translations/$apiSlug.json'),
    );
    if (response.statusCode != 200) {
      throw Exception('Error al descargar: ${response.statusCode}');
    }

    final verses = jsonDecode(response.body) as List<dynamic>;
    final total = verses.length;

    final db = await _db;
    var batch = db.batch();
    var count = 0;

    for (final v in verses) {
      final verse = v as Map<String, dynamic>;

      final bookId = verse['book'] as int;
      final bookName = bookNames[bookId] ?? 'Book $bookId';

      batch.insert(
          'bible_verses',
          {
            'version': versionId,
            'book_id': bookId,
            'book_name': bookName,
            'chapter': verse['chapter'] as int,
            'verse': verse['verse'] as int,
            'text': _stripHtml(verse['text'] as String),
          },
          conflictAlgorithm: ConflictAlgorithm.replace);

      count++;
      if (count % _batchSize == 0 || count == total) {
        await batch.commit(noResult: true);
        batch = db.batch();
        onProgress?.call(count, total);
      }
    }
  }

  Future<void> deleteVersion(String slug) async {
    if (kIsWeb) {
      await _removeWebDownloadedSlug(slug);
      return;
    }
    final db = await _db;
    await db.delete('bible_verses', where: 'version = ?', whereArgs: [slug]);
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String? _versionName(String slug) {
    const names = {
      'rv1960': 'Reina-Valera 1960',
      'rv1909': 'Reina Valera 1909',
      'web': 'World English Bible',
      'kjv': 'King James Version',
    };
    return names[slug.toLowerCase()];
  }
}
