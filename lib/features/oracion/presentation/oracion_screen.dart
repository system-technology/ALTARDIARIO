import 'package:altar_diario/core/services/community_policy_service.dart';
import 'package:altar_diario/core/services/gamification_service.dart';
import 'package:altar_diario/core/theme/app_theme.dart';
import 'package:altar_diario/data/models/peticion_oracion.dart';
import 'package:altar_diario/features/oracion/presentation/widgets/peticion_card.dart'
    show PeticionCard;
import 'package:altar_diario/features/oracion/providers/oracion_providers.dart'
    show
        PeticionesFiltro,
        peticionesFiltroProvider,
        peticionesFiltradasProvider,
        peticionesFiltradasCursorProvider;
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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pantalla principal de la feature de oración (migrada a lib/features/oracion/).
/// Mantiene la misma funcionalidad que la OracionScreen original pero usando
/// los providers de la feature y delegando el card a PeticionCard widget.
/// Implementa paginación por cursor con infinite scroll.
class OracionScreen extends ConsumerStatefulWidget {
  const OracionScreen({super.key});

  @override
  ConsumerState<OracionScreen> createState() => _OracionScreenState();
}

class _OracionScreenState extends ConsumerState<OracionScreen> {
  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  final List<PeticionOracion> _allPeticiones = [];
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    final filtro = ref.read(peticionesFiltroProvider);
    final uid = ref.read(effectiveUserUidProvider);
    if (uid == null) {
      setState(() => _isLoadingMore = false);
      return;
    }

    try {
      // Usar el provider family con el último documento como cursor
      final nextPage = await ref.read(
        peticionesFiltradasCursorProvider((
          uid: uid,
          filtro: filtro,
          lastDocument: _lastDocument,
        )).future,
      );

      if (mounted) {
        setState(() {
          _allPeticiones.addAll(nextPage.items);
          _lastDocument = nextPage.lastDoc;
          _hasMore = nextPage.hasMore;
          _isLoadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  void _resetPagination() {
    setState(() {
      _allPeticiones.clear();
      _lastDocument = null;
      _hasMore = true;
      _isLoadingMore = false;
    });
  }

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
  Widget build(BuildContext context) {
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

    // Resetear paginación cuando cambia el filtro
    ref.listen(peticionesFiltroProvider, (_, __) {
      _resetPagination();
    });

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
          PopupMenuButton<PeticionesFiltro>(
            initialValue: filtro,
            tooltip: 'Filtrar peticiones',
            icon: const Icon(Icons.filter_list, color: AppTheme.textPrimary),
            onSelected: (value) =>
                ref.read(peticionesFiltroProvider.notifier).setFiltro(value),
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: PeticionesFiltro.todas, child: Text('Todas')),
              const PopupMenuItem(
                  value: PeticionesFiltro.pendientes,
                  child: Text('Pendientes')),
              const PopupMenuItem(
                  value: PeticionesFiltro.respondidas,
                  child: Text('Respondidas')),
              const PopupMenuItem(
                  value: PeticionesFiltro.misOraciones,
                  child: Text('Por las que oro')),
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
              isLoading: peticionesAsync.isLoading && _allPeticiones.isEmpty,
              error: peticionesAsync.error,
              items: _allPeticiones.isEmpty
                  ? peticionesAsync.value
                  : _allPeticiones,
              onRetry: () async {
                _resetPagination();
                // ignore: unused_result
                await ref.refresh(peticionesFiltradasProvider.future);
              },
              emptyTitle: 'No hay peticiones activas.',
              emptyDescription: '¡Sé el primero en pedir apoyo!',
              builder: (context, peticiones) => RefreshIndicator(
                onRefresh: () async {
                  _resetPagination();
                  // ignore: unused_result
                  await ref.refresh(peticionesFiltradasProvider.future);
                  // La primera carga se hace via el stream, así que solo reseteamos
                  // y el stream emitirá la primera página
                  final uid = ref.read(effectiveUserUidProvider);
                  if (uid != null) {
                    final firstPage = await ref.read(
                      peticionesFiltradasCursorProvider((
                        uid: uid,
                        filtro: filtro,
                        lastDocument: null,
                      )).future,
                    );
                    if (mounted) {
                      setState(() {
                        _allPeticiones
                          ..clear()
                          ..addAll(firstPage.items);
                        _lastDocument = firstPage.lastDoc;
                        _hasMore = firstPage.hasMore;
                      });
                    }
                  }
                },
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    if (notification is ScrollEndNotification &&
                        _scrollController.position.pixels >=
                            _scrollController.position.maxScrollExtent - 200 &&
                        _hasMore &&
                        !_isLoadingMore) {
                      _loadMore();
                    }
                    return false;
                  },
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                    itemCount: peticiones.length +
                        (_hasMore && _isLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= peticiones.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      return PeticionCard(peticion: peticiones[index]);
                    },
                  ),
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
