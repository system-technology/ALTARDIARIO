import 'package:cloud_firestore/cloud_firestore.dart';

class PeticionOracion {
  final String id;
  final String userId;
  final String userName;
  final String motivo;
  final DateTime fecha;
  final int oracionesCount;
  final bool respondida;
  final DateTime? fechaRespondida;
  final bool oculto;
  final List<String> apoyadosPor;

  PeticionOracion({
    required this.id,
    required this.userId,
    required this.userName,
    required this.motivo,
    required this.fecha,
    this.oracionesCount = 0,
    this.respondida = false,
    this.fechaRespondida,
    this.oculto = false,
    this.apoyadosPor = const [],
  });

  factory PeticionOracion.fromFirestore(DocumentSnapshot doc) {
    final Map data = doc.data() as Map<String, dynamic>;
    return PeticionOracion(
      id: doc.id,
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anónimo',
      motivo: data['motivo'] ?? '',
      fecha: (data['fecha'] as Timestamp).toDate(),
      oracionesCount: data['oracionesCount'] ?? 0,
      respondida: data['respondida'] ?? false,
      fechaRespondida: data['fechaRespondida'] != null
          ? (data['fechaRespondida'] as Timestamp).toDate()
          : null,
      oculto: data['oculto'] ?? false,
      apoyadosPor: List<String>.from(data['apoyadosPor'] ?? []),
    );
  }

  factory PeticionOracion.fromMap(Map<String, dynamic> data) {
    return PeticionOracion(
      id: data['id'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Anónimo',
      motivo: data['motivo'] ?? '',
      fecha: data['fecha'] != null
          ? (data['fecha'] as Timestamp).toDate()
          : DateTime.now(),
      oracionesCount: data['oracionesCount'] ?? 0,
      respondida: data['respondida'] ?? false,
      fechaRespondida: data['fechaRespondida'] != null
          ? (data['fechaRespondida'] as Timestamp).toDate()
          : null,
      oculto: data['oculto'] ?? false,
      apoyadosPor: List<String>.from(data['apoyadosPor'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'motivo': motivo,
      'fecha': Timestamp.fromDate(fecha),
      'oracionesCount': oracionesCount,
      'respondida': respondida,
      'fechaRespondida':
          fechaRespondida != null ? Timestamp.fromDate(fechaRespondida!) : null,
      'oculto': oculto,
      'apoyadosPor': apoyadosPor,
    };
  }
}
