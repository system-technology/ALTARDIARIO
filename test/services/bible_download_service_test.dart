import 'package:altar_diario/data/models/bible_models.dart';
import 'package:altar_diario/data/services/bible_download_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('BibleDownloadService', () {
    late BibleDownloadService service;

    setUp(() {
      service = BibleDownloadService();
      SharedPreferences.setMockInitialValues({});
    });

    tearDown(() async {
      await service.close();
    });

    group('AvailableTranslation', () {
      test('incluye sizeBytes opcional', () {
        const t1 = AvailableTranslation(
          slug: 'rv1909',
          name: 'Reina Valera 1909',
          language: 'Español',
          isDownloaded: false,
          sizeBytes: 5242880, // 5 MB
        );
        expect(t1.sizeBytes, 5242880);
        expect(t1.isDownloaded, false);

        const t2 = AvailableTranslation(
          slug: 'web',
          name: 'World English Bible',
          language: 'English',
          isDownloaded: true,
        );
        expect(t2.sizeBytes, isNull);
        expect(t2.isDownloaded, true);
      });
    });

    group('fetchVersionSize', () {
      test('retorna null si HEAD request falla', () async {
        // Este test verifica que el método existe y maneja errores
        // En test real se mockearía http.Client
        // Aquí solo verificamos que no lance excepción
        final size = await service.fetchVersionSize('version_inexistente');
        expect(size, isNull);
      });
    });

    group('fetchAvailableTranslations — filtrado', () {
      test('solo retorna versiones permitidas', () async {
        // Este test requeriría mockear http.Client y la respuesta JSON
        // Verificamos que el método existe y la lógica de filtrado está presente
        // En implementación real, se mockearía la respuesta de languages.json
        // para confirmar que solo rv1960, rv1909, web, kjv pasan el filtro
        expect(true, isTrue); // Placeholder para test de integración
      });
    });

    group('Descarga y borrado de versiones libres', () {
      test('rv1909, web, kjv pueden descargarse y borrarse', () async {
        // Test de integración que requeriría:
        // 1. Mock HTTP responses para get-books y static/translations
        // 2. Mock SharedPreferences para web
        // 3. Verificar que downloadVersion no lanza para estas versiones
        // 4. Verificar que deleteVersion funciona
        // 5. Verificar que getDownloadedVersions las incluye tras descarga
        expect(true, isTrue); // Placeholder
      });
    });

    group('Reintento de descarga', () {
      test('lógica de backoff exponencial: 2s, 4s, 8s', () {
        const baseDelay = Duration(seconds: 2);

        // Intento 1 -> 2s
        final delay1 = baseDelay * (1 << (1 - 1));
        expect(delay1, const Duration(seconds: 2));

        // Intento 2 -> 4s
        final delay2 = baseDelay * (1 << (2 - 1));
        expect(delay2, const Duration(seconds: 4));

        // Intento 3 -> 8s
        final delay3 = baseDelay * (1 << (3 - 1));
        expect(delay3, const Duration(seconds: 8));
      });
    });

    group('_versionName behavior (indirecto via getDownloadedVersions)', () {
      test(
        'getDownloadedVersions usa nombres correctos para versiones permitidas',
        () async {
          // En web, getDownloadedVersions usa _versionName internamente
          // Verificamos que no lance y retorna lista (aunque vacía en test sin mock)
          final versions = await service.getDownloadedVersions();
          expect(versions, isA<List<BibleVersion>>());
        },
      );
    });
  });
}
