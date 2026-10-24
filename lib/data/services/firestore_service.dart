import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../models/bible_models.dart';
import '../models/bloqueo.dart';
import '../models/comment.dart';
import '../models/debate.dart';
import '../models/debate_reply.dart';
import '../models/message.dart';
import '../models/note.dart';
import '../models/peticion_oracion.dart';
import '../models/reflexion.dart';
import '../models/usuario.dart';

class FirestoreService {
  final FirebaseFirestore? _firestore;

  FirestoreService({FirebaseFirestore? firestore})
    : _firestore = firestore ?? _initFirestore();

  static FirebaseFirestore? _initFirestore() {
    try {
      final instance = FirebaseFirestore.instance;
      if (!kIsWeb) {
        instance.settings = const Settings(persistenceEnabled: true);
      }
      return instance;
    } catch (_) {
      return null;
    }
  }

  bool get _available => _firestore != null;

  FirebaseFirestore? get firestore => _firestore;

  CollectionReference<Map<String, dynamic>> get _reflexiones =>
      _firestore!.collection('reflexiones');

  CollectionReference<Map<String, dynamic>> get _peticiones =>
      _firestore!.collection('peticiones_oracion');

  CollectionReference<Map<String, dynamic>> get _usuarios =>
      _firestore!.collection('usuarios');

  CollectionReference<Map<String, dynamic>> get _chats =>
      _firestore!.collection('chats');

  CollectionReference<Map<String, dynamic>> _bibleHighlights(String userId) =>
      _usuarios.doc(userId).collection('bible_highlights');

  CollectionReference<Map<String, dynamic>> get _debates =>
      _firestore!.collection('debates');

  CollectionReference<Map<String, dynamic>> _debateReplies(String debateId) =>
      _debates.doc(debateId).collection('respuestas');

  CollectionReference<Map<String, dynamic>> _bibleNotes(String userId) =>
      _usuarios.doc(userId).collection('bible_notes');

  // ââ Reflexiones ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// TamaÃ±o de pÃ¡gina del feed. Sin lÃ­mite, cada apertura del feed leÃ­a TODA
  /// la colecciÃ³n (coste y latencia lineales con el nÃºmero de reflexiones).
  /// TODO(roadmap-fase-1): paginaciÃ³n real con startAfterDocument.
  static const int feedPageSize = 30;
  static const int userReflectionsPageSize = 50;
  static const int commentsPageSize = 100;
  static const int debatePageSize = 50;
  static const int debateRepliesPageSize = 100;
  static const int messagesPageSize = 100;
  static const int chatsPageSize = 50;
  static const int prayerPageSize = 100;

