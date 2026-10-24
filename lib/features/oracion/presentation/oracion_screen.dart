import 'package:altar_diario/core/services/community_policy_service.dart';
import 'package:altar_diario/core/services/gamification_service.dart';
import 'package:altar_diario/core/theme/app_theme.dart';
import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:altar_diario/features/oracion/presentation/widgets/peticion_card.dart'
    show PeticionCard;
import 'package:altar_diario/features/oracion/providers/oracion_providers.dart'
    show peticionesFiltroProvider, peticionesFiltradasProvider;
import 'package:altar_diario/presentation/providers/app_providers.dart'
    show
        effectiveUserUidProvider,
        storageProvider,
        userProfileProvider,
        isGuestUserProvider,
        oracionRepositoryProvider,
        firestoreServiceProvider;
import 'package:altar_diario/presentation/widgets/estados/index.dart';
import 'package:altar_diario/presentation/widgets/guest_access_restricted_widget.dart'
    show GuestAccessRestrictedWidget;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pantalla principal de la feature de oración (migrada a lib/features/oracion/).
/// Mantiene la misma funcionalidad que la OracionScreen original pero usando
/// los providers de la feature y delegando el card a PeticionCard widget.
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
            Text(
              'Pedir Oración',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
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
            child: const Text(
              'Cancelar',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            onPressed: () async {
              final motivo = controller.text.trim();
              if (motivo.isEmpty) return;

              final policyCheck = CommunityPolicyService.validarContenido(
                motivo,
              );
              if (!policyCheck.isApproved) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      policyCheck.reason ??
                          'La petición no cumple las normas comunitarias.',
                    ),
                    backgroundColor: Colors.redAccent,
                  ),
                );
                return;
              }

              final uid = ref.read(effectiveUserUidProvider) ?? 'anonimo';
              final firestoreService = ref.read(firestoreServiceProvider);
              final oracionRepo = ref.read(oracionRepositoryProvider);
              final storage = ref.read(storageProvider);
              final user = ref.read(userProfileProvider).asData?.value;

              final userName = (user?.nombre.isNotEmpty == true)
                  ? user!.nombre
                  : (storage.getUserName() ?? 'Invitado');

              final nuevaPeticion = PeticionOracion(
                id: '',
                userId: uid,
                userName: userName,
                motivo: controller.text.trim(),
                fecha: DateTime.now(),
              );

              await oracionRepo.crearPeticionOracion(nuevaPeticion);

              final newBadges =
                  await GamificationService.evaluarYNotificarBadges(
                user: user,
                firestore: firestoreService,
                storage: storage,
                extraStats: {'peticionesPublicadas': 1},
              );

              if (context.mounted) {
                Navigator.pop(context);
                if (newBadges.isNotEmpty) {
                  GamificationService.showBadgeUnlockedDialog(
                    context,
                    newBadges,
                    firestore: firestoreService,
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
              const Icon(
                Icons.local_fire_department,
                color: AppTheme.primaryBlue,
                size: 22,
              ),
              const SizedBox(width: 8),
              Text(
                'AltarDiario',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primaryBlue,
                      fontSize: 20,
                    ),
              ),
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
            const Icon(
              Icons.local_fire_department,
              color: AppTheme.primaryBlue,
              size: 22,
            ),
            const SizedBox(width: 8),
            Text(
              'AltarDiario',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppTheme.primaryBlue,
                    fontSize: 20,
                  ),
            ),
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
              const PopupMenuItem(value: null, child: Text('Todas')),
              const PopupMenuItem(value: false, child: Text('Pendientes')),
              const PopupMenuItem(value: true, child: Text('Respondidas')),
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
                Icon(
                  Icons.front_hand,
                  size: 18,
                  color: AppTheme.primaryBlueLight,
                ),
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
            child: AsyncStateBuilder<PeticionOracion>(
              isLoading: peticionesAsync.isLoading,
              error: peticionesAsync.error,
              items: peticionesAsync.value,
              onRetry: () => ref.refresh(peticionesFiltradasProvider.future),
              emptyTitle: 'No hay peticiones activas.',
              emptyDescription: '¡Sé el primero en pedir apoyo!',
              builder: (context, peticiones) => RefreshIndicator(
                onRefresh: () =>
                    ref.refresh(peticionesFiltradasProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: peticiones.length,
                  itemBuilder: (context, index) =>
                      PeticionCard(peticion: peticiones[index]),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'oracion_fab',
        onPressed: () => _abrirDialogoNuevaPeticion(context, ref),
        label: const Text('Pedir Oración'),
        icon: const Icon(Icons.add),
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }
}
