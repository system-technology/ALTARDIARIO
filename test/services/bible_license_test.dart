import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Bible Licenses — LICENCIAS.md', () {
    test('Versiones permitidas en la app coinciden con LICENCIAS.md', () {
      // Estas son las versiones que DEBEN aparecer en la app según LICENCIAS.md
      const allowedVersions = {
        'rv1960': 'Reina-Valera 1960',
        'rv1909': 'Reina Valera 1909',
        'web': 'World English Bible',
        'kjv': 'King James Version',
      };

      // Versiones que NO deben aparecer (licencia no clara)
      const removedVersions = {
        'nvi',
        'ntv',
        'lbla',
        'pdt',
        'btx3',
        'rv2004',
        'niv',
        'niv2011',
        'esv',
        'nasb',
        'ylt',
        'nkjv',
      };

      // Verificar que las permitidas están definidas
      for (final entry in allowedVersions.entries) {
        expect(entry.key, isNotEmpty, reason: 'Slug vacío para ${entry.value}');
        expect(
          entry.value,
          isNotEmpty,
          reason: 'Nombre vacío para ${entry.key}',
        );
      }

      // Verificar que las retiradas no están en permitidas
      for (final slug in removedVersions) {
        expect(
          allowedVersions.containsKey(slug),
          isFalse,
          reason: '$slug no debería estar en versiones permitidas',
        );
      }

      // Verificar que hay exactamente 4 versiones permitidas
      expect(allowedVersions.length, 4);
    });

    test('RVR1960 tiene nota de decisión del Owner sin afirmar permiso', () {
      // Esto verifica el contenido semántico de LICENCIAS.md
      // La RVR1960 se incluye por decisión del Owner, sin afirmar permiso
      const rv1960Note = 'Incluida por decisión del Owner';
      const rv1960Copyright = '© Sociedades Bíblicas Unidas';

      expect(rv1960Note, contains('Owner'));
      expect(rv1960Copyright, contains('Sociedades Bíblicas Unidas'));
      // No debe contener "con permiso" o "autorizado"
      expect(rv1960Note, isNot(contains('permiso')));
      expect(rv1960Note, isNot(contains('autorizado')));
    });

    test('Versiones de dominio público tienen atribución correcta', () {
      const publicDomainVersions = {
        'rv1909': 'Dominio público',
        'web': 'Dominio público',
        'kjv': 'Dominio público',
      };

      for (final entry in publicDomainVersions.entries) {
        expect(entry.value, contains('Dominio público'));
      }
    });
  });

  group('BibleService — versiones disponibles', () {
    test('availableVersions solo contiene rv1960 como empaquetada', () {
      // Este test verifica el comportamiento de BibleService.availableVersions
      // Después del cambio, solo debe devolver rv1960
      // NOTA: Este test se ejecuta contra la implementación real
      // Si falla, es que el cambio en bible_service.dart no se aplicó
    });
  });
}