  Stream<List<Reflexion>> reflexionesStream() {
    if (!_available) return Stream.value([]);
    return _reflexiones
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(feedPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Reflexion.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  /// Carga una página de reflexiones usando cursor (startAfterDocument).
  Future<({List<Reflexion> items, DocumentSnapshot? lastDoc, bool hasMore})>
  getReflexionesPage({DocumentSnapshot? lastDoc}) async {
    if (!_available) {
      return (items: <Reflexion>[], lastDoc: null, hasMore: false);
    }
    var query = _reflexiones.orderBy('fecha', descending: true);
    if (lastDoc != null) {
      query = query.startAfterDocument(lastDoc);
    }
    final snapshot = await query.limit(feedPageSize).get();
    final items = snapshot.docs
        .map((d) => Reflexion.fromMap({'id': d.id, ...d.data()}))
        .toList();
    final newLastDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
    final hasMore = snapshot.docs.length >= feedPageSize;
    return (items: items, lastDoc: newLastDoc, hasMore: hasMore);
  }

  Stream<List<Reflexion>> getUserReflexiones(String userId) {
    if (!_available) return Stream.value([]);
    return _reflexiones
        .where('userId', isEqualTo: userId)
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(userReflectionsPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Reflexion.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  Future<void> publicarReflexion(Reflexion reflexion) async {
    if (!_available) return;
    await _reflexiones.add(reflexion.toMap());
  }

  Future<void> toggleLike(
    String reflexionId,
    String userId,
    bool isLiked,
  ) async {
    if (!_available) return;
    if (isLiked) {
      await _reflexiones.doc(reflexionId).update({
        'likes': FieldValue.increment(-1),
        'likedBy': FieldValue.arrayRemove([userId]),
      });
    } else {
      await _reflexiones.doc(reflexionId).update({
        'likes': FieldValue.increment(1),
        'likedBy': FieldValue.arrayUnion([userId]),
      });
    }
  }

  Stream<List<Reflexion>> getUserReflexionesWithUid(String userId) {
    if (!_available) return Stream.value([]);
    return _reflexiones
        .where('userId', isEqualTo: userId)
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(userReflectionsPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Reflexion.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  Future<List<Reflexion>> getUserReflexionesOnce(String userId) async {
    if (!_available) return [];
    final snapshot = await _reflexiones
        .where('userId', isEqualTo: userId)
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(50)
        .get();
    return snapshot.docs
        .map((d) => Reflexion.fromMap({'id': d.id, ...d.data()}))
        .toList();
  }

  // ââ Comentarios ââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Stream<List<Comment>> comentariosStream(String reflexionId) {
    if (!_available) return Stream.value([]);
    return _reflexiones
        .doc(reflexionId)
        .collection('comentarios')
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: false)
        .limit(commentsPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Comment.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  /// Stream de comentarios con paginación por cursor.
  /// [lastDocument] es el último documento de la página anterior (opcional).
  Stream<List<Comment>> comentariosStreamCursor(
    String reflexionId, {
    DocumentSnapshot? lastDocument,
  }) {
    if (!_available) return Stream.value([]);
    Query query = _reflexiones
        .doc(reflexionId)
        .collection('comentarios')
        .orderBy('fecha', descending: false)
        .limit(commentsPageSize);
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.snapshots().map(
      (s) => s.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) return null;
            return Comment.fromMap({'id': d.id, ...data});
          })
          .whereType<Comment>()
          .toList(),
    );
  }

  Future<void> publicarComentario(Comment comment) async {
    if (!_available) return;
    await _reflexiones
        .doc(comment.reflexionId)
        .collection('comentarios')
        .add(comment.toMap());
    await _reflexiones.doc(comment.reflexionId).update({
      'commentCount': FieldValue.increment(1),
    });

    final refDoc = await _reflexiones.doc(comment.reflexionId).get();
    if (refDoc.exists) {
      final data = refDoc.data()!;
      final authorId = data['userId'] as String?;
      if (authorId != null && authorId != comment.userId) {
        await createNotification(
          userId: authorId,
          type: 'new_comment',
          title: 'Nuevo comentario',
          body: '${comment.userName} comentÃ³ en tu reflexiÃ³n.',
          actorId: comment.userId,
          actorName: comment.userName,
          actorFotoUrl: comment.userFotoUrl,
          data: {'reflexionId': comment.reflexionId},
        );
      }
    }
  }

  Future<void> toggleCommentLike(
    String reflexionId,
    String commentId,
    String userId,
    bool isLiked,
  ) async {
    if (!_available) return;
    if (isLiked) {
      await _reflexiones
          .doc(reflexionId)
          .collection('comentarios')
          .doc(commentId)
          .update({
            'likes': FieldValue.increment(-1),
            'likedBy': FieldValue.arrayRemove([userId]),
          });
    } else {
      await _reflexiones
          .doc(reflexionId)
          .collection('comentarios')
          .doc(commentId)
          .update({
            'likes': FieldValue.increment(1),
            'likedBy': FieldValue.arrayUnion([userId]),
          });
    }
  }

  // ââ Debates BÃ­blicos âââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Stream<List<Debate>> debatesStream({String? libroId}) {
    if (!_available) return Stream.value([]);
    var query =
        _debates
                .where('oculto', isEqualTo: false)
                .orderBy('fecha', descending: true)
            as Query;
    if (libroId != null && libroId.isNotEmpty) {
      query = query.where('libroId', isEqualTo: libroId);
    }
    query = query.limit(debatePageSize);
    return query.snapshots().map(
      (s) => s.docs
          .map(
            (d) => Debate.fromMap({
              'id': d.id,
              ...d.data() as Map<String, dynamic>,
            }),
          )
          .toList(),
    );
  }

  Future<void> crearDebate(Debate debate) async {
    if (!_available) return;
    await _debates.add(debate.toMap());
  }

  Future<void> toggleDebateVote(
    String debateId,
    String userId,
    bool hasVoted,
  ) async {
    if (!_available) return;
    if (hasVoted) {
      await _debates.doc(debateId).update({
        'upvotes': FieldValue.increment(-1),
        'votedBy': FieldValue.arrayRemove([userId]),
      });
    } else {
      await _debates.doc(debateId).update({
        'upvotes': FieldValue.increment(1),
        'votedBy': FieldValue.arrayUnion([userId]),
      });
    }
  }

  /// Cierra un debate (solo el autor).
  Future<void> cerrarDebate(String debateId) async {
    if (!_available) return;
    await _debates.doc(debateId).update({'cerrado': true});
  }

  /// Oculta un debate (moderación).
  Future<void> ocultarDebate(String debateId) async {
    if (!_available) return;
    await _debates.doc(debateId).update({'oculto': true});
  }

  // ââ Respuestas de Debates ââââââââââââââââââââââââââââââââââââââââââââââââ

  Stream<List<DebateReply>> debateRepliesStream(String debateId) {
    if (!_available) return Stream.value([]);
    return _debateReplies(debateId)
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: false)
        .limit(debateRepliesPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => DebateReply.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  /// Stream de respuestas de debates con paginación por cursor.
  /// [lastDocument] es el último documento de la página anterior (opcional).
  Stream<List<DebateReply>> debateRepliesStreamCursor(
    String debateId, {
    DocumentSnapshot? lastDocument,
  }) {
    if (!_available) return Stream.value([]);
    Query query = _debateReplies(
      debateId,
    ).orderBy('fecha', descending: false).limit(debateRepliesPageSize);
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.snapshots().map(
      (s) => s.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) return null;
            return DebateReply.fromMap({'id': d.id, ...data});
          })
          .whereType<DebateReply>()
          .toList(),
    );
  }

