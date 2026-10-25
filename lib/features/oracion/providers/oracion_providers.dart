import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../presentation/providers/app_providers.dart';

/// Enum para el filtro de peticiones.
enum PeticionesFiltro { todas, pendientes, respondidas, misOraciones }

/// Notifier para el filtro de peticiones.
class PeticionesFiltroNotifier extends Notifier<PeticionesFiltro> {
  @override
  PeticionesFiltro build() => PeticionesFiltro.todas;

  void setFiltro(PeticionesFiltro value) => state = value;
}

/// Filtro actual para las peticiones.
final peticionesFiltroProvider =
    NotifierProvider<PeticionesFiltroNotifier, PeticionesFiltro>(
  PeticionesFiltroNotifier.new,
);

/// Stream de todas las peticiones de oración (filtrado: sin bloqueados ni ocultos).
/// El filtrado se hace en OracionRepository.
final peticionesStreamProvider = StreamProvider<List<PeticionOracion>>((ref) {
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return Stream.value([]);
  return ref.watch(oracionRepositoryProvider).peticionesStream(uid: uid);
});

/// Stream de peticiones donde el usuario actual hizo "Amén" (filtrado: sin bloqueados ni ocultos).
/// El filtrado se hace en OracionRepository.
final peticionesDondeOroProvider = StreamProvider<List<PeticionOracion>>((ref) {
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return Stream.value([]);
  return ref
      .watch(oracionRepositoryProvider)
      .peticionesStreamDondeOro(uid: uid);
});

/// Stream de peticiones filtradas por estado (respondida/pendiente) y sin bloqueados/ocultos.
/// El filtrado se hace en OracionRepository.
final peticionesFiltradasProvider = StreamProvider<List<PeticionOracion>>((
  ref,
) {
  final filtro = ref.watch(peticionesFiltroProvider);
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return Stream.value([]);

  switch (filtro) {
    case PeticionesFiltro.todas:
      return ref.watch(oracionRepositoryProvider).peticionesStream(uid: uid);
    case PeticionesFiltro.pendientes:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamFiltrado(uid: uid, respondida: false);
    case PeticionesFiltro.respondidas:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamFiltrado(uid: uid, respondida: true);
    case PeticionesFiltro.misOraciones:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamDondeOro(uid: uid);
  }
});

/// Stream de peticiones filtradas por estado con paginación por cursor.
/// Acepta un parámetro family con (uid, filtro, lastDocument).
/// El filtrado se hace en OracionRepository.
final peticionesFiltradasCursorProvider = StreamProvider.family<
    ({List<PeticionOracion> items, DocumentSnapshot? lastDoc, bool hasMore}),
    ({
      String uid,
      PeticionesFiltro filtro,
      DocumentSnapshot? lastDocument
    })>((ref, params) {
  final uid = params.uid;
  if (uid.isEmpty) {
    return Stream.value((
      items: <PeticionOracion>[],
      lastDoc: null,
      hasMore: false,
    ));
  }

  switch (params.filtro) {
    case PeticionesFiltro.todas:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamFiltradoCursor(
            uid: uid,
            respondida: null,
            lastDocument: params.lastDocument,
          );
    case PeticionesFiltro.pendientes:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamFiltradoCursor(
            uid: uid,
            respondida: false,
            lastDocument: params.lastDocument,
          );
    case PeticionesFiltro.respondidas:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamFiltradoCursor(
            uid: uid,
            respondida: true,
            lastDocument: params.lastDocument,
          );
    case PeticionesFiltro.misOraciones:
      return ref
          .watch(oracionRepositoryProvider)
          .peticionesStreamDondeOroCursor(
            uid: uid,
            lastDocument: params.lastDocument,
          );
  }
});
