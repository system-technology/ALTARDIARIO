import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:altar_diario/data/services/firestore_service.dart';
import 'package:altar_diario/presentation/providers/app_providers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Repositorio para la feature de oración.
/// Encapsula el acceso a FirestoreService para peticiones de oración
/// y aplica los filtros de oculto y usuarios bloqueados.
class OracionRepository {
  OracionRepository(this._firestore);

  final FirestoreService _firestore;

  /// Stream de todas las peticiones de oración filtradas (oculto + bloqueados).
  /// Requiere [uid] para filtrar usuarios bloqueados.
  /// Lanza [ArgumentError] si [uid] es nulo o vacío.
  Stream<List<PeticionOracion>> peticionesStream({required String uid}) {
    if (uid.isEmpty) {
      throw ArgumentError(
        'uid es obligatorio para filtrar usuarios bloqueados',
      );
    }
    if (_firestore.firestore == null) return Stream.value([]);

    // Stream de UIDs bloqueados por el usuario actual
    final blockedStream = _firestore.getUsuariosBloqueados(uid);

    // Stream de peticiones desde Firestore (ya filtra oculto == false a nivel de query)
    final peticionesStream = _firestore.peticionesStream();

    // Combinar ambos streams y filtrar en el repositorio
    return blockedStream.asyncMap((blockedUids) {
      final blockedSet = blockedUids.toSet();
      return peticionesStream.map((peticiones) {
        return peticiones.where((p) {
          final isBlocked = blockedSet.contains(p.userId);
          // Filtrado defensivo: aunque Firestore ya filtra oculto == false,
          // aplicamos el filtro aquí también por seguridad
          final isHidden = p.oculto == true;
          return !isBlocked && !isHidden;
        }).toList();
      });
    }).asyncExpand((s) => s);
  }

  /// Stream de peticiones filtradas por estado (respondida/pendiente)
  /// y filtradas por oculto + usuarios bloqueados.
  /// Requiere [uid] para filtrar usuarios bloqueados.
  /// Lanza [ArgumentError] si [uid] es nulo o vacío.
  Stream<List<PeticionOracion>> peticionesStreamFiltrado({
    required String uid,
    bool? respondida,
  }) {
    if (uid.isEmpty) {
      throw ArgumentError(
        'uid es obligatorio para filtrar usuarios bloqueados',
      );
    }
    if (_firestore.firestore == null) return Stream.value([]);

    // Stream de UIDs bloqueados por el usuario actual
    final blockedStream = _firestore.getUsuariosBloqueados(uid);

    // Stream de peticiones desde Firestore con filtro opcional por respondida
    // (FirestoreService ya filtra oculto == false a nivel de query)
    final peticionesStream = _firestore.peticionesStreamFiltrado(
      respondida: respondida,
    );

    // Combinar ambos streams y filtrar en el repositorio
    return blockedStream.asyncMap((blockedUids) {
      final blockedSet = blockedUids.toSet();
      return peticionesStream.map((peticiones) {
        return peticiones.where((p) {
          final isBlocked = blockedSet.contains(p.userId);
          // Filtrado defensivo: aunque Firestore ya filtra oculto == false,
          // aplicamos el filtro aquí también por seguridad
          final isHidden = p.oculto == true;
          return !isBlocked && !isHidden;
        }).toList();
      });
    }).asyncExpand((s) => s);
  }

  /// Stream de peticiones filtradas por estado (respondida/pendiente) con paginación por cursor
  /// y filtradas por oculto + usuarios bloqueados.
  /// Requiere [uid] para filtrar usuarios bloqueados.
  /// Lanza [ArgumentError] si [uid] es nulo o vacío.
  Stream<
      ({
        List<PeticionOracion> items,
        DocumentSnapshot? lastDoc,
        bool hasMore
      })> peticionesStreamFiltradoCursor({
    required String uid,
    bool? respondida,
    DocumentSnapshot? lastDocument,
  }) {
    if (uid.isEmpty) {
      throw ArgumentError(
        'uid es obligatorio para filtrar usuarios bloqueados',
      );
    }
    if (_firestore.firestore == null) {
      return Stream.value((
        items: <PeticionOracion>[],
        lastDoc: null,
        hasMore: false,
      ));
    }

    // Stream de UIDs bloqueados por el usuario actual
    final blockedStream = _firestore.getUsuariosBloqueados(uid);

    // Stream de peticiones desde Firestore con filtro opcional por respondida y cursor
    final peticionesStream = _firestore.peticionesStreamFiltradoCursor(
      respondida: respondida,
      lastDocument: lastDocument,
    );

    // Combinar ambos streams y filtrar en el repositorio
    return blockedStream.asyncMap((blockedUids) {
      final blockedSet = blockedUids.toSet();
      return peticionesStream.map((page) {
        final filteredItems = page.items.where((p) {
          final isBlocked = blockedSet.contains(p.userId);
          final isHidden = p.oculto == true;
          return !isBlocked && !isHidden;
        }).toList();
        // hasMore se ajusta: si el filtrado local reduce items, puede que haya más
        // pero no lo sabemos sin hacer otra query. Mantenemos hasMore del servicio
        // y añadimos una heurística: si items filtrados < prayerPageSize pero hasMore
        // del servicio es true, podríamos tener más.
        return (
          items: filteredItems,
          lastDoc: page.lastDoc,
          hasMore: page.hasMore,
        );
      });
    }).asyncExpand((s) => s);
  }