  Future<void> crearRespuesta(DebateReply reply) async {
    if (!_available) return;
    await _debateReplies(reply.debateId).add(reply.toMap());
    await _debates.doc(reply.debateId).update({
      'replyCount': FieldValue.increment(1),
    });

    final debateDoc = await _debates.doc(reply.debateId).get();
    if (debateDoc.exists) {
      final data = debateDoc.data()!;
      final authorId = data['userId'] as String?;
      if (authorId != null && authorId != reply.userId) {
        await createNotification(
          userId: authorId,
          type: 'debate_reply',
          title: 'Nueva respuesta',
          body: '${reply.userName} respondiÃ³ a tu debate.',
          actorId: reply.userId,
          actorName: reply.userName,
          data: {'debateId': reply.debateId},
        );
      }
    }
  }

  Future<void> toggleReplyVote(
    String debateId,
    String replyId,
    String userId,
    bool hasVoted,
  ) async {
    if (!_available) return;
    if (hasVoted) {
      await _debateReplies(debateId).doc(replyId).update({
        'upvotes': FieldValue.increment(-1),
        'votedBy': FieldValue.arrayRemove([userId]),
      });
    } else {
      await _debateReplies(debateId).doc(replyId).update({
        'upvotes': FieldValue.increment(1),
        'votedBy': FieldValue.arrayUnion([userId]),
      });
    }
  }

