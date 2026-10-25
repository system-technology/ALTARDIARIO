import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../features/moderation/presentation/report_content_dialog.dart';
import '../../core/services/community_policy_service.dart';
import '../../core/services/gamification_service.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/peticion_oracion.dart';
import '../providers/app_providers.dart';
import '../widgets/guest_access_restricted_widget.dart';
import '../widgets/shimmer_loading_widget.dart';

class OracionScreen extends ConsumerWidget {
  const OracionScreen({super.key});

  void _abrirDialogoNuevaPeticion(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 20, color: AppTheme.primaryBlue),
            SizedBox(width: 8),
            Text('Pedir Oración',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CommunityPolicyService.buildPolicyBanner(context),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: '¿Por qué podemos orar por ti?',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: AppTheme.pendingGray,
              ),
            ),
          ],
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar',
                style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
            onPressed: () async {
              final motivo = controller.text.trim();
              if (motivo.isEmpty) return;

              final policyCheck =
                  CommunityPolicyService.validarContenido(motivo);
              if (!policyCheck.isApproved) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(policyCheck.reason ??
                        'La petición no cumple las normas comunitarias.'),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              final uid = ref.read(effectiveUserUidProvider) ?? 'anonimo';
              final firestore = ref.read(firestoreServiceProvider);
              final storage = ref.read(storageProvider);
              final user = ref.read(userProfileProvider).asData?.value;
              final firebaseUser = ref.read(authServiceProvider).currentUser;

              final userName = (user?.nombre.isNotEmpty == true)
                  ? user!.nombre
                  : (storage.getUserName() ??
                      firebaseUser?.displayName ??
                      'Invitado');

              final nuevaPeticion = PeticionOracion(
                id: '',
                userId: uid,
                userName: userName,
                motivo: controller.text.trim(),
                fecha: DateTime.now(),
              );

              await firestore.crearPeticionOracion(nuevaPeticion);

              final newBadges =
                  await GamificationService.evaluarYNotificarBadges(
                user: user,
                firestore: firestore,
                storage: storage,
                extraStats: {'peticionesPublicadas': 1},
              );

              if (context.mounted) {
                Navigator.pop(context);
                if (newBadges.isNotEmpty) {
                  GamificationService.showBadgeUnlockedDialog(
                    context,
                    newBadges,
                    firestore: firestore,
                    storage: storage,
                    user: user,
                  );
                }
              }
            },
            child: const Text('Compartir'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGuest = ref.watch(isGuestUserProvider);

    if (isGuest) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.textPrimary,
          elevation: 0,
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.local_fire_department,
                  color: AppTheme.primaryBlue, size: 22),
              const SizedBox(width: 8),
              Text('AltarDiario',
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(color: AppTheme.primaryBlue, fontSize: 20)),
            ],
          ),
        ),
        body: const GuestAccessRestrictedWidget(
          title: 'Compañeros de Oración Reservado',
          description:
              'Para proteger la privacidad y evitar cuentas falsas, la consulta y envío de peticiones de oración comunitarias están reservadas para miembros registrados con su cuenta de Google.',
        ),
      );
    }

    final filtro = ref.watch(peticionesFiltroProvider);
    final peticionesAsync = ref.watch(peticionesFiltradasProvider);

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.local_fire_department,
                color: AppTheme.primaryBlue, size: 22),
            const SizedBox(width: 8),
            Text('AltarDiario',
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: AppTheme.primaryBlue, fontSize: 20)),
          ],
        ),
        actions: [
          PopupMenuButton<bool?>(
            initialValue: filtro,
            tooltip: 'Filtrar peticiones',
            icon: const Icon(Icons.filter_list, color: AppTheme.textPrimary),
            onSelected: (value) =>
                ref.read(peticionesFiltroProvider.notifier).setFiltro(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('Todas'),
              ),
              const PopupMenuItem(
                value: false,
                child: Text('Pendientes'),
              ),
              const PopupMenuItem(
                value: true,
                child: Text('Respondidas'),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(Icons.front_hand,
                    size: 18, color: AppTheme.primaryBlueLight),
                SizedBox(width: 6),
                Text(
                  'COMPAÑEROS DE ORACIÓN',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.primaryBlueLight,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: peticionesAsync.when(
              data: (peticiones) => peticiones.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      onRefresh: () =>
                          ref.refresh(peticionesStreamProvider.future),
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: peticiones.length,
                        itemBuilder: (context, index) =>
                            _PeticionCard(peticion: peticiones[index]),
                      ),
                    ),
              loading: () => const ShimmerListLoading(itemCount: 4),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: () => _abrirDialogoNuevaPeticion(context, ref),
        label: const Text('Pedir Oración'),
        icon: const Icon(Icons.add),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.accentGoldLight.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome,
                  size: 40, color: AppTheme.accentGold),
            ),
            const SizedBox(height: 20),
            const Text(
              'No hay peticiones activas.',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),
            const Text(
              '¡Sé el primero en pedir apoyo!',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeticionCard extends ConsumerWidget {
  final PeticionOracion peticion;
  const _PeticionCard({required this.peticion});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authorProfile =
        ref.watch(userProfileByIdProvider(peticion.userId)).value;
    final authorName = (authorProfile?.nombre.isNotEmpty == true)
        ? authorProfile!.displayName
        : peticion.userName;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        boxShadow: AppTheme.softShadow,
        border:
            Border.all(color: AppTheme.pendingGrayDark.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.accentGold.withValues(alpha: 0.15),
                child: Text(
                  authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
                  style: const TextStyle(
                      color: AppTheme.accentGold, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(authorName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppTheme.primaryBlue)),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('dd MMM, HH:mm').format(peticion.fecha),
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.pendingGray,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              peticion.motivo,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
          const Divider(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_outline,
                      size: 14, color: AppTheme.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    '${peticion.oracionesCount} orando',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.textSecondary),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => ReportContentDialog(
                      targetType: 'peticion',
                      targetId: peticion.id,
                      targetTitle: peticion.motivo.length > 50
                          ? '${peticion.motivo.substring(0, 50)}...'
                          : peticion.motivo,
                      targetAuthor: authorName,
                    ),
                  );
                },
                icon: const Icon(Icons.flag_outlined,
                    size: 20, color: Colors.grey),
                tooltip: 'Reportar',
              ),
              const SizedBox(width: 8),
              // Botón "Marcar como respondida" solo para el autor y si no está respondida
              if (!peticion.respondida)
                _buildMarcarRespondidaButton(ref, context, peticion),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  HapticFeedback.mediumImpact();
                  ref.read(firestoreServiceProvider).apoyarPeticion(
                      peticion.id, ref.read(effectiveUserUidProvider)!);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Has dicho: ¡Amén! 🙏'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon:
                    const Icon(Icons.front_hand, size: 16, color: Colors.white),
                label: const Text('AMÉN',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 12)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryBlue,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  elevation: 0,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Método para construir el botón "Marcar como respondida"
  Widget _buildMarcarRespondidaButton(
      WidgetRef ref, BuildContext context, PeticionOracion peticion) {
    final currentUid = ref.read(effectiveUserUidProvider);
    final isAutor = currentUid == peticion.userId;

    if (!isAutor) return const SizedBox.shrink();

    return TextButton.icon(
      onPressed: () async {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Marcar como respondida'),
            content: const Text('¿Marcar esta petición como respondida?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Marcar'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          try {
            await ref
                .read(firestoreServiceProvider)
                .marcarPeticionComoRespondida(
                  peticion.id,
                  ref.read(effectiveUserUidProvider)!,
                );
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Petición marcada como respondida ✨')),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Error: $e')),
              );
            }
          }
        }
      },
      icon: const Icon(Icons.check_circle_outline,
          size: 18, color: AppTheme.accentGold),
      label: const Text('Respondida', style: TextStyle(fontSize: 12)),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.accentGold,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }
}
