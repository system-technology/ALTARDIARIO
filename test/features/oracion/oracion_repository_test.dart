import 'package:altar_diario/data/services/firestore_service.dart';
import 'package:altar_diario/features/oracion/data/oracion_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OracionRepository — filtros oculto y bloqueados', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService firestore;
    late OracionRepository repository;

    setUp(() {
      fake = FakeFirebaseFirestore();
      firestore = FirestoreService(firestore: fake);
      repository = OracionRepository(firestore);
    });

    Future<void> seedPeticiones({
      required List<Map<String, dynamic>> peticiones,
    }) async {
      final batch = fake.batch();
      for (final p in peticiones) {
        batch.set(
          fake.collection('peticiones_oracion').doc(p['id'] as String),
          p,
        );
      }
      await batch.commit();
    }

    Future<void> seedBloqueados({
      required String uid,
      required List<String> blockedUids,
    }) async {
      final batch = fake.batch();
      for (final blockedUid in blockedUids) {
        batch.set(
          fake
              .collection('usuarios')
              .doc(uid)
              .collection('blocked')
              .doc(blockedUid),
          {'uid': uid, 'blockedUid': blockedUid, 'fecha': DateTime.now()},
        );
      }
      await batch.commit();
    }

    test('peticionesStream excluye peticiones con oculto == true', () async {
      // Arrange: 3 peticiones, una con oculto == true
      await seedPeticiones(
        peticiones: [
          {
            'id': 'p1',
            'userId': 'u1',
            'userName': 'User 1',
            'motivo': 'Petición 1',
            'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
            'oculto': false,
          },
          {
            'id': 'p2',
            'userId': 'u2',
            'userName': 'User 2',
            'motivo': 'Petición 2 (oculta)',
            'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
            'oculto': true,
          },
          {
            'id': 'p3',
            'userId': 'u3',
            'userName': 'User 3',
            'motivo': 'Petición 3',
            'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
            'oculto': false,
          },
        ],
      );

      // Act
      final result =
          await repository.peticionesStream(uid: 'currentUser').first;

      // Assert: solo p1 y p3 (p2 tiene oculto == true)
      expect(result, hasLength(2));
      expect(result.map((p) => p.id).toSet(), equals({'p1', 'p3'}));
    });

    test(
      'peticionesStream excluye peticiones de usuarios bloqueados',
      () async {
        // Arrange: 3 peticiones de distintos usuarios
        await seedPeticiones(
          peticiones: [
            {
              'id': 'p1',
              'userId': 'u1',
              'userName': 'User 1',
              'motivo': 'Petición 1',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
              'oculto': false,
            },
            {
              'id': 'p2',
              'userId': 'u2',
              'userName': 'User 2',
              'motivo': 'Petición 2',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
              'oculto': false,
            },
            {
              'id': 'p3',
              'userId': 'u3',
              'userName': 'User 3',
              'motivo': 'Petición 3',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
              'oculto': false,
            },
          ],
        );

        // Bloquear a u2
        await seedBloqueados(uid: 'currentUser', blockedUids: ['u2']);

        // Act
        final result =
            await repository.peticionesStream(uid: 'currentUser').first;

        // Assert: solo p1 y p3 (p2 es de usuario bloqueado)
        expect(result, hasLength(2));
        expect(result.map((p) => p.id).toSet(), equals({'p1', 'p3'}));
      },
    );

    test(
      'peticionesStream aplica ambos filtros juntos (oculto + bloqueados)',
      () async {
        // Arrange: 4 peticiones
        // p1: normal (visible)
        // p2: oculto == true
        // p3: usuario bloqueado
        // p4: oculto == true Y usuario bloqueado
        await seedPeticiones(
          peticiones: [
            {
              'id': 'p1',
              'userId': 'u1',
              'userName': 'User 1',
              'motivo': 'Petición 1 (normal)',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
              'oculto': false,
            },
            {
              'id': 'p2',
              'userId': 'u2',
              'userName': 'User 2',
              'motivo': 'Petición 2 (oculta)',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
              'oculto': true,
            },
            {
              'id': 'p3',
              'userId': 'u3',
              'userName': 'User 3',
              'motivo': 'Petición 3 (bloqueado)',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
              'oculto': false,
            },
            {
              'id': 'p4',
              'userId': 'u4',
              'userName': 'User 4',
              'motivo': 'Petición 4 (oculta y bloqueada)',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 4)),
              'oculto': true,
            },
          ],
        );

        // Bloquear a u3 y u4
        await seedBloqueados(uid: 'currentUser', blockedUids: ['u3', 'u4']);

        // Act
        final result =
            await repository.peticionesStream(uid: 'currentUser').first;

        // Assert: solo p1 sobrevive a ambos filtros
        expect(result, hasLength(1));
        expect(result.single.id, 'p1');
      },
    );

    test(
      'peticionesStreamFiltrado respeta filtro respondida + ambos filtros',
      () async {
        // Arrange: 4 peticiones con diferentes estados respondida
        await seedPeticiones(
          peticiones: [
            {
              'id': 'p1',
              'userId': 'u1',
              'userName': 'User 1',
              'motivo': 'Pendiente visible',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
              'oculto': false,
              'respondida': false,
            },
            {
              'id': 'p2',
              'userId': 'u2',
              'userName': 'User 2',
              'motivo': 'Respondida visible',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
              'oculto': false,
              'respondida': true,
            },
            {
              'id': 'p3',
              'userId': 'u3',
              'userName': 'User 3',
              'motivo': 'Pendiente oculta',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 3)),
              'oculto': true,
              'respondida': false,
            },
            {
              'id': 'p4',
              'userId': 'u4',
              'userName': 'User 4',
              'motivo': 'Respondida bloqueada',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 4)),
              'oculto': false,
              'respondida': true,
            },
          ],
        );

        // Bloquear a u4
        await seedBloqueados(uid: 'currentUser', blockedUids: ['u4']);

        // Act: filtrar solo respondidas
        final result = await repository
            .peticionesStreamFiltrado(uid: 'currentUser', respondida: true)
            .first;

        // Assert: solo p2 (respondida, no oculta, no bloqueada)
        expect(result, hasLength(1));
        expect(result.single.id, 'p2');
        expect(result.single.respondida, isTrue);
      },
    );

    test(
      'peticionesStreamFiltrado con respondida == null no filtra por estado',
      () async {
        // Arrange: 2 peticiones, una pendiente y una respondida, ambas visibles
        await seedPeticiones(
          peticiones: [
            {
              'id': 'p1',
              'userId': 'u1',
              'userName': 'User 1',
              'motivo': 'Pendiente',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 1)),
              'oculto': false,
              'respondida': false,
            },
            {
              'id': 'p2',
              'userId': 'u2',
              'userName': 'User 2',
              'motivo': 'Respondida',
              'fecha': Timestamp.fromDate(DateTime.utc(2026, 1, 2)),
              'oculto': false,
              'respondida': true,
            },
          ],
        );

        // Act: sin filtro por respondida
        final result = await repository
            .peticionesStreamFiltrado(uid: 'currentUser', respondida: null)
            .first;

        // Assert: ambas peticiones
        expect(result, hasLength(2));
        expect(result.map((p) => p.id).toSet(), equals({'p1', 'p2'}));
      },
    );

    test('peticionesStream lanza ArgumentError si uid es vacío', () async {
      await expectLater(
        () => repository.peticionesStream(uid: ''),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'peticionesStreamFiltrado lanza ArgumentError si uid es vacío',
      () async {
        await expectLater(
          () => repository.peticionesStreamFiltrado(uid: '', respondida: null),
          throwsA(isA<ArgumentError>()),
        );
      },
    );
  });
}
