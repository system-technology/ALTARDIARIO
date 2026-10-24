# Changelog

Formato: [Keep a Changelog](https://keepachangelog.com/es/1.1.0/). Versionado semántico.

## [Unreleased]

### Añadido
- Biblia RVR1960 empaquetada y funcional offline desde primer arranque (T-078).
- `assets/bible/LICENCIAS.md`: registro de licencias por versión (RVR1960 por decisión Owner, RVR1909/WEB/KJV dominio público).
- Pantalla de versiones: atribución/licencia visible, reintento de descarga (3× backoff exponencial), tamaño de archivo en MB.
- Tests: `bible_license_test`, `bible_service_offline_test`, `bible_download_service_test`, `bible_versions_screen_test`.

### Seguridad
- Reglas de Firestore reescritas: nadie edita contenido ajeno; chats privados solo para participantes; notificaciones no suplantables; contadores sociales acotados a ±1 con uid propio; colección `reports` para moderación.
- Chats: allowlist de campos actualizables en `/chats` (`participantIds`, `lastMessage`, `lastSenderId`, `lastUpdate`, `participantNames`) y `create` con participantes duplicados rechazado.
- App Check activado en cliente (monitor; pasar a enforce en consola).
- Bloqueo real: si un usuario te bloqueó (o tú a él), ninguno de los dos puede comentar, responder, escribir en el chat, notificar ni seguir al otro; las reglas lo comprueban con `exists()` sobre `usuarios/{uid}/blocked/{uid}`. Dejar de seguir sigue permitido para que el bloqueado pueda limpiar su rastro. 6 tests de reglas nuevos (41/41).

### Añadido
- Auditor autónomo del ciclo (`scripts/auditor.mjs` + `scripts/auditor.test.mjs`): supervisor continuo con latido, STOP global, Phase 1 (snapshot + 7 detectores deterministas) y Phase 2 (modelo con fallback en cascada), acciones permitidas en lista blanca (reiniciar supervisor, crear STOP, escribir informe), informe por ciclo en `sesiones/INFORME-AUDITOR.md` y escalada en `sesiones/ESCALADA.md`. CLI: `--una-vez`, `--simulacro`. Sección `auditor` en `ciclo.config.json`. (T-073)
- Script de migración del campo `oculto` (`scripts/migrar-oculto.mjs`): recorre `reflexiones`, `debates`, `peticiones_oracion` (colecciones raíz) y `comentarios`, `respuestas` (collectionGroup); pone `oculto=false` donde falta el campo y `oculto=true` si tenían `hidden:true`; idempotente, lotes de 400, simulacro por defecto con `--aplicar` para escribir; usa `firebase-admin` de `functions/node_modules` con `GOOGLE_APPLICATION_CREDENTIALS`. (T-071)
- Componentes de estados asíncronos reutilizables (`lib/presentation/widgets/estados/`): carga, vacío, error con reintento y `AsyncStateBuilder`, con tests. Rescatados de la rama `rescate/main-local-20261022-2201`.
- Compartir versículo como imagen (T-010): botón Compartir en lector genera texto con versículo, referencia y marca AltarDiario; usa share_plus para Android/iOS/Web.
- Paginacion real del feed con startAfterDocument e infinite scroll: feedPageSize=30, getReflexionesPage con cursor, FeedPaginationNotifier. (T-007)
- Debate biblico de calidad: etiquetas, respuestas anidadas de un nivel, reglas comunitarias visibles, cerrar debate por autor, reportar debate. (T-031)
- Búsqueda y temas seguidos en la comunidad: campo temasSeguidos en Usuario, método toggleTemaSeguido en FirestoreService, provider temasSeguidosProvider, y sección Mis temas seguidos en FeedScreen para seguir/dejar de seguir temas.
- Suite de tests de reglas de Firestore con emulador (`firestore-tests/`).
- Observabilidad: Crashlytics, Analytics (`lib/core/observability`).
- Base de i18n (ARB es/en) y `flutter_localizations`.
- Esqueleto de Cloud Functions: XP en servidor y moderación por reportes.
- Herramienta de migración de datos privados del perfil (`functions`: `npm run migrate:private-account`; idempotente, por lotes y con `--apply` explícito) y orden de operaciones documentado en `docs/SECURITY.md`.
- Andamiaje de IA: `AGENTS.md` v2, `opencode.jsonc` V2, agentes `planner`/`reviewer`/`rules-auditor`/`release-manager`, comandos y skills.
- CI/CD en GitHub Actions: format/analyze/test, reglas, builds Android/Web, deploy de Firebase, release Android por tag, Dependabot.
- Grafo de conocimiento versionado (`.opencode/knowledge-graph.jsonl`): el CI lo sincroniza desde el diff de contratos y abre un PR; en local es de solo lectura.
- `scripts/check.sh`, `scripts/rules_test.sh`, `scripts/bootstrap.sh`.
- Documentación: ROADMAP, ADR-0001/0002/0003, AI_WORKFLOW, SECURITY, RELEASE.
- Inicio: tarjeta de la lectura de hoy con cuatro estados (cargando con skeleton, sin conexión, pendiente y completado). Se abre con un solo toque, al completar el día muestra una celebración discreta y la siguiente lectura del plan, y respeta el escalado de texto del sistema.

- Publicar reflexión: el borrador sobrevive al cierre de la app y se recupera al volver; publicar exige una vista previa con confirmación explícita; y las notas se convierten en reflexión con un toque, sin copiar texto.
- Widget test de PublicarReflexionScreen: flujo completo borrador (textoInicial desde Notas y borrador recuperado) → vista previa → publicar, con todos los providers sobrescritos por mocks y sin Firebase real. (T-064)
- Biblioteca personal (Notas): aviso de que las notas son privadas (solo el dueño puede verlas), exportación bajo demanda al portapapeles (nada se envía a otros usuarios ni a terceros) y estado de error con reintento que no bloquea la lectura.
- Observabilidad: los eventos de producto pasan por una capa que descarta textos, correos, tokens y motivos libres; solo números, booleanos y categorías cerradas llegan a Analytics. Cableados `lectura_completada` y `nota_guardada`.
- Observabilidad: al publicar una reflexión se envía `reflexion_publicada` con la longitud del texto y si lleva pasaje; el texto en sí nunca sale del dispositivo.
- `DESIGN.md` (antes `design.md`): escala espacial cerrada, CTA único por vista y estados obligatorios de vista (datos/carga/error/vacío) con microcopia UX.
- Coordinación entre sesiones: `docs/SESIONES.md` (worktree por sesión, un solo merger, máximo 2 PRs, validar contra `origin/main` citando SHA), registro en `roadmap/sesiones/` y scripts `session-check.sh` / `sync-main.sh` (el `main` local no se usa para trabajar y solo se alinea por fast-forward).
- Borrado de cuenta desde Perfil con reautenticación (Google/Apple/email): borra perfil y cuenta privada de Firestore, elimina el usuario de Auth y vuelve a login (T-054).

### Cambiado
- Feed, oración (feature `lib/features/oracion/`) y debates (listado y detalle) adoptan `AsyncStateBuilder` y los widgets de estados (`LoadingStateView`, `ErrorStateView`, `EmptyStateView`): carga no bloqueante, error en lenguaje humano con botón Reintentar y vacío con microcopia propia, en sustitución de `when` con `Center(Text('Error: …'))` y estados vacíos duplicados por pantalla; de paso se corrige un texto con acentos corruptos ('SÃ© el primero en responder.') en el detalle de debate. (T-059)
- Moderación: `reportarContenido` y `moderationRepositoryProvider` migrados a `lib/features/moderation/` (`data/`, `providers/`, `presentation/`). (T-035)
- CI: el job `Build APK (debug)` solo compila cuando el PR toca `android/`, `pubspec.*` o `.github/workflows/` (y siempre en `main`); añade caché de Gradle y compila una sola ABI. Los PRs de Dart/UI bajan de ~7,6 a ~1,5 min de checks; el nombre del check requerido no cambia.
- Feed de reflexiones limitado a 100 documentos por lectura (antes: colección completa).
- Streams de colecciones sociales y chats limitados para controlar lecturas; se conserva el escalado de texto configurado por el sistema.
- `sendMessage` crea el documento del chat antes del mensaje (requerido por las reglas).
- `analysis_options.yaml` con lints adicionales.
- Mocks permitidos en tests (`mocktail`, `fake_cloud_firestore`, `firebase_auth_mocks`).
- Formato y lints alineados con Dart 3.12 / Flutter 3.44; `pubspec.lock` y registro de plugins regenerados.

### Arreglado
- Chat: `sendMessage` ya no reescribe `participantIds`/`participantNames` en chats existentes y la UI conserva el texto si el envío falla (con reintento).
- Chats: las reglas aceptan el reordenamiento de `participantIds` al enviar mensajes (antes solo podía escribir quien creó el chat). Tests de reglas para todas las escrituras del cliente.
- Build Android en CI: Gradle 8.14.3, AGP 8.11.1 y Kotlin 2.2.20 (mínimos de Flutter stable); `google-services.json` restaurado desde secret; archivos generados (`local.properties`, `GeneratedPluginRegistrant.java`, logs de Kotlin) fuera del control de versiones.
- Firestore: eliminado el índice redundante de un solo campo en `respuestas` que impedía el deploy de índices; Firestore ya cubre `fecha` con el índice de campo único.
- `borrarCuenta(uid)` borra el perfil público y el documento privado `usuarios/{uid}/private/account` en una operación batch; las reglas permiten al dueño borrar su cuenta privada.
- Reglas: límites de tamaño en debates (título ≤200, contenido ≤5000), respuestas (contenido ≤2000), comentarios de petición (texto ≤2000) y notificaciones (title ≤200, body ≤1000), aplicados también en la edición del dueño.
- Roadmap: `STATE.md` ya no duplica el encabezado de los ciclos (`## ## Ciclo N`) ni deja ciclos sin cabecera, y `scripts/loop.sh` termina con exit 0 (el `head` ya no rompe el pipe con SIGPIPE).
- Roadmap: tests de regresión que garantizan que guardar `tasks.yaml` solo reescribe las claves que cambian (guardar sin cambios no altera ni un byte).
- Skill `frontend-design`: reescrito en markdown válido (el archivo estaba escapado con `\---` y `\#`, por lo que no se cargaba); añade ergonomía táctil, microcopia y checklist de entrega, y enlaza los tokens de `DESIGN.md`.

### Pendiente (no incluido en esta rama)
- UI de reportar/bloquear usuario.
- Migración a `lib/features/`.
- Paginación real del feed.

## [1.0.4] - 2026-07-31
- Diccionario bíblico offline, tipografía Lora, shimmer, háptica. (Ver BITACORA.md para el historial anterior.)
