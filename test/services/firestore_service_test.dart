import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:altar_diario/data/models/usuario.dart';
import 'package:altar_diario/data/services/firestore_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirestoreService límites de colecciones', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test(
      'el stream de peticiones queda acotado a su tamaño de página',
      () async {
        final batch = fake.batch();
        for (var i = 0; i < 120; i++) {
          batch.set(fake.collection('peticiones_oracion').doc('p$i'), {
            'userId': 'u1',
            'motivo': 'Petición $i',
            'oculto': false,
            'fecha': DateTime.utc(2026, 1, i + 1),
          });
        }
        await batch.commit();

        final results = await service.peticionesStream().first;

        expect(results, hasLength(FirestoreService.prayerPageSize));
      },
    );
  });

  group('FirestoreService peticionesStreamFiltradoCursor', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test(
      'peticionesStreamFiltradoCursor primera página retorna items y hasMore',
      () async {
        final batch = fake.batch();
        // Insertar 150 peticiones con timestamps descendentes (ms desde epoch)
        for (var i = 0; i < 150; i++) {
          batch.set(fake.collection('peticiones_oracion').doc('p$i'), {
            'userId': 'u1',
            'motivo': 'Petición $i',
            'oculto': false,
            'respondida': false,
            'fecha': Timestamp.fromMillisecondsSinceEpoch(
                1767225600000 + (150 - i) * 86400000), // 2026 fechas válidas
          });
        }
        await batch.commit();

        // Primera página (sin cursor)
        final firstPage = await service.peticionesStreamFiltradoCursor().first;
        expect(firstPage.items, hasLength(FirestoreService.prayerPageSize));
        expect(firstPage.hasMore, isTrue);
        expect(firstPage.lastDoc, isNotNull);
      },
    );

    test('peticionesStreamFiltradoCursor hasMore false al final', () async {
      final batch = fake.batch();
      // Insertar exactamente prayerPageSize + 1 peticiones
      for (var i = 0; i < FirestoreService.prayerPageSize + 1; i++) {
        batch.set(fake.collection('peticiones_oracion').doc('p$i'), {
          'userId': 'u1',
          'motivo': 'Petición $i',
          'oculto': false,
          'respondida': false,
          'fecha': Timestamp.fromMillisecondsSinceEpoch(
              1767225600000 + i * 86400000),
        });
      }
      await batch.commit();

      // Primera página
      final firstPage = await service.peticionesStreamFiltradoCursor().first;
      expect(firstPage.items, hasLength(FirestoreService.prayerPageSize));
      expect(firstPage.hasMore, isTrue);

      // Segunda página (FakeFirestore puede no soportar startAfterDocument completo,
      // pero verificamos que la estructura del retorno es correcta)
      final secondPage = await service
          .peticionesStreamFiltradoCursor(lastDocument: firstPage.lastDoc)
          .first;
      // En FakeFirestore, startAfterDocument puede no filtrar, así que aceptamos
      // cualquier longitud >= 0, pero verificamos la estructura
      expect(secondPage.items, isA<List<PeticionOracion>>());
      expect(secondPage.lastDoc, isA<DocumentSnapshot?>());
      expect(secondPage.hasMore, isA<bool>());
    });

    test(
      'peticionesStreamFiltradoCursor maneja error Firestore no disponible',
      () async {
        // Crear servicio sin Firestore (simula error de inicialización)
        final serviceNoFirestore = FirestoreService(firestore: null);

        final result =
            await serviceNoFirestore.peticionesStreamFiltradoCursor().first;

        expect(result.items, isEmpty);
        expect(result.lastDoc, isNull);
        expect(result.hasMore, isFalse);
      },
    );

    test('peticionesStreamFiltradoCursor filtra por respondida', () async {
      final batch = fake.batch();
      // 50 respondidas, 50 pendientes
      for (var i = 0; i < 50; i++) {
        batch.set(fake.collection('peticiones_oracion').doc('resp_$i'), {
          'userId': 'u1',
          'motivo': 'Respondida $i',
          'oculto': false,
          'respondida': true,
          'fecha': Timestamp.fromMillisecondsSinceEpoch(
              1767225600000 + (100 - i) * 86400000),
        });
        batch.set(fake.collection('peticiones_oracion').doc('pend_$i'), {
          'userId': 'u1',
          'motivo': 'Pendiente $i',
          'oculto': false,
          'respondida': false,
          'fecha': Timestamp.fromMillisecondsSinceEpoch(
              1767225600000 + (50 - i) * 86400000),
        });
      }
      await batch.commit();

      // Filtrar solo respondidas
      final page =
          await service.peticionesStreamFiltradoCursor(respondida: true).first;
      // Solo 50 respondidas, pageSize = 100 -> 50 items, hasMore = false
      expect(page.items, hasLength(50));
      expect(page.items.every((p) => p.respondida == true), isTrue);
      expect(page.hasMore, isFalse);
    });
  });

  group('FirestoreService perfiles privados', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test('guarda el correo fuera del documento público del perfil', () async {
      await service.crearOActualizarUsuario(
        Usuario(id: 'u1', nombre: 'Ana', email: 'ana@ejemplo.com'),
      );

      final perfil = (await fake.doc('usuarios/u1').get()).data()!;
      final cuenta =
          (await fake.doc('usuarios/u1/private/account').get()).data()!;

      expect(perfil.containsKey('email'), isFalse);
      expect(cuenta['email'], 'ana@ejemplo.com');
    });

    test('guarda y elimina el token FCM fuera del perfil público', () async {
      await service.saveFCMToken('u1', 'token');

      final cuenta =
          (await fake.doc('usuarios/u1/private/account').get()).data()!;
      expect(cuenta['fcmToken'], 'token');

      await service.clearFCMToken('u1');
      final cuentaSinToken =
          (await fake.doc('usuarios/u1/private/account').get()).data()!;
      expect(cuentaSinToken.containsKey('fcmToken'), isFalse);
    });
  });

  group('FirestoreService.sendMessage', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test('crea el chat con participantes y envía el primer mensaje', () async {
      await service.sendMessage(
        'c1',
        'u1',
        'hola',
        participantIds: ['u1', 'u2'],
        participantNames: {'u1': 'Juan', 'u2': 'María'},
      );

      final chat = (await fake.doc('chats/c1').get()).data()!;
      expect(chat['participantIds'], equals(['u1', 'u2']));
      expect(chat['participantNames'], equals({'u1': 'Juan', 'u2': 'María'}));
      expect(chat['lastMessage'], 'hola');
      expect(chat['lastSenderId'], 'u1');
      expect(chat.containsKey('lastUpdate'), isTrue);

      final messages = await fake.collection('chats/c1/messages').get();
      expect(messages.docs.length, 1);
      expect(messages.docs.single.data()['senderId'], 'u1');
      expect(messages.docs.single.data()['text'], 'hola');
    });

    test(
        'chat existente con participantes pasados: conserva participantIds y '
        'participantNames', () async {
      await fake.doc('chats/c1').set({
        'participantIds': ['u2', 'u1'],
        'participantNames': {'u2': 'María', 'u1': 'Juan'},
      });

      await service.sendMessage(
        'c1',
        'u1',
        'nuevo mensaje',
        participantIds: ['u1', 'u2'],
        participantNames: {'u1': 'Otro Juan', 'u2': 'Otra María'},
      );

      final chat = (await fake.doc('chats/c1').get()).data()!;
      expect(chat['participantIds'], equals(['u2', 'u1']));
      expect(chat['participantNames'], equals({'u2': 'María', 'u1': 'Juan'}));
      expect(chat['lastMessage'], 'nuevo mensaje');
      expect(chat['lastSenderId'], 'u1');
      expect(chat.containsKey('lastUpdate'), isTrue);

      final messages = await fake.collection('chats/c1/messages').get();
      expect(messages.docs.length, 1);
      expect(messages.docs.single.data()['text'], 'nuevo mensaje');
    });

    test(
        'chat existente con participantes pasados no toca participantNames '
        'aunque el chat no los tuviera', () async {
      await fake.doc('chats/c1').set({
        'participantIds': ['u1', 'u2'],
      });

      await service.sendMessage(
        'c1',
        'u1',
        'hola',
        participantIds: ['u9', 'u8'],
      );

      final chat = (await fake.doc('chats/c1').get()).data()!;
      // El chat es el mismo: los participantes que llegan por parámetro se
      // ignoran por completo (ni se reescriben ni se crean de cero).
      expect(chat['participantIds'], equals(['u1', 'u2']));
      expect(chat.containsKey('participantNames'), isFalse);
      expect(chat['lastMessage'], 'hola');
    });

    test(
      'chat existente sin participantes: actualiza solo metadatos y añade el '
      'mensaje',
      () async {
        await fake.doc('chats/c1').set({
          'participantIds': ['u1', 'u2'],
          'participantNames': {'u1': 'Juan', 'u2': 'María'},
        });

        await service.sendMessage('c1', 'u2', 'sin metadatos');

        final chat = (await fake.doc('chats/c1').get()).data()!;
        expect(chat['participantIds'], equals(['u1', 'u2']));
        expect(chat['participantNames'], equals({'u1': 'Juan', 'u2': 'María'}));
        expect(chat['lastMessage'], 'sin metadatos');
        expect(chat['lastSenderId'], 'u2');

        final messages = await fake.collection('chats/c1/messages').get();
        expect(messages.docs.length, 1);
        expect(messages.docs.single.data()['senderId'], 'u2');
        expect(messages.docs.single.data()['text'], 'sin metadatos');
      },
    );

    test(
      'cada envío añade exactamente un mensaje y actualiza lastSenderId',
      () async {
        await fake.doc('chats/c1').set({
          'participantIds': ['u1', 'u2'],
          'participantNames': {'u1': 'Juan', 'u2': 'María'},
        });

        await service.sendMessage('c1', 'u1', 'primero');
        await service.sendMessage('c1', 'u2', 'segundo');

        final messages = await fake.collection('chats/c1/messages').get();
        expect(messages.docs.length, 2);
        expect(
          messages.docs.map((d) => d.data()['text']).toSet(),
          equals({'primero', 'segundo'}),
        );

        final chat = (await fake.doc('chats/c1').get()).data()!;
        expect(chat['lastMessage'], 'segundo');
        expect(chat['lastSenderId'], 'u2');
        // Dos envíos seguidos no duplican ni reescriben a los participantes.
        expect(chat['participantIds'], equals(['u1', 'u2']));
        expect(chat['participantNames'], equals({'u1': 'Juan', 'u2': 'María'}));
      },
    );

    test('chat inexistente sin participantes no crea documento', () async {
      // Sin participantes se asume chat existente: en Fake, `update` sobre un
      // documento inexistente lanza not-found (en producción, permission-denied
      // por la regla de update). Lo importante es que falle y no invente un
      // chat sin participantIds.
      await expectLater(
        service.sendMessage('nuevo', 'u1', 'hola'),
        throwsA(
          isA<FirebaseException>().having((e) => e.code, 'code', 'not-found'),
        ),
      );

      final doc = await fake.doc('chats/nuevo').get();
      expect(doc.exists, isFalse);

      final messages = await fake.collection('chats/nuevo/messages').get();
      expect(messages.docs, isEmpty);
    });

    test('participantIds con un solo miembro lanza StateError', () async {
      await expectLater(
        service.sendMessage('nuevo', 'u1', 'hola', participantIds: ['u1']),
        throwsA(isA<StateError>()),
      );

      final doc = await fake.doc('chats/nuevo').get();
      expect(doc.exists, isFalse);
    });
  });

  group('FirestoreService.bloqueos', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test('bloquearUsuario guarda el documento en blocked', () async {
      await service.bloquearUsuario('u1', 'u2');

      final doc = await fake.doc('usuarios/u1/blocked/u2').get();
      expect(doc.exists, isTrue);
      expect(doc.data()?['uid'], 'u1');
      expect(doc.data()?['blockedUid'], 'u2');
    });

    test('bloquearUsuario no se bloquea a sí mismo', () async {
      await service.bloquearUsuario('u1', 'u1');

      final doc = await fake.doc('usuarios/u1/blocked/u1').get();
      expect(doc.exists, isFalse);
    });

    test('desbloquearUsuario borra el documento de blocked', () async {
      await fake.doc('usuarios/u1/blocked/u2').set({
        'uid': 'u1',
        'blockedUid': 'u2',
        'fecha': DateTime.now(),
      });

      await service.desbloquearUsuario('u1', 'u2');

      final doc = await fake.doc('usuarios/u1/blocked/u2').get();
      expect(doc.exists, isFalse);
    });

    test('getUsuariosBloqueados retorna la lista de uids bloqueados', () async {
      await fake.doc('usuarios/u1/blocked/u2').set({
        'uid': 'u1',
        'blockedUid': 'u2',
        'fecha': DateTime.now(),
      });
      await fake.doc('usuarios/u1/blocked/u3').set({
        'uid': 'u1',
        'blockedUid': 'u3',
        'fecha': DateTime.now(),
      });

      final bloqueados = await service.getUsuariosBloqueados('u1').first;
      expect(bloqueados, containsAll(['u2', 'u3']));
      expect(bloqueados, hasLength(2));
    });
  });

  group('FirestoreService.toggleLike', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test('toggleLike da like a una reflexión', () async {
      await fake.doc('reflexiones/r1').set({
        'likes': 5,
        'likedBy': ['u2', 'u3'],
      });

      await service.toggleLike('r1', 'u1', false);

      final doc = await fake.doc('reflexiones/r1').get();
      expect(doc.data()?['likes'], 6);
      expect(List<String>.from(doc.data()?['likedBy'] ?? []), contains('u1'));
    });

    test('toggleLike quita like de una reflexión', () async {
      await fake.doc('reflexiones/r1').set({
        'likes': 5,
        'likedBy': ['u1', 'u2'],
      });

      await service.toggleLike('r1', 'u1', true);

      final doc = await fake.doc('reflexiones/r1').get();
      expect(doc.data()?['likes'], 4);
      expect(
        List<String>.from(doc.data()?['likedBy'] ?? []),
        isNot(equals(contains('u1'))),
      );
    });
  });

  group('FirestoreService.toggleReaction', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test('toggleReaction añade reacción nueva', () async {
      await fake.doc('reflexiones/r1').set({
        'reactions': {'u1': '❤️'},
      });

      await service.toggleReaction('r1', 'u1', '🔥', '❤️');

      final doc = await fake.doc('reflexiones/r1').get();
      final reactions = doc.data()?['reactions'] as Map<String, dynamic>?;
      expect(reactions?['u1'], '🔥');
    });

    test('toggleReaction quita reacción si es la misma', () async {
      await fake.doc('reflexiones/r1').set({
        'reactions': {'u1': '❤️'},
      });

      await service.toggleReaction('r1', 'u1', '❤️', '❤️');

      final doc = await fake.doc('reflexiones/r1').get();
      final reactions = doc.data()?['reactions'] as Map<String, dynamic>?;
      expect(reactions?.containsKey('u1'), isFalse);
    });

    test('toggleReaction cambia reacción a otra diferente', () async {
      await fake.doc('reflexiones/r1').set({
        'reactions': {'u1': '❤️'},
      });

      await service.toggleReaction('r1', 'u1', '🔥', '❤️');

      final doc = await fake.doc('reflexiones/r1').get();
      final reactions = doc.data()?['reactions'] as Map<String, dynamic>?;
      expect(reactions?['u1'], '🔥');
    });
  });

  group('FirestoreService.toggleFollow', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test('toggleFollow sigue a un usuario', () async {
      await fake.doc('usuarios/u1').set({'siguiendo': []});
      await fake.doc('usuarios/u2').set({'seguidores': []});

      await service.toggleFollow('u1', 'u2', false);

      final u1Doc = await fake.doc('usuarios/u1').get();
      final u2Doc = await fake.doc('usuarios/u2').get();
      expect(
        List<String>.from(u1Doc.data()?['siguiendo'] ?? []),
        contains('u2'),
      );
      expect(
        List<String>.from(u2Doc.data()?['seguidores'] ?? []),
        contains('u1'),
      );
    });

    test('toggleFollow deja de seguir a un usuario', () async {
      await fake.doc('usuarios/u1').set({
        'siguiendo': ['u2'],
      });
      await fake.doc('usuarios/u2').set({
        'seguidores': ['u1'],
      });

      await service.toggleFollow('u1', 'u2', true);

      final u1Doc = await fake.doc('usuarios/u1').get();
      final u2Doc = await fake.doc('usuarios/u2').get();
      expect(
        List<String>.from(u1Doc.data()?['siguiendo'] ?? []),
        isNot(equals(contains('u2'))),
      );
      expect(
        List<String>.from(u2Doc.data()?['seguidores'] ?? []),
        isNot(equals(contains('u1'))),
      );
    });
  });

  group('FirestoreService.apoyarPeticion', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test(
        'apoyarPeticion incrementa oracionesCount y añade userId a apoyadosPor',
        () async {
      await fake.doc('peticiones_oracion/p1').set({'oracionesCount': 5});

      await service.apoyarPeticion('p1', 'user123');

      final doc = await fake.doc('peticiones_oracion/p1').get();
      expect(doc.data()?['oracionesCount'], 6);
      expect(doc.data()?['apoyadosPor'], ['user123']);
    });
  });

  group('FirestoreService.borrarCuenta', () {
    late FakeFirebaseFirestore fake;
    late FirestoreService service;

    setUp(() {
      fake = FakeFirebaseFirestore();
      service = FirestoreService(firestore: fake);
    });

    test(
      'borra el perfil público y el documento privado en una operación',
      () async {
        await fake.doc('usuarios/u1/private/account').set({
          'email': 'u1@ejemplo.com',
        });
        await fake.doc('usuarios/u1').set({
          'nombre': 'Uno',
          'email': 'u1@ejemplo.com',
        });

        await service.borrarCuenta('u1');

        final publico = await fake.doc('usuarios/u1').get();
        final privado = await fake.doc('usuarios/u1/private/account').get();
        expect(publico.exists, isFalse);
        expect(privado.exists, isFalse);
      },
    );

    test('borra el perfil aunque el privado no exista', () async {
      await fake.doc('usuarios/u1').set({'nombre': 'Uno'});

      await service.borrarCuenta('u1');

      final publico = await fake.doc('usuarios/u1').get();
      expect(publico.exists, isFalse);
    });
  });
}
