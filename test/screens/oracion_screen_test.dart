import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:altar_diario/data/services/firestore_service.dart';
import 'package:altar_diario/features/oracion/presentation/oracion_screen.dart';
import 'package:altar_diario/presentation/providers/app_providers.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('OracionScreen — filtro "Por las que oro"', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService firestore;

    setUp(() {
      fake = FakeFirebaseFirestore();
      firestore = FirestoreService(firestore: fake);
    });

    Widget buildTestWidget({
      required String currentUid,
      required List<PeticionOracion> peticiones,
      List<String> blockedUids = const [],
    }) {
      // Seed peticiones
      final batch = fake.batch();
      for (final p in peticiones) {
        batch.set(
          fake.collection('peticiones_oracion').doc(p.id),
          p.toMap(),
        );
      }
      // Seed blocked users
      for (final blockedUid in blockedUids) {
        batch.set(
          fake
              .collection('usuarios')
              .doc(currentUid)
              .collection('blocked')
              .doc(blockedUid),
          {
            'uid': currentUid,
            'blockedUid': blockedUid,
            'fecha': DateTime.now()
          },
        );
      }
      batch.commit();

      return ProviderScope(
        overrides: [
          firestoreServiceProvider.overrideWithValue(firestore),
          effectiveUserUidProvider.overrideWithValue(currentUid),
          isGuestUserProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(
          home: OracionScreen(),
        ),
      );
    }

    testWidgets('PopupMenuButton muestra opción "Por las que oro"',
        (tester) async {
      final peticiones = [
        PeticionOracion(
          id: 'p1',
          userId: 'u1',
          userName: 'User 1',
          motivo: 'Petición 1',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        currentUid: 'currentUser',
        peticiones: peticiones,
      ));

      // Find and tap the filter button
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Verify all filter options are present
      expect(find.text('Todas'), findsOneWidget);
      expect(find.text('Pendientes'), findsOneWidget);
      expect(find.text('Respondidas'), findsOneWidget);
      expect(find.text('Por las que oro'), findsOneWidget);
    });

    testWidgets(
        'Filtrar por "Por las que oro" muestra solo peticiones donde el usuario está en apoyadosPor',
        (tester) async {
      final peticiones = [
        PeticionOracion(
          id: 'p1',
          userId: 'u1',
          userName: 'User 1',
          motivo: 'Petición donde oré',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
        ),
        PeticionOracion(
          id: 'p2',
          userId: 'u2',
          userName: 'User 2',
          motivo: 'Petición donde no oré',
          fecha: DateTime.now(),
          apoyadosPor: ['otroUsuario'],
        ),
        PeticionOracion(
          id: 'p3',
          userId: 'u3',
          userName: 'User 3',
          motivo: 'Otra donde oré',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser', 'otroUsuario'],
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        currentUid: 'currentUser',
        peticiones: peticiones,
      ));

      // Wait for initial load
      await tester.pumpAndSettle();

      // Tap filter button
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Select "Por las que oro"
      await tester.tap(find.text('Por las que oro'));
      await tester.pumpAndSettle();

      // Verify only p1 and p3 are shown (they have currentUser in apoyadosPor)
      expect(find.text('Petición donde oré'), findsOneWidget);
      expect(find.text('Otra donde oré'), findsOneWidget);
      expect(find.text('Petición donde no oré'), findsNothing);
    });

    testWidgets('Filtro "Por las que oro" respeta usuarios bloqueados',
        (tester) async {
      final peticiones = [
        PeticionOracion(
          id: 'p1',
          userId: 'u1',
          userName: 'User 1',
          motivo: 'Petición visible',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
        ),
        PeticionOracion(
          id: 'p2',
          userId: 'u2',
          userName: 'User 2 (bloqueado)',
          motivo: 'Petición de bloqueado',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
        ),
        PeticionOracion(
          id: 'p3',
          userId: 'u3',
          userName: 'User 3',
          motivo: 'Otra visible',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        currentUid: 'currentUser',
        peticiones: peticiones,
        blockedUids: ['u2'],
      ));

      await tester.pumpAndSettle();

      // Tap filter button
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Select "Por las que oro"
      await tester.tap(find.text('Por las que oro'));
      await tester.pumpAndSettle();

      // Verify only p1 and p3 are shown (p2 is from blocked user)
      expect(find.text('Petición visible'), findsOneWidget);
      expect(find.text('Otra visible'), findsOneWidget);
      expect(find.text('Petición de bloqueado'), findsNothing);
    });

    testWidgets('Filtro "Por las que oro" oculta peticiones con oculto=true',
        (tester) async {
      final peticiones = [
        PeticionOracion(
          id: 'p1',
          userId: 'u1',
          userName: 'User 1',
          motivo: 'Petición visible',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
          oculto: false,
        ),
        PeticionOracion(
          id: 'p2',
          userId: 'u2',
          userName: 'User 2',
          motivo: 'Petición oculta',
          fecha: DateTime.now(),
          apoyadosPor: ['currentUser'],
          oculto: true,
        ),
      ];

      await tester.pumpWidget(buildTestWidget(
        currentUid: 'currentUser',
        peticiones: peticiones,
      ));

      await tester.pumpAndSettle();

      // Tap filter button
      await tester.tap(find.byIcon(Icons.filter_list));
      await tester.pumpAndSettle();

      // Select "Por las que oro"
      await tester.tap(find.text('Por las que oro'));
      await tester.pumpAndSettle();

      // Verify only p1 is shown (p2 has oculto=true)
      expect(find.text('Petición visible'), findsOneWidget);
      expect(find.text('Petición oculta'), findsNothing);
    });
  });
}
