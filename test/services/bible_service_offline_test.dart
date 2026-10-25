import 'package:altar_diario/data/services/bible_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BibleService — RVR1960 offline desde primer arranque', () {
    late BibleService service;

    setUp(() {
      service = BibleService();
    });

    test('availableVersions contiene solo rv1960 como versión empaquetada', () {
      final versions = BibleService.availableVersions;
      expect(versions.length, 1);
      expect(versions.first.id, 'rv1960');
      expect(versions.first.name, 'Reina-Valera 1960');
      expect(versions.first.lang, 'es');
      expect(versions.first.offline, true);
    });

    test('parsePassage funciona para pasajes comunes sin red', () {
      // Estos tests no requieren red ni base de datos, solo parsing
      final psalm23 = service.parsePassage('Salmos 23');
      expect(psalm23, isNotNull);
      expect(psalm23!.bookId, 19);
      expect(psalm23.bookName, 'Salmos');
      expect(psalm23.chapterStart, 23);
      expect(psalm23.verseStart, isNull);

      final john316 = service.parsePassage('Juan 3:16');
      expect(john316, isNotNull);
      expect(john316!.bookId, 43);
      expect(john316.chapterStart, 3);
      expect(john316.verseStart, 16);
    });

    test('getBookNameFromId devuelve nombres correctos para RVR1960', () {
      expect(service.getBookNameFromId(1), 'Génesis');
      expect(service.getBookNameFromId(19), 'Salmos');
      expect(service.getBookNameFromId(23), 'Isaías');
      expect(service.getBookNameFromId(40), 'Mateo');
      expect(service.getBookNameFromId(43), 'Juan');
      expect(service.getBookNameFromId(66), 'Apocalipsis');
    });

    test('getBookNames devuelve 66 libros', () {
      final names = service.getBookNames();
      expect(names.length, 66);
      expect(names.first, 'Génesis');
      expect(names.last, 'Apocalipsis');
    });

    test('reconoce variantes con acentos y abreviaturas', () {
      expect(service.parsePassage('Éxodo 1')?.bookId, 2);
      expect(service.parsePassage('Gálatas 1')?.bookId, 48);
      expect(service.parsePassage('Eclesiastés 1')?.bookId, 21);
      expect(service.parsePassage('Jn 3:16')?.bookId, 43);
      expect(service.parsePassage('1 Samuel 1')?.bookId, 9);
      expect(service.parsePassage('2 Reyes 1')?.bookId, 12);
    });
  });

  group('BibleService — getAllAvailableVersions', () {
    test('En web devuelve solo availableVersions (sin descargas)', () async {
      // En entorno de test, kIsWeb suele ser false, pero verificamos la lógica
      // Este test valida que el método existe y no falla
      final versions = await BibleService().getAllAvailableVersions();
      expect(versions, isNotEmpty);
      // Al menos rv1960 debe estar presente
      expect(versions.any((v) => v.id == 'rv1960'), isTrue);
    });
  });
}