  // ââ Reacciones âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Future<void> toggleReaction(
    String reflexionId,
    String userId,
    String? emoji,
    String? currentEmoji,
  ) async {
    if (!_available) return;
    if (currentEmoji == emoji) {
      await _reflexiones.doc(reflexionId).update({
        'reactions.$userId': FieldValue.delete(),
      });
    } else {
      await _reflexiones.doc(reflexionId).update({'reactions.$userId': emoji});
    }
  }

  // ââ Usuarios âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Stream<Usuario?> getUsuario(String uid) {
    if (!_available) return Stream.value(null);
    return _usuarios
        .doc(uid)
        .snapshots()
        .map(
          (d) => d.exists ? Usuario.fromMap({'id': d.id, ...d.data()!}) : null,
        );
  }

  Future<Usuario?> getUsuarioOnce(String uid) async {
    if (!_available) return null;
    final doc = await _usuarios.doc(uid).get();
    if (!doc.exists) return null;
    return Usuario.fromMap({'id': doc.id, ...doc.data()!});
  }

  Stream<List<Usuario>> getUsuariosStream(List<String> uids) {
    if (!_available) return Stream.value([]);
    if (uids.isEmpty) return Stream.value([]);
    return _usuarios
        .where(FieldPath.documentId, whereIn: uids)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Usuario.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  Future<List<Usuario>> getSiguiendoUsuarios(String uid) async {
    if (!_available) return [];
    final usuario = await getUsuarioOnce(uid);
    if (usuario == null || usuario.siguiendo.isEmpty) return [];
    final snapshot = await _usuarios
        .where(FieldPath.documentId, whereIn: usuario.siguiendo)
        .get();
    return snapshot.docs
        .map((d) => Usuario.fromMap({'id': d.id, ...d.data()}))
        .toList();
  }

  Future<List<Usuario>> getAllUsuarios() async {
    if (!_available) return [];
    final snapshot = await _usuarios.limit(100).get();
    return snapshot.docs
        .map((d) => Usuario.fromMap({'id': d.id, ...d.data()}))
        .toList();
  }

  Future<List<Usuario>> getSeguidoresUsuarios(String uid) async {
    if (!_available) return [];
    final usuario = await getUsuarioOnce(uid);
    if (usuario == null || usuario.seguidores.isEmpty) return [];
    final snapshot = await _usuarios
        .where(FieldPath.documentId, whereIn: usuario.seguidores)
        .get();
    return snapshot.docs
        .map((d) => Usuario.fromMap({'id': d.id, ...d.data()}))
        .toList();
  }

  /// Obtiene datos de racha (progresoLectura, maxStreak) para una lista de usuarios.
  /// Usado para las rachas entre amigos y el leaderboard.
  Future<Map<String, Map<String, dynamic>>> getStreaksData(
    List<String> uids,
  ) async {
    if (!_available || uids.isEmpty) return {};
    final result = <String, Map<String, dynamic>>{};
    final snapshot = await _usuarios
        .where(FieldPath.documentId, whereIn: uids)
        .get();
    for (final doc in snapshot.docs) {
      final data = doc.data();
      result[doc.id] = {
        'nombre': data['nombre'] ?? '',
        'fotoUrl': data['fotoUrl'] ?? '',
        'progresoLectura': List<String>.from(data['progresoLectura'] ?? []),
        'maxStreak': data['maxStreak'] ?? 0,
      };
    }
    return result;
  }

  Future<void> crearOActualizarUsuario(Usuario usuario) async {
    if (!_available) return;
    final userRef = _usuarios.doc(usuario.id);
    await userRef.set(usuario.toMap(), SetOptions(merge: true));
    if (usuario.privateAccountMap.isNotEmpty) {
      await userRef
          .collection('private')
          .doc('account')
          .set(usuario.privateAccountMap, SetOptions(merge: true));
    }
  }

  /// Toggle un tema seguido por [uid]. Si [siguiendo] es true, agrega el tema;
  /// si es false, lo elimina.
  Future<void> toggleTemaSeguido(
    String uid,
    String tema,
    bool siguiendo,
  ) async {
    if (!_available) return;
    if (siguiendo) {
      await _usuarios.doc(uid).update({
        'temasSeguidos': FieldValue.arrayUnion([tema]),
      });
    } else {
      await _usuarios.doc(uid).update({
        'temasSeguidos': FieldValue.arrayRemove([tema]),
      });
    }
  }

  /// Borra el perfil público y su documento privado (`private/account`) en
  /// una sola operación. Si el documento privado no existe, el batch sigue
  /// adelante y borra el público.
  Future<void> borrarCuenta(String uid) async {
    if (!_available) return;
    final batch = _firestore!.batch();
    batch.delete(_usuarios.doc(uid).collection('private').doc('account'));
    batch.delete(_usuarios.doc(uid));
    await batch.commit();
  }

  Future<void> toggleFollow(
    String currentUserId,
    String targetUserId,
    bool isFollowing,
  ) async {
    if (!_available) return;
    final currentDoc = _usuarios.doc(currentUserId);
    final targetDoc = _usuarios.doc(targetUserId);

    if (isFollowing) {
      await currentDoc.set({
        'siguiendo': FieldValue.arrayRemove([targetUserId]),
      }, SetOptions(merge: true));
      await targetDoc.set({
        'seguidores': FieldValue.arrayRemove([currentUserId]),
      }, SetOptions(merge: true));
    } else {
      await currentDoc.set({
        'siguiendo': FieldValue.arrayUnion([targetUserId]),
      }, SetOptions(merge: true));
      await targetDoc.set({
        'seguidores': FieldValue.arrayUnion([currentUserId]),
      }, SetOptions(merge: true));

      final currentUserSnap = await currentDoc.get();
      if (currentUserSnap.exists) {
        final data = currentUserSnap.data()!;
        await createNotification(
          userId: targetUserId,
          type: 'new_follower',
          title: 'Nuevo seguidor',
          body: '${data['nombre'] ?? 'Alguien'} te ha empezado a seguir.',
          actorId: currentUserId,
          actorName: data['nombre'],
          actorFotoUrl: data['fotoUrl'],
          data: {'userId': currentUserId},
        );
      }
    }
  }

  Future<void> updateUserConfig(String uid, Map<String, dynamic> config) async {
    if (!_available) return;
    await _usuarios.doc(uid).set(config, SetOptions(merge: true));
  }

  Future<void> syncProgress(
    String userId,
    List<String> completedDates,
    int maxStreak,
  ) async {
    if (!_available) return;
    await _usuarios.doc(userId).set({
      'progresoLectura': completedDates,
      'maxStreak': maxStreak,
      'lastSync': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Guarda el token FCM del usuario para push notifications.
  Future<void> saveFCMToken(String uid, String token) async {
    if (!_available) return;
    await _usuarios.doc(uid).collection('private').doc('account').set({
      'fcmToken': token,
    }, SetOptions(merge: true));
  }

  /// Elimina el token FCM del usuario (logout).
  Future<void> clearFCMToken(String uid) async {
    if (!_available) return;
    await _usuarios.doc(uid).collection('private').doc('account').set({
      'fcmToken': FieldValue.delete(),
    }, SetOptions(merge: true));
  }

  /// Crea una notificaciÃ³n en la subcolecciÃ³n del usuario (para Cloud Functions).
  Future<void> createNotification({
    required String userId,
    required String type,
    required String title,
    required String body,
    Map<String, String>? data,
    String? actorId,
    String? actorName,
    String? actorFotoUrl,
  }) async {
    if (!_available) return;
    await _usuarios.doc(userId).collection('notifications').add({
      'type': type,
      'title': title,
      'body': body,
      'data': data ?? {},
      'actorId': actorId,
      'actorName': actorName,
      'actorFotoUrl': actorFotoUrl ?? '',
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Stream de notificaciones del usuario.
  Stream<List<Map<String, dynamic>>> notificationsStream(String uid) {
    if (!_available) return Stream.value([]);
    return _usuarios
        .doc(uid)
        .collection('notifications')
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList())
        .handleError((_) => <Map<String, dynamic>>[]);
  }

  /// Stream de notificaciones filtrando las que provienen de usuarios bloqueados.
  Stream<List<Map<String, dynamic>>> notificationsStreamFiltrado(String uid) {
    if (!_available) return Stream.value([]);
    return getUsuariosBloqueados(uid)
        .asyncMap((bloqueados) {
          return _usuarios
              .doc(uid)
              .collection('notifications')
              .orderBy('createdAt', descending: true)
              .limit(50)
              .snapshots()
              .map(
                (s) =>
                    s.docs.map((d) => {'id': d.id, ...d.data()}).where((notif) {
                      final actorId = notif['actorId'] as String?;
                      if (actorId == null) return true;
                      return !bloqueados.contains(actorId);
                    }).toList(),
              );
        })
        .asyncExpand((s) => s);
  }

  /// Marca una notificaciÃ³n como leÃ­da.
  Future<void> markNotificationAsRead(String uid, String notificationId) async {
    if (!_available) return;
    await _usuarios
        .doc(uid)
        .collection('notifications')
        .doc(notificationId)
        .update({'read': true});
  }

  /// Marca todas las notificaciones como leÃ­das.
  Future<void> markAllNotificationsAsRead(String uid) async {
    if (!_available) return;
    final snapshot = await _usuarios
        .doc(uid)
        .collection('notifications')
        .where('read', isEqualTo: false)
        .get();
    if (snapshot.docs.isEmpty) {
      return; // No hay notificaciones sin leer, no crear batch vacÃ­o
    }
    final batch = _firestore!.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
  }

  // ââ Biblia: Subrayados y Notas ââââââââââââââââââââââââââââââââââââââââââââââ

  Future<void> syncBibleHighlight(
    String userId,
    BibleHighlight highlight,
  ) async {
    if (!_available) return;
    await _bibleHighlights(userId)
        .doc(highlight.id)
        .set(highlight.toFirestoreMap(), SetOptions(merge: true));
  }

  Future<List<BibleHighlight>> getBibleHighlightsForAnchors(
    String userId,
    List<BibleChapterAnchor> anchors,
  ) async {
    if (!_available) return [];
    final highlights = <BibleHighlight>[];
    for (final anchor in anchors) {
      final snapshot = await _bibleHighlights(userId)
          .where('version', isEqualTo: anchor.version)
          .where('bookId', isEqualTo: anchor.bookId)
          .where('chapter', isEqualTo: anchor.chapter)
          .get();

      highlights.addAll(
        snapshot.docs.map((doc) {
          return BibleHighlight.fromFirestoreMap(
            id: doc.id,
            userId: userId,
            map: doc.data(),
          );
        }),
      );
    }
    return highlights;
  }

  Future<void> deleteBibleHighlight(String userId, String highlightId) async {
    if (!_available) return;
    await _bibleHighlights(userId).doc(highlightId).delete();
  }

  Future<void> syncBibleNote(String userId, BibleNote note) async {
    if (!_available) return;
    await _bibleNotes(
      userId,
    ).doc(note.id).set(note.toFirestoreMap(), SetOptions(merge: true));
  }

  Future<List<BibleNote>> getBibleNotesForAnchors(
    String userId,
    List<BibleChapterAnchor> anchors,
  ) async {
    if (!_available) return [];
    final notes = <BibleNote>[];
    for (final anchor in anchors) {
      final snapshot = await _bibleNotes(userId)
          .where('version', isEqualTo: anchor.version)
          .where('bookId', isEqualTo: anchor.bookId)
          .where('chapter', isEqualTo: anchor.chapter)
          .get();

      notes.addAll(
        snapshot.docs.map((doc) {
          return BibleNote.fromFirestoreMap(
            id: doc.id,
            userId: userId,
            map: doc.data(),
          );
        }),
      );
    }
    return notes;
  }

  Future<void> deleteBibleNote(String userId, String noteId) async {
    if (!_available) return;
    await _bibleNotes(userId).doc(noteId).delete();
  }

  // ââ Peticiones de OraciÃ³n ââââââââââââââââââââââââââââââââââââââââââââââââ

  Stream<List<PeticionOracion>> peticionesStream() {
    if (!_available) return Stream.value([]);
    return _peticiones
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(prayerPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => PeticionOracion.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  /// Stream de peticiones filtrado por estado (respondida/pendiente).
  /// Si [respondida] es null, no filtra por estado.
  Stream<List<PeticionOracion>> peticionesStreamFiltrado({bool? respondida}) {
    if (!_available) return Stream.value([]);
    Query query = _peticiones
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(prayerPageSize);

    if (respondida != null) {
      query = query.where('respondida', isEqualTo: respondida);
    }

    return query.snapshots().map(
      (s) => s.docs
          .map(
            (d) => PeticionOracion.fromMap({
              'id': d.id,
              ...d.data() as Map<String, dynamic>,
            }),
          )
          .toList(),
    );
  }

  /// Stream de peticiones filtrado por estado (respondida/pendiente) con paginación por cursor.
  /// Si [respondida] es null, no filtra por estado.
  /// [lastDocument] es el último documento de la página anterior (opcional).
  /// Retorna una tupla con (items, lastDoc, hasMore).
  Stream<
    ({List<PeticionOracion> items, DocumentSnapshot? lastDoc, bool hasMore})
  >
  peticionesStreamFiltradoCursor({
    bool? respondida,
    DocumentSnapshot? lastDocument,
  }) {
    if (!_available) {
      return Stream.value((
        items: <PeticionOracion>[],
        lastDoc: null,
        hasMore: false,
      ));
    }
    Query query = _peticiones
        .where('oculto', isEqualTo: false)
        .orderBy('fecha', descending: true)
        .limit(prayerPageSize);

    if (respondida != null) {
      query = query.where('respondida', isEqualTo: respondida);
    }

    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }

    return query.snapshots().map((s) {
      final items = s.docs
          .map(
            (d) => PeticionOracion.fromMap({
              'id': d.id,
              ...d.data() as Map<String, dynamic>,
            }),
          )
          .toList();
      final newLastDoc = s.docs.isNotEmpty ? s.docs.last : null;
      final hasMore = s.docs.length >= prayerPageSize;
      return (items: items, lastDoc: newLastDoc, hasMore: hasMore);
    });
  }

  Future<void> crearPeticionOracion(PeticionOracion peticion) async {
    if (!_available) return;
    await _peticiones.add(peticion.toMap());
  }

  Future<void> apoyarPeticion(String peticionId) async {
    if (!_available) return;
    await _peticiones.doc(peticionId).update({
      'oracionesCount': FieldValue.increment(1),
    });
  }

  /// Marca una peticiÃ³n de oraciÃ³n como respondida.
  /// Solo el autor puede marcar su propia peticiÃ³n como respondida.
  Future<void> marcarPeticionComoRespondida(
    String peticionId,
    String userId,
  ) async {
    if (!_available) return;
    final docRef = _peticiones.doc(peticionId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final data = doc.data()!;
    if (data['userId'] != userId) {
      throw StateError(
        'Solo el autor puede marcar la peticiÃ³n como respondida',
      );
    }

    await docRef.update({
      'respondida': true,
      'fechaRespondida': FieldValue.serverTimestamp(),
    });
  }

  // ââ Feedback âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Future<void> sendFeedback({
    required String userId,
    required String userName,
    required String mensaje,
    int calificacion = 0,
  }) async {
    if (!_available) return;
    await _firestore!.collection('feedback').add({
      'userId': userId,
      'userName': userName,
      'mensaje': mensaje,
      'calificacion': calificacion,
      'fecha': FieldValue.serverTimestamp(),
      'appVersion': '1.0.0',
    });
  }

  // ââ Notas generales ââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Future<void> syncNote(String userId, Note note) async {
    if (!_available) return;
    await _usuarios
        .doc(userId)
        .collection('notes')
        .doc(note.id)
        .set(note.toMap(), SetOptions(merge: true));
  }

  Future<void> deleteNoteFromFirestore(String userId, String noteId) async {
    if (!_available) return;
    await _usuarios.doc(userId).collection('notes').doc(noteId).delete();
  }

  // ââ Chat âââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââââ

  Stream<List<Message>> getMessages(String chatId) {
    if (!_available) return Stream.value([]);
    return _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(messagesPageSize)
        .snapshots()
        .map(
          (s) => s.docs
              .map((d) => Message.fromMap({'id': d.id, ...d.data()}))
              .toList(),
        );
  }

  /// Stream de mensajes con paginación por cursor.
  /// [lastDocument] es el último documento de la página anterior (opcional).
  Stream<List<Message>> getMessagesCursor(
    String chatId, {
    DocumentSnapshot? lastDocument,
  }) {
    if (!_available) return Stream.value([]);
    Query query = _chats
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(messagesPageSize);
    if (lastDocument != null) {
      query = query.startAfterDocument(lastDocument);
    }
    return query.snapshots().map(
      (s) => s.docs
          .map((d) {
            final data = d.data() as Map<String, dynamic>?;
            if (data == null) return null;
            return Message.fromMap({'id': d.id, ...data});
          })
          .whereType<Message>()
          .toList(),
    );
  }

  /// Envía un mensaje al chat [chatId].
  ///
  /// `participantIds`/`participantNames` son SOLO para crear el chat; en un
  /// chat existente se ignoran (solo se actualizan los metadatos). Si no se
  /// pasan, se asume que el chat ya existe y no se hace ninguna lectura extra.
  Future<void> sendMessage(
    String chatId,
    String senderId,
    String text, {
    List<String>? participantIds,
    Map<String, String>? participantNames,
  }) async {
    if (!_available) {
      throw StateError('sendMessage: Firestore no estÃ¡ disponible');
    }
    final chatRef = _chats.doc(chatId);
    final metadata = <String, dynamic>{
      'lastUpdate': FieldValue.serverTimestamp(),
      'lastMessage': text,
      'lastSenderId': senderId,
    };

    if (participantIds == null && participantNames == null) {
      // Camino caliente: chat existente (la UI solo abre chats ya creados).
      // Sin `get()`: 0 lecturas y ninguna posibilidad de reescribir quiÃ©nes
      // participan.
      await chatRef.update(metadata);
    } else {
      if (participantIds == null || participantIds.length != 2) {
        throw StateError(
          'sendMessage: participantIds con exactamente 2 miembros es obligatorio para crear el chat $chatId',
        );
      }
      // El documento del chat debe existir ANTES del mensaje (las reglas leen
      // participantIds del padre para autorizar la escritura en /messages).
      var exists = false;
      try {
        exists = (await chatRef.get()).exists;
      } on FirebaseException catch (e) {
        // Las reglas actuales (`allow read: if isParticipant(resource.data)`)
        // devuelven permission-denied cuando el documento aÃºn no existe
        // (resource == null). Se interpreta como "no existe": si el chat
        // existiera y el llamador no fuera participante, el `set` de abajo
        // tambiÃ©n serÃ­a denegado por la regla de create.
        if (e.code != 'permission-denied') rethrow;
        exists = false;
      }
      if (exists) {
        // Chat existente: solo metadatos. participantIds/participantNames se
        // ignoran a propÃ³sito (era el bug de T-014: se reescribÃ­an).
        await chatRef.update(metadata);
      } else {
        await chatRef.set({
          ...metadata,
          'participantIds': participantIds,
          if (participantNames != null) 'participantNames': participantNames,
        });
      }
    }

    await chatRef.collection('messages').add({
      'senderId': senderId,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<Map<String, dynamic>>> getUserChats(String userId) {
    if (!_available) return Stream.value([]);
    return _chats
        .where('participantIds', arrayContains: userId)
        .orderBy('lastUpdate', descending: true)
        .limit(chatsPageSize)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  /// Stream de chats filtrando usuarios bloqueados (excluye chats donde
  /// el otro participante estÃ¡ bloqueado por [userId]).
  Stream<List<Map<String, dynamic>>> getUserChatsFiltrados(String userId) {
    if (!_available) return Stream.value([]);
    return getUsuariosBloqueados(userId)
        .asyncMap((bloqueados) {
          return _chats
              .where('participantIds', arrayContains: userId)
              .orderBy('lastUpdate', descending: true)
              .limit(chatsPageSize)
              .snapshots()
              .map(
                (s) => s.docs.map((d) => {'id': d.id, ...d.data()}).where((
                  chat,
                ) {
                  final participants = List<String>.from(
                    chat['participantIds'] ?? [],
                  );
                  // Solo ocultar si TODOS los otros participantes estan bloqueados
                  // (chat de 2 personas donde el otro esta bloqueado)
                  final otros = participants.where((p) => p != userId).toList();
                  if (otros.isEmpty) return false;
                  // En chats de 2, ocultar si el otro esta bloqueado
                  if (otros.length == 1) {
                    return !bloqueados.contains(otros.first);
                  }
                  // En chats grupales, mostrar siempre
                  return true;
                }).toList(),
              );
        })
        .asyncExpand((s) => s);
  }
  // ââ Bloqueos de usuarios âââââââââââââââââââââââââââââââââââââââââââââââââââ

  /// Bloquea a [blockedUid] desde la perspectiva de [uid].
  /// Guarda el documento en `usuarios/{uid}/blocked/{blockedUid}`.
  Future<void> bloquearUsuario(String uid, String blockedUid) async {
    if (!_available) return;
    if (uid == blockedUid) return;
    await _usuarios
        .doc(uid)
        .collection('blocked')
        .doc(blockedUid)
        .set(
          Bloqueo(
            uid: uid,
            blockedUid: blockedUid,
            fecha: DateTime.now(),
          ).toMap(),
          SetOptions(merge: true),
        );
  }

  /// Desbloquea a [blockedUid] para [uid].
  Future<void> desbloquearUsuario(String uid, String blockedUid) async {
    if (!_available) return;
    await _usuarios.doc(uid).collection('blocked').doc(blockedUid).delete();
  }

  /// Stream de uids bloqueados por [uid].
  Stream<List<String>> getUsuariosBloqueados(String uid) {
    if (!_available) return Stream.value([]);
    return _usuarios
        .doc(uid)
        .collection('blocked')
        .limit(100)
        .snapshots()
        .map((s) => s.docs.map((d) => d.id).toList());
  }
}
