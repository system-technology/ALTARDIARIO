import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PeticionOracion', () {
    final now = DateTime(2026, 6, 6);

    test('fromMap crea instancia correctamente', () {
      final p = PeticionOracion.fromMap({
        'id': 'pet_001',
        'userId': 'user_001',
        'userName': 'Lucía',
        'motivo': 'Oren por mi familia',
        'fecha': Timestamp.fromDate(now),
        'oracionesCount': 3,
        'apoyadosPor': ['uid1', 'uid2'],
      });
      expect(p.id, 'pet_001');
      expect(p.userId, 'user_001');
      expect(p.userName, 'Lucía');
      expect(p.motivo, 'Oren por mi familia');
      expect(p.fecha, now);
      expect(p.oracionesCount, 3);
      expect(p.apoyadosPor, ['uid1', 'uid2']);
    });

    test('fromMap maneja valores nulos', () {
      final p = PeticionOracion.fromMap({});
      expect(p.id, '');
      expect(p.userId, '');
      expect(p.userName, 'Anónimo');
      expect(p.motivo, '');
      expect(p.oracionesCount, 0);
      expect(p.apoyadosPor, []);
    });

    test('toMap produce el mapa correcto', () {
      final p = PeticionOracion(
        id: 'pet_001',
        userId: 'user_001',
        userName: 'Pedro',
        motivo: 'Sanidad',
        fecha: now,
        oracionesCount: 5,
        apoyadosPor: ['uid1', 'uid2'],
      );
      final map = p.toMap();
      expect(map['userId'], 'user_001');
      expect(map['userName'], 'Pedro');
      expect(map['motivo'], 'Sanidad');
      expect(map['oracionesCount'], 5);
      expect(map['fecha'], isA<Timestamp>());
      expect(map['apoyadosPor'], ['uid1', 'uid2']);
    });

    test('oracionesCount por defecto es 0', () {
      final p = PeticionOracion(
        id: 'pet_002',
        userId: 'user_002',
        userName: 'Ana',
        motivo: 'Trabajo',
        fecha: now,
      );
      expect(p.oracionesCount, 0);
      expect(p.apoyadosPor, []);
    });

    test('apoyadosPor por defecto es lista vacía', () {
      final p = PeticionOracion(
        id: 'pet_003',
        userId: 'user_003',
        userName: 'Juan',
        motivo: 'Salud',
        fecha: now,
      );
      expect(p.apoyadosPor, []);
    });
  });
}
