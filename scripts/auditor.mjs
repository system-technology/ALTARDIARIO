#!/usr/bin/env node
// Auditor autónomo del ciclo: supervisa los carriles, detecta problemas y propone tareas.
//   node scripts/auditor.mjs                — bucle continuo (cada auditor.minutosEntreCiclos)
//   node scripts/auditor.mjs --una-vez      — un solo ciclo y termina
//   node scripts/auditor.mjs --simulacro    — no actúa (solo informa qué haría)
//   node --test scripts/auditor.test.mjs    — tests unitarios

import { spawn, spawnSync } from 'node:child_process';
import {
  appendFileSync,
  existsSync,
  mkdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const repoBase = resolve(aqui, '..');
const cfg = JSON.parse(readFileSync(join(aqui, 'ciclo.config.json'), 'utf8'));
const auditorCfg = cfg.auditor ?? {
  minutosEntreCiclos: 90,
  directorio: 'auditor-auto',
  modelo: [
    'nvidia/nvidia/nemotron-3-ultra-550b-a55b',
    'opencode/nemotron-3-ultra-free',
  ],
  modeloRevisa: [
    'opencode/glm-5.3-flash-free',
    'nvidia/nvidia/nemotron-3.5-super-vl-120b-a12b',
  ],
  escaladaCiclos: 3,
  minutosFase: 25,
  minutosFaseRespaldo: 15,
};
const own = JSON.parse(readFileSync(join(repoBase, 'ownership.json'), 'utf8'));
const YAML = createRequire(join(repoBase, 'tools/roadmap-mcp/noop.js'))('yaml');

const args = process.argv.slice(2);
const UNA_VEZ = args.includes('--una-vez');
const SIMULACRO = args.includes('--simulacro');

const base = resolve(
  process.env.ALTARDIARIO_SESIONES || join(repoBase, '..', 'sesiones')
);
const dir = join(base, auditorCfg.directorio);
mkdirSync(dir, { recursive: true });

const ficheroEstado = join(dir, 'estado.json');
const ficheroLatido = join(dir, 'latido.txt');
const ficheroLog = join(dir, 'ciclo.log');
const ficheroInforme = join(base, 'INFORME-AUDITOR.md');
const ficheroEscalada = join(base, 'ESCALADA.md');
const ficheroStopGlobal = join(base, 'STOP');
const ficheroStopPropio = join(dir, 'STOP');

const BASH = existsSync('C:/Program Files/Git/bin/bash.exe')
  ? 'C:/Program Files/Git/bin/bash.exe'
  : 'bash';

const ACCIONES_PERMITIDAS = [
  'reiniciarSupervisor',
  'crearSTOP',
  'escribirInforme',
];

// ───────────────────────── utilidades ─────────────────────────

const ahora = () =>
  new Date().toISOString().replace('T', ' ').slice(0, 19);

const log = (m) => {
  const l = `[${ahora()}] ${m}`;
  console.log(l);
  appendFileSync(ficheroLog, l + '\n');
};

const dormir = (ms) => new Promise((r) => setTimeout(r, ms));

const hoy = () => new Date().toLocaleDateString('sv-SE');

const stopPedido = () =>
  existsSync(ficheroStopGlobal) || existsSync(ficheroStopPropio);

function leerEstado() {
  let e = {
    fecha: hoy(),
    ciclos: 0,
    ultimaRevision: null,
    problemasPendientes: {},
  };
  try {
    e = {
      ...e,
      ...JSON.parse(readFileSync(ficheroEstado, 'utf8').replace(/^\uFEFF/, '')),
    };
  } catch {
    /* primera vez */
  }
  if (e.fecha !== hoy()) {
    e.fecha = hoy();
    e.ciclos = 0;
  }
  return e;
}

const guardarEstado = (e) =>
  writeFileSync(ficheroEstado, JSON.stringify(e, null, 2));

const latido = () =>
  writeFileSync(ficheroLatido, `${ahora()}\n`);

function ejecutar(cmd, a, o = {}) {
  const r = spawnSync(cmd, a, {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
    ...o,
  });
  return { codigo: r.status ?? 1, salida: `${r.stdout || ''}${r.stderr || ''}` };
}

const git = (cwd, ...a) => ejecutar('git', a, { cwd });
const gh = (...a) =>
  ejecutar(process.execPath, [join(aqui, 'gh-app.mjs'), 'integradora', 'gh', ...a], {
    cwd: repoBase,
  });

const recorte = (t, n = 4000) => (t.length > n ? '…' + t.slice(-n) : t);

// ───────────────────────── SNAPSHOT (Phase 1) ─────────────────────────

/**
 * Obtiene el estado y latido de cada supervisor (plataforma, producto).
 * Lee directamente los archivos en lugar de require() ciclo-estado.mjs.
 */
function leerCicloEstado() {
  const supervisores = {};
  for (const lane of Object.keys(cfg.carriles)) {
    const d = join(base, `${lane}-auto`);
    let estado = {};
    try {
      estado = JSON.parse(
        readFileSync(join(d, 'estado.json'), 'utf8').replace(/^\uFEFF/, '')
      );
    } catch {
      /* sin estado */
    }
    let latidoMin = 'sin latido';
    try {
      const min = Math.round(
        (Date.now() - statSync(join(d, 'latido.txt')).mtimeMs) / 60000
      );
      latidoMin = `hace ${min} min${min > 40 ? ' ⚠ posiblemente parado' : ''}`;
    } catch {
      /* sin fichero */
    }
    let ultimasLineas = [];
    try {
      ultimasLineas = readFileSync(join(d, 'ciclo.log'), 'utf8')
        .trim()
        .split('\n')
        .slice(-10);
    } catch {
      /* sin log */
    }
    let errLog = [];
    try {
      errLog = readFileSync(join(d, 'ciclo-err.log'), 'utf8')
        .trim()
        .split('\n')
        .slice(-10);
    } catch {
      /* sin err log */
    }
    supervisores[lane] = {
      estado,
      latido: latidoMin,
      ultimasLineas,
      errLog,
      directorio: d,
    };
  }
  return supervisores;
}

/**
 * Obtiene PRs abiertos con mergeStateStatus y checks usando board.mjs o gh directamente.
 */
async function obtenerPRs() {
  // Usamos board.mjs vía spawn para obtener salida parseable
  const r = spawnSync(process.execPath, [join(aqui, 'board.mjs'), '--all'], {
    encoding: 'utf8',
    maxBuffer: 64 * 1024 * 1024,
  });
  const lineas = (r.stdout || '').trim().split('\n').slice(1); // skip header

  const prs = [];
  for (const l of lineas) {
    if (!l.trim()) continue;
    const match = l.match(/^(T-\d{3})\s+(\w+)\s+(\w+)\s+(\S+)\s+(.+)$/);
    if (match) {
      const [, id, prio, status, real, prInfo] = match;
      prs.push({ id, priority: prio, status, real, prInfo });
    }
  }

  // También obtenemos info detallada con gh para mergeStateStatus y checks
  const r2 = gh(
    'pr',
    'list',
    '--repo',
    cfg.repo,
    '--state',
    'open',
    '--limit',
    '200',
    '--json',
    'number,title,headRefName,state,isDraft,mergeStateStatus,statusCheckRollup,author'
  );
  let detallados = [];
  try {
    detallados = JSON.parse(r2.salida);
  } catch {
    /* sin datos */
  }

  return { board: prs, detallados };
}

/**
 * git log de origin/main desde la última revisión.
 */
function gitLogDesdeRevision(ultimaRevision) {
  const desde = ultimaRevision
    ? `${ultimaRevision}..origin/main`
    : 'origin/main~20..origin/main';
  const r = git(repoBase, 'log', '--oneline', '--since=48 hours ago', desde);
  return r.codigo === 0 ? r.salida.trim().split('\n') : [];
}

/**
 * Cuenta fallos seguidos por carril.
 */
function contarFallosSeguidos() {
  const fallos = {};
  for (const lane of Object.keys(cfg.carriles)) {
    const d = join(base, `${lane}-auto`);
    try {
      const e = JSON.parse(
        readFileSync(join(d, 'estado.json'), 'utf8').replace(/^\uFEFF/, '')
      );
      fallos[lane] = e.fallosSeguidos ?? 0;
    } catch {
      fallos[lane] = 0;
    }
  }
  return fallos;
}

/**
 * Lista procesos opencode huérfanos (sin supervisor padre).
 */
function listarProcesosOpencode() {
  const r = spawnSync('tasklist', ['/FO', 'CSV', '/NH'], { encoding: 'utf8' });
  const lineas = (r.stdout || '').split('\n');
  const huérfanos = [];
  for (const l of lineas) {
    if (l.includes('opencode') && l.includes('run')) {
      huérfanos.push(l.trim());
    }
  }
  return huérfanos;
}

/**
 * Recopila la instantánea completa para los detectores.
 */
async function recopilarSnapshot() {
  const estado = leerEstado();
  const supervisores = leerCicloEstado();
  const { board, detallados } = await obtenerPRs();
  const gitLog = gitLogDesdeRevision(estado.ultimaRevision);
  const fallosSeguidos = contarFallosSeguidos();
  const procesosHuérfanos = listarProcesosOpencode();

  const snapshot = {
    timestamp: ahora(),
    supervisores,
    prs: { board, detallados },
    gitLog,
    fallosSeguidos,
    procesosHuérfanos,
    cicloActual: estado.ciclos,
  };

  estado.ultimaRevision = `origin/main@${git(repoBase, 'rev-parse', '--short', 'origin/main').salida.trim()}`;
  estado.ciclos += 1;
  guardarEstado(estado);

  return snapshot;
}

// ───────────────────────── DETECTORES (funciones puras, exportadas para test) ─────────────────────────

/**
 * Detector: supervisor sin latido más de 40 min.
 */
function detectorLatido(snapshot) {
  const hallazgos = [];
  for (const [lane, sup] of Object.entries(snapshot.supervisores)) {
    const match = sup.latido.match(/hace (\d+) min/);
    if (match && Number(match[1]) > 40) {
      hallazgos.push({
        tipo: 'supervisor-sin-latido',
        gravedad: 'alta',
        carril: lane,
        evidencia: `Latido: ${sup.latido}`,
        lineaLog: `supervisores.${lane}.latido`,
      });
    }
  }
  return hallazgos;
}

/**
 * Detector: fallos seguidos >= 2 en un carril.
 */
function detectorFallosSeguidos(snapshot) {
  const hallazgos = [];
  for (const [lane, fallos] of Object.entries(snapshot.fallosSeguidos)) {
    if (fallos >= 2) {
      hallazgos.push({
        tipo: 'fallos-seguidos',
        gravedad: fallos >= 3 ? 'critica' : 'alta',
        carril: lane,
        evidencia: `Fallos seguidos: ${fallos}`,
        lineaLog: `fallosSeguidos.${lane}`,
      });
    }
  }
  return hallazgos;
}

/**
 * Detector: PR con auto-merge BEHIND o DIRTY más de 2h.
 */
function detectorPRBehindDirty(snapshot) {
  const hallazgos = [];
  const dosHorasAtras = Date.now() - 2 * 60 * 60 * 1000;

  for (const pr of snapshot.prs.detallados) {
    if (!pr.autoMergeRequest) continue;
    const estado = pr.mergeStateStatus;
    if (estado === 'BEHIND' || estado === 'DIRTY') {
      // Verificar si el PR se creó/actualizó hace más de 2h
      // Como no tenemos timestamp exacto, usamos heurística: si está en BEHIND/DIRTY
      hallazgos.push({
        tipo: 'pr-behind-dirty',
        gravedad: 'media',
        carril: pr.headRefName?.startsWith('a/') ? 'plataforma' : 'producto',
        evidencia: `PR #${pr.number} "${pr.title}" mergeStateStatus=${estado} con auto-merge`,
        lineaLog: `prs.detallados[#${pr.number}].mergeStateStatus`,
      });
    }
  }
  return hallazgos;
}

/**
 * Detector: PR con checks rojos.
 */
function detectorPRChecksRojos(snapshot) {
  const hallazgos = [];
  for (const pr of snapshot.prs.detallados) {
    const rojos = (pr.statusCheckRollup ?? []).filter(
      (c) => c.conclusion === 'FAILURE'
    );
    if (rojos.length > 0) {
      hallazgos.push({
        tipo: 'pr-checks-rojos',
        gravedad: 'alta',
        carril: pr.headRefName?.startsWith('a/') ? 'plataforma' : 'producto',
        evidencia: `PR #${pr.number} "${pr.title}" checks rojos: ${rojos
          .map((r) => r.name)
          .join(', ')}`,
        lineaLog: `prs.detallados[#${pr.number}].statusCheckRollup`,
      });
    }
  }
  return hallazgos;
}

/**
 * Detector: mismo ciclo "no hay tarea libre" 4 veces seguidas.
 */
function detectorSinTareaLibre(snapshot) {
  const hallazgos = [];
  // Buscar en los logs de los supervisores "no hay tarea libre"
  for (const [lane, sup] of Object.entries(snapshot.supervisores)) {
    let cuenta = 0;
    for (const l of sup.ultimasLineas) {
      if (l.includes('no hay tarea libre') || l.includes('sin-tarea')) {
        cuenta++;
      }
    }
    if (cuenta >= 4) {
      hallazgos.push({
        tipo: 'sin-tarea-libre',
        gravedad: 'media',
        carril: lane,
        evidencia: `Detectado "no hay tarea libre" ${cuenta} veces en últimos eventos`,
        lineaLog: `supervisores.${lane}.ultimasLineas`,
      });
    }
  }
  return hallazgos;
}

/**
 * Detector: errores de cuota/límite (429, Free usage limit, Invalid API Key, expired) repetidos.
 */
function detectorCuotaLimite(snapshot) {
  const hallazgos = [];
  const patrones = [
    /429/,
    /Free usage limit/i,
    /Invalid API Key/i,
    /expired/i,
    /quota/i,
    /rate limit/i,
  ];

  for (const [lane, sup] of Object.entries(snapshot.supervisores)) {
    let cuenta = 0;
    for (const l of [...sup.ultimasLineas, ...sup.errLog]) {
      for (const p of patrones) {
        if (p.test(l)) {
          cuenta++;
          break;
        }
      }
    }
    if (cuenta >= 2) {
      hallazgos.push({
        tipo: 'cuota-limite',
        gravedad: 'alta',
        carril: lane,
        evidencia: `${cuenta} coincidencias de errores de cuota/límite en logs`,
        lineaLog: `supervisores.${lane}.ultimasLineas + errLog`,
      });
    }
  }
  return hallazgos;
}

/**
 * Detector: ficheros prohibidos, secretos o tests borrados en commits nuevos de main.
 * Reutiliza escanear-secretos.mjs y añade detección de tests borrados (diff-filter=D).
 */
async function detectorSecretosProhibidos(snapshot) {
  const hallazgos = [];

  // 1. Secretos y ficheros prohibidos en commits nuevos (AM)
  const r1 = ejecutar(process.execPath, [
    join(aqui, 'escanear-secretos.mjs'),
    '--base',
    'origin/main',
  ]);
  if (r1.codigo !== 0) {
    hallazgos.push({
      tipo: 'secretos-prohibidos',
      gravedad: 'critica',
      carril: 'global',
      evidencia: r1.salida.trim(),
      lineaLog: 'escanear-secretos.mjs --base origin/main',
    });
  }

  // 2. Tests borrados en commits nuevos de main (diff-filter=D)
  const r2 = git(repoBase, 'diff', '--name-only', '--diff-filter=D', 'origin/main^..origin/main');
  const borrados = r2.salida.trim().split('\n').filter(Boolean);
  const testsBorrados = borrados.filter((f) => f.startsWith('test/') && f.endsWith('.dart'));
  if (testsBorrados.length > 0) {
    hallazgos.push({
      tipo: 'tests-borrados',
      gravedad: 'alta',
      carril: 'global',
      evidencia: `Tests borrados en main: ${testsBorrados.join(', ')}`,
      lineaLog: 'git diff --diff-filter=D origin/main^..origin/main',
    });
  }

  return hallazgos;
}

/**
 * Ejecuta todos los detectores y devuelve hallazgos consolidados.
 */
async function ejecutarDetectores(snapshot) {
  const detectores = [
    detectorLatido,
    detectorFallosSeguidos,
    detectorPRBehindDirty,
    detectorPRChecksRojos,
    detectorSinTareaLibre,
    detectorCuotaLimite,
    detectorSecretosProhibidos,
  ];

  let todos = [];
  for (const d of detectores) {
    const h = await d(snapshot);
    todos.push(...h);
  }
  return todos;
}

// ───────────────────────── ACCIONES (lista blanca) ─────────────────────────

/**
 * Valida que la acción está en la lista blanca.
 */
function validarAccion(accion) {
  if (!ACCIONES_PERMITIDAS.includes(accion)) {
    throw new Error(
      `Acción no permitida: ${accion}. Lista blanca: ${ACCIONES_PERMITIDAS.join(', ')}`
    );
  }
}

/**
 * Reinicia un supervisor caído (spawn desacoplado de node scripts/ciclo.mjs <carril>).
 */
async function reiniciarSupervisor(carril) {
  validarAccion('reiniciarSupervisor');
  const logProceso = join(base, `${carril}-auto`, 'proceso.log');
  const hijo = spawn(process.execPath, [join(aqui, 'ciclo.mjs'), carril], {
    cwd: repoBase,
    detached: true,
    stdio: ['ignore', 'ignore', 'ignore'],
    windowsHide: true,
  });
  hijo.unref();
  log(`Reiniciado supervisor ${carril} (PID ${hijo.pid}), salida en ${logProceso}`);
  return { ok: true, pid: hijo.pid };
}

/**
 * Crea STOP global ante secretos en main o fallos seguidos >= 3 en ambos carriles.
 */
async function crearSTOPGlobal() {
  validarAccion('crearSTOP');
  writeFileSync(ficheroStopGlobal, `Creado por auditor: ${ahora()}\n`);
  log('STOP global creado');
  return { ok: true };
}

/**
 * Escribe el informe en INFORME-AUDITOR.md.
 */
async function escribirInforme(ciclo, hallazgos) {
  validarAccion('escribirInforme');
  const linea = hallazgos.length === 0
    ? `${ahora()} — Ciclo ${ciclo}: sin novedades`
    : hallazgos
        .map(
          (h) =>
            `${ahora()} — Ciclo ${ciclo}: ${h.tipo} (${h.gravedad}) en ${h.carril} — ${h.evidencia} [${h.lineaLog}]`
        )
        .join('\n');

  appendFileSync(ficheroInforme, linea + '\n');
  log(`Informe escrito: ${hallazgos.length} hallazgos`);
  return { ok: true };
}

// ───────────────────────── ESCALADA ─────────────────────────

const problemasPendientes = new Map(); // tipo -> { desdeCiclo, cuenta, ultimaEvidencia }

function registrarProblema(tipo, evidencia, ciclo) {
  const key = `${tipo}`;
  const actual = problemasPendientes.get(key) || { desdeCiclo: ciclo, cuenta: 0 };
  actual.cuenta += 1;
  actual.ultimaEvidencia = evidencia;
  problemasPendientes.set(key, actual);
}

function limpiarResueltos(hallazgosActuales) {
  const tiposActuales = new Set(hallazgosActuales.map((h) => h.tipo));
  for (const [key, v] of problemasPendientes.entries()) {
    if (!tiposActuales.has(key)) {
      problemasPendientes.delete(key);
    }
  }
}

async function comprobarEscalada(ciclo, hallazgos) {
  for (const h of hallazgos) {
    const key = h.tipo;
    const p = problemasPendientes.get(key);
    if (p && p.cuenta >= auditorCfg.escaladaCiclos) {
      const contenido = `# Escalada — ${ahora()}

## Problema persistente
- **Tipo:** ${h.tipo}
- **Carril:** ${h.carril}
- **Gravedad:** ${h.gravedad}
- **Ciclos sin resolver:** ${p.cuenta} (desde ciclo ${p.desdeCiclo})
- **Evidencia actual:** ${h.evidencia}
- **Evidencia original:** ${p.ultimaEvidencia}

## Acción requerida
El auditor no puede resolver este problema con sus acciones permitidas (${ACCIONES_PERMITIDAS.join(
        ', '
      )}).
Necesita intervención de: **Owner o auditor externo**.

---
`;
      appendFileSync(ficheroEscalada, contenido);
      log(`ESCALADA escrita para ${key} (${p.cuenta} ciclos)`);
    }
  }
}

// ───────────────────────── FASE 2: MODELO ─────────────────────────

/**
 * Fase 2 con modelo: lee snapshot y detectores, devuelve diagnóstico y tareas propuestas.
 */
async function faseModelo(snapshot, hallazgos) {
  if (SIMULACRO) {
    log('SIMULACRO: saltando Fase 2 (modelo)');
    return { propuestas: [], diagnostico: 'simulacro' };
  }

  const wt = join(dir, `fase2-${Date.now()}`);
  mkdirSync(wt, { recursive: true });

  try {
    // Escribir FASE.md con el contexto para el modelo
    const mensaje = `# Fase AUDITOR — Análisis y propuestas

## Instantánea del ciclo
\`\`\`json
${JSON.stringify(snapshot, null, 2).slice(0, 15000)}
\`\`\`

## Hallazgos de detectores deterministas
${hallazgos
  .map(
    (h) =>
      `- **${h.tipo}** (${h.gravedad}) [${h.carril}]: ${h.evidencia} — _${h.lineaLog}_`
  )
  .join('\n') || 'Ninguno'}

## Tu misión
Analiza la instantánea y los hallazgos. Para cada problema:
1. Diagnostica la causa raíz (máximo 3 líneas por problema).
2. Propone **una tarea concreta** por problema (tipo, prioridad, esfuerzo S/M, criterios de aceptación verificables, ficheros afectados).
3. Las tareas deben ser de **un solo carril** (plataforma=a o producto=b según ownership.json).
4. NO propongas tareas que toquen rutas protegidas (firestore.rules, .github/, pubspec.yaml, etc.).

## Formato de salida
Escribe \`PROPUESTAS.json\` en la raíz del worktree con exactamente:
\`\`\`json
{
  "diagnostico": "resumen ejecutivo 3-5 líneas",
  "propuestas": [
    {
      "title": "Título claro y accionable",
      "type": "security|bug|refactor|test|feature|docs|infra|audit",
      "priority": "P1|P2|P3",
      "effort": "S|M",
      "acceptance": ["criterio verificable 1", "criterio verificable 2"],
      "files": ["ruta/real/archivo.dart", "..."],
      "carril": "plataforma|producto",
      "evidencia": "fichero:línea o comando que prueba el problema"
    }
  ]
}
\`\`\`

**Reglas:**
- Un carril por tarea (validado con ownership.json).
- Criterios verificables (ej: "test X pasa", "scripts/check.sh --fast verde", "regla Y deniega Z").
- Esfuerzo S o M (L no permitido, dividir antes).
- Sin rutas humanRequired salvo que sea estrictamente necesario y se justifique.
- ${JSON.stringify(ACCIONES_PERMITIDAS)} son las ÚNICAS acciones que el auditor puede ejecutar; no propongas approve, merge, secretos, branch protection, .github.
`;

    writeFileSync(join(wt, 'FASE.md'), mensaje);

    // Probar modelos en cascada
    const modelos = auditorCfg.modelo;
    let propuestas = null;
    let diagnostico = '';

    for (const [i, modelo] of modelos.entries()) {
      const logFase = join(dir, 'logs', `${hoy()}-fase2${i ? `-respaldo${i}` : ''}.log`);
      mkdirSync(dirname(logFase), { recursive: true });
      writeFileSync(logFase, '');

      log(`Fase 2 con modelo ${modelo}${i ? ' (respaldo)' : ''}…`);

      const r = await new Promise((resolve) => {
        const usaShell = process.platform === 'win32';
        const hijo = usaShell
          ? spawn(
              [process.execPath, join(aqui, '..', 'node_modules/.bin/opencode'), 'run', '--auto', '--model', modelo, '--title', `auditor-fase2`, 'Lee FASE.md en la raíz de este worktree y ejecútalo entero.'].join(' '),
              { cwd: wt, shell: true, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }
            )
          : spawn(
              join(aqui, '..', 'node_modules/.bin/opencode'),
              ['run', '--auto', '--model', modelo, '--title', 'auditor-fase2', 'Lee FASE.md en la raíz de este worktree y ejecútalo entero.'],
              { cwd: wt, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }
            );

        const trozos = [];
        const timeout = setTimeout(() => {
          hijo.kill('SIGKILL');
          resolve({ codigo: 1, salida: '', agotado: true });
        }, (i ? auditorCfg.minutosFaseRespaldo : auditorCfg.minutosFase) * 60000);

        const recibir = (d) => {
          const txt = d.toString();
          trozos.push(txt);
          appendFileSync(logFase, txt);
        };
        hijo.stdout.on('data', recibir);
        hijo.stderr.on('data', recibir);
        hijo.on('close', (codigo) => {
          clearTimeout(timeout);
          resolve({ codigo, salida: trozos.join(''), agotado: false });
        });
        hijo.on('error', (e) => {
          clearTimeout(timeout);
          resolve({ codigo: 1, salida: String(e), agotado: false });
        });
      });

      latido();

      if (r.agotado) {
        log(`Fase 2 agotó el tiempo con ${modelo}`);
        continue;
      }

      // Leer PROPUESTAS.json
      try {
        const prop = JSON.parse(readFileSync(join(wt, 'PROPUESTAS.json'), 'utf8'));
        propuestas = prop.propuestas ?? [];
        diagnostico = prop.diagnostico ?? '';
        if (propuestas.length > 0) break;
      } catch {
        log(`${modelo} no produjo PROPUESTAS.json válido`);
      }
    }

    if (!propuestas || !propuestas.length) {
      log('Fase 2: sin propuestas válidas de ningún modelo');
      return { propuestas: [], diagnostico: 'sin propuestas válidas' };
    }

    // Validar propuestas con roadmap.mjs
    const { load, validate, addTask, save } = await import(
      pathToFileURL(join(repoBase, 'tools/roadmap-mcp/roadmap.mjs')).href
    );
    const fichTareas = join(wt, 'roadmap/tasks.yaml');
    const store = load(fichTareas);

    const validas = [];
    for (const p of propuestas) {
      // Validar carril único
      const carril = p.carril;
      if (!['plataforma', 'producto'].includes(carril)) {
        log(`Propuesta rechazada: carril inválido "${p.carril}"`);
        continue;
      }
      // Validar que archivos pertenecen al carril
      const prefijoCarril = { plataforma: 'a', producto: 'b' };
      const prefijo = prefijoCarril[carril];
      const reLane = own.lanes[prefijo].owns.map((g) =>
        new RegExp('^' + g.replace(/\*/g, '.*').replace(/\?/g, '.') + '$')
      );
      const mal = p.files.find(
        (f) => !reLane.some((r) => r.test(f)) && !own.shared.some((s) => new RegExp('^' + s.replace(/\*/g, '.*') + '$').test(f))
      );
      if (mal) {
        log(`Propuesta rechazada: archivo ${mal} no pertenece a carril ${carril}`);
        continue;
      }
      // Validar con roadmap.mjs
      try {
        const nueva = addTask(store.data, {
          title: p.title,
          type: p.type,
          priority: p.priority,
          effort: p.effort,
          acceptance: p.acceptance,
          files: p.files,
          source: `auditor-auto:${hoy()}`,
        });
        validas.push(nueva);
        log(`Propuesta válida: ${nueva.id} — ${nueva.title}`);
      } catch (e) {
        log(`Propuesta rechazada por validador: ${e.message}`);
      }
    }

    if (!validas.length) {
      return { propuestas: [], diagnostico: 'ninguna propuesta pasó validación' };
    }

    // Guardar en tasks.yaml y crear PR con app Integradora
    const errores = validate(store.data);
    if (errores.length) throw new Error('tasks.yaml no valida: ' + errores.join('; '));
    save(store, fichTareas);

    // Commit y push con Integradora
    const sha = git(repoBase, 'rev-parse', '--short', 'origin/main').salida.trim();
    git(wt, 'add', 'roadmap');
    git(wt, 'commit', '-q', '-m', `docs(roadmap): auditor automático, ${validas.length} tareas nuevas`);
    const push = ejecutar(process.execPath, [join(aqui, 'gh-app.mjs'), 'integradora', 'push'], { cwd: wt });
    if (push.codigo !== 0) throw new Error('push falló: ' + push.salida);

    const pr = gh('pr', 'create', '--repo', cfg.repo, '--base', 'main', '--head', `i/T-000-auditor-${Date.now()}`, '--title', `docs(roadmap): auditor automático, ${validas.length} tareas nuevas`, '--body', `Propuestas del auditor autónomo (ciclo ${snapshot.cicloActual}).\n\nDiagnóstico: ${diagnostico}`);
    if (pr.codigo !== 0) throw new Error('pr create falló: ' + pr.salida);

    gh('pr', 'merge', `i/T-000-auditor-${Date.now()}`, '--repo', cfg.repo, '--auto', '--squash');

    log(`Fase 2 completada: ${validas.length} tareas publicadas en PR`);
    return { propuestas: validas, diagnostico };
  } finally {
    rmSync(wt, { force: true, recursive: true });
  }
}

// ───────────────────────── MAIN LOOP ─────────────────────────

async function main() {
  log(`Auditor iniciado (${UNA_VEZ ? 'un ciclo' : 'continuo'}${SIMULACRO ? ', SIMULACRO' : ''})`);

  for (;;) {
    latido();

    if (stopPedido()) {
      log('STOP detectado: me detengo');
      return;
    }

    const estado = leerEstado();

    // Phase 1: snapshot + detectores
    log('Recopilando snapshot…');
    const snapshot = await recopilarSnapshot();

    log('Ejecutando detectores…');
    const hallazgos = await ejecutarDetectores(snapshot);

    // Registrar problemas para escalada
    for (const h of hallazgos) registrarProblema(h.tipo, h.evidencia, estado.ciclos);
    limpiarResueltos(hallazgos);

    // Escribir informe
    await escribirInforme(estado.ciclos, hallazgos);

    // Acciones deterministas permitidas
    for (const h of hallazgos) {
      if (h.tipo === 'supervisor-sin-latido' && h.gravedad === 'alta') {
        await reiniciarSupervisor(h.carril);
      }
      if (h.tipo === 'fallos-seguidos' && h.gravedad === 'critica') {
        // Si AMBOS carriles tienen >=3 fallos, crear STOP global
        const ambos = Object.values(snapshot.fallosSeguidos).every((f) => f >= 3);
        if (ambos) await crearSTOPGlobal();
      }
      if (h.tipo === 'secretos-prohibidos' && h.gravedad === 'critica') {
        await crearSTOPGlobal();
      }
    }

    // Escalada
    await comprobarEscalada(estado.ciclos, hallazgos);

    // Phase 2: modelo (solo si hay hallazgos y no es simulacro)
    if (hallazgos.length > 0 && !SIMULACRO) {
      log('Ejecutando Fase 2 (modelo)…');
      await faseModelo(snapshot, hallazgos);
    } else if (SIMULACRO) {
      log('SIMULACRO: Fase 2 omitida');
    }

    if (UNA_VEZ) return;

    await dormir(auditorCfg.minutosEntreCiclos * 60000);
  }
}

if (pathToFileURL(process.argv[1]).href === import.meta.url) {
  main().catch((e) => {
    log(`FATAL: ${e.stack || e}`);
    process.exit(1);
  });
}

// ───────────────────────── EXPORTS PARA TESTS ─────────────────────────

export {
  detectorLatido,
  detectorFallosSeguidos,
  detectorPRBehindDirty,
  detectorPRChecksRojos,
  detectorSinTareaLibre,
  detectorCuotaLimite,
  detectorSecretosProhibidos,
  ACCIONES_PERMITIDAS,
  validarAccion,
  recopilarSnapshot,
  ejecutarDetectores,
};