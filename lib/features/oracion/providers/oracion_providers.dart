import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../presentation/providers/app_providers.dart';

/// Notifier para el filtro de peticiones (todas/respondidas/pendientes).
class PeticionesFiltroNotifier extends Notifier<bool?> {
  @override
  bool? build() => null;

  void setFiltro(bool? value) => state = value;
}

/// Filtro actual para las peticiones (null = todas, true = respondidas, false = pendientes).
final peticionesFiltroProvider =
    NotifierProvider<PeticionesFiltroNotifier, bool?>(
  PeticionesFiltroNotifier.new,
);

/// Stream de todas las peticiones de oración (filtrado: sin bloqueados ni ocultos).
/// El filtrado se hace en OracionRepository.
final peticionesStreamProvider = StreamProvider<List<PeticionOracion>>((ref) {
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return Stream.value([]);
  return ref.watch(oracionRepositoryProvider).peticionesStream(uid: uid);
});

/// Stream de peticiones filtradas por estado (respondida/pendiente) y sin bloqueados/ocultos.
/// El filtrado se hace en OracionRepository.
final peticionesFiltradasProvider = StreamProvider<List<PeticionOracion>>((
  ref,
) {
  final filtro = ref.watch(peticionesFiltroProvider);
  final uid = ref.watch(effectiveUserUidProvider);
  if (uid == null) return Stream.value([]);
  return ref
      .watch(oracionRepositoryProvider)
      .peticionesStreamFiltrado(uid: uid, respondida: filtro);
});

/// Stream de peticiones filtradas por estado con paginación por cursor.
/// Acepta un parámetro family con (uid, filtro, lastDocument).
/// El filtrado se hace en OracionRepository.
final peticionesFiltradasCursorProvider = StreamProvider.family<
    ({List<PeticionOracion> items, DocumentSnapshot? lastDoc, bool hasMore}),
    ({
      String uid,
      bool? respondida,
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
  return ref.watch(oracionRepositoryProvider).peticionesStreamFiltradoCursor(
        uid: uid,
        respondida: params.respondida,
        lastDocument: params.lastDocument,
      );
});