  /// Stream de peticiones donde el usuario actual hizo "Amén" (está en apoyadosPor).
  /// Filtrado por oculto + usuarios bloqueados.
  /// Requiere [uid] para filtrar usuarios bloqueados.
  /// Lanza [ArgumentError] si [uid] es nulo o vacío.
  Stream<List<PeticionOracion>> peticionesStreamDondeOro({
    required String uid,
  }) {
    if (uid.isEmpty) {
      throw ArgumentError(
        'uid es obligatorio para filtrar usuarios bloqueados',
      );
    }
    if (_firestore.firestore == null) return Stream.value([]);

    // Stream de UIDs bloqueados por el usuario actual
    final blockedStream = _firestore.getUsuariosBloqueados(uid);

    // Stream de peticiones desde Firestore (ya filtra oculto == false y apoyadosPor)
    final peticionesStream = _firestore.peticionesStreamDondeOro(uid);

    // Combinar ambos streams y filtrar en el repositorio
    return blockedStream.asyncMap((blockedUids) {
      final blockedSet = blockedUids.toSet();
      return peticionesStream.map((peticiones) {
        return peticiones.where((p) {
          final isBlocked = blockedSet.contains(p.userId);
          // Filtrado defensivo: aunque Firestore ya filtra oculto == false,
          // aplicamos el filtro aquí también por seguridad
          final isHidden = p.oculto == true;
          return !isBlocked && !isHidden;
        }).toList();
      });
    }).asyncExpand((s) => s);
  }

  /// Stream de peticiones donde el usuario actual hizo "Amén" con paginación por cursor.
  /// Filtrado por oculto + usuarios bloqueados.
  /// Requiere [uid] para filtrar usuarios bloqueados.
  /// Lanza [ArgumentError] si [uid] es nulo o vacío.
  Stream<
      ({
        List<PeticionOracion> items,
        DocumentSnapshot? lastDoc,
        bool hasMore
      })> peticionesStreamDondeOroCursor({
    required String uid,
    DocumentSnapshot? lastDocument,
  }) {
    if (uid.isEmpty) {
      throw ArgumentError(
        'uid es obligatorio para filtrar usuarios bloqueados',
      );
    }
    if (_firestore.firestore == null) {
      return Stream.value((
        items: <PeticionOracion>[],
        lastDoc: null,
        hasMore: false,
      ));
    }

    // Stream de UIDs bloqueados por el usuario actual
    final blockedStream = _firestore.getUsuariosBloqueados(uid);

    // Stream de peticiones desde Firestore con cursor
    final peticionesStream = _firestore.peticionesStreamDondeOroCursor(
      uid: uid,
      lastDocument: lastDocument,
    );

    // Combinar ambos streams y filtrar en el repositorio
    return blockedStream.asyncMap((blockedUids) {
      final blockedSet = blockedUids.toSet();
      return peticionesStream.map((page) {
        final filteredItems = page.items.where((p) {
          final isBlocked = blockedSet.contains(p.userId);
          final isHidden = p.oculto == true;
          return !isBlocked && !isHidden;
        }).toList();
        return (
          items: filteredItems,
          lastDoc: page.lastDoc,
          hasMore: page.hasMore,
        );
      });
    }).asyncExpand((s) => s);
  }

  /// Crea una nueva petición de oración.
  Future<void> crearPeticionOracion(PeticionOracion peticion) {
    return _firestore.crearPeticionOracion(peticion);
  }

  /// Marca una petición como respondida (solo el autor).
  Future<void> marcarPeticionComoRespondida(String peticionId, String uid) {
    return _firestore.marcarPeticionComoRespondida(peticionId, uid);
  }

  /// Apoya una petición (incrementa oracionesCount y añade UID a apoyadosPor).
  Future<void> apoyarPeticion(String peticionId, String userId) {
    return _firestore.apoyarPeticion(peticionId, userId);
  }
}

/// Provider del repositorio de oración.
final oracionRepositoryProvider = Provider<OracionRepository>((ref) {
  return OracionRepository(ref.watch(firestoreServiceProvider));
});
