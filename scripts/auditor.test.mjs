#!/usr/bin/env node
// Tests unitarios para el auditor autónomo
//   node --test scripts/auditor.test.mjs

import { describe, it, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert';
import {
  detectorLatido,
  detectorFallosSeguidos,
  detectorPRBehindDirty,
  detectorPRChecksRojos,
  detectorSinTareaLibre,
  detectorCuotaLimite,
  ACCIONES_PERMITIDAS,
  validarAccion,
} from './auditor.mjs';

// ───────────────────────── HELPERS ─────────────────────────

function crearSnapshotBase(sobrescrituras = {}) {
  return {
    timestamp: '2026-10-24 10:00:00',
    supervisores: {
      plataforma: {
        estado: { fallosSeguidos: 0, ciclos: 5 },
        latido: 'hace 5 min',
        ultimasLineas: ['[2026-10-24 10:00:00] [plataforma] ciclo ok'],
        errLog: [],
        directorio: '/fake/plataforma-auto',
      },
      producto: {
        estado: { fallosSeguidos: 0, ciclos: 3 },
        latido: 'hace 3 min',
        ultimasLineas: ['[2026-10-24 10:00:00] [producto] ciclo ok'],
        errLog: [],
        directorio: '/fake/producto-auto',
      },
    },
    prs: {
      board: [],
      detallados: [],
    },
    gitLog: ['abc123 fix: algo', 'def456 feat: otra cosa'],
    fallosSeguidos: { plataforma: 0, producto: 0 },
    procesosHuérfanos: [],
    cicloActual: 10,
    ...sobrescrituras,
  };
}

// ───────────────────────── TESTS DE DETECTORES ─────────────────────────

describe('detectorLatido', () => {
  it('no reporta nada si latido < 40 min', async () => {
    const snap = crearSnapshotBase();
    const r = await detectorLatido(snap);
    assert.strictEqual(r.length, 0);
  });

  it('reporta supervisor-sin-latido si latido > 40 min', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: {
          estado: { fallosSeguidos: 0 },
          latido: 'hace 45 min ⚠ posiblemente parado',
          ultimasLineas: [],
          errLog: [],
          directorio: '/fake/plataforma-auto',
        },
        producto: {
          estado: { fallosSeguidos: 0 },
          latido: 'hace 10 min',
          ultimasLineas: [],
          errLog: [],
          directorio: '/fake/producto-auto',
        },
      },
    });
    const r = await detectorLatido(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].tipo, 'supervisor-sin-latido');
    assert.strictEqual(r[0].carril, 'plataforma');
    assert.strictEqual(r[0].gravedad, 'alta');
  });

  it('reporta ambos si los dos están parados', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: { latido: 'hace 50 min ⚠', ultimasLineas: [], errLog: [], directorio: '', estado: {} },
        producto: { latido: 'hace 60 min ⚠', ultimasLineas: [], errLog: [], directorio: '', estado: {} },
      },
    });
    const r = await detectorLatido(snap);
    assert.strictEqual(r.length, 2);
  });
});

describe('detectorFallosSeguidos', () => {
  it('no reporta si fallos < 2', async () => {
    const snap = crearSnapshotBase({ fallosSeguidos: { plataforma: 1, producto: 0 } });
    const r = await detectorFallosSeguidos(snap);
    assert.strictEqual(r.length, 0);
  });

  it('reporta fallos-seguidos gravedad alta si fallos >= 2', async () => {
    const snap = crearSnapshotBase({ fallosSeguidos: { plataforma: 2, producto: 0 } });
    const r = await detectorFallosSeguidos(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].tipo, 'fallos-seguidos');
    assert.strictEqual(r[0].gravedad, 'alta');
  });

  it('reporta gravedad critica si fallos >= 3', async () => {
    const snap = crearSnapshotBase({ fallosSeguidos: { plataforma: 3, producto: 0 } });
    const r = await detectorFallosSeguidos(snap);
    assert.strictEqual(r[0].gravedad, 'critica');
  });

  it('reporta ambos carriles independientemente', async () => {
    const snap = crearSnapshotBase({ fallosSeguidos: { plataforma: 2, producto: 3 } });
    const r = await detectorFallosSeguidos(snap);
    assert.strictEqual(r.length, 2);
    assert.strictEqual(r[0].gravedad, 'alta');
    assert.strictEqual(r[1].gravedad, 'critica');
  });
});

describe('detectorPRBehindDirty', () => {
  it('no reporta si PR sin auto-merge', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 1, title: 'PR 1', headRefName: 'a/T-001-test', mergeStateStatus: 'BEHIND', autoMergeRequest: false, statusCheckRollup: [] },
        ],
      },
    });
    const r = await detectorPRBehindDirty(snap);
    assert.strictEqual(r.length, 0);
  });

  it('reporta PR BEHIND con auto-merge', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 1, title: 'PR 1', headRefName: 'a/T-001-test', mergeStateStatus: 'BEHIND', autoMergeRequest: true, statusCheckRollup: [] },
        ],
      },
    });
    const r = await detectorPRBehindDirty(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].tipo, 'pr-behind-dirty');
    assert.strictEqual(r[0].carril, 'plataforma');
  });

  it('reporta PR DIRTY con auto-merge', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 2, title: 'PR 2', headRefName: 'b/T-002-test', mergeStateStatus: 'DIRTY', autoMergeRequest: true, statusCheckRollup: [] },
        ],
      },
    });
    const r = await detectorPRBehindDirty(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].carril, 'producto');
  });

  it('no reporta PR CLEAN o MERGING', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 1, title: 'PR 1', headRefName: 'a/T-001-test', mergeStateStatus: 'CLEAN', autoMergeRequest: true, statusCheckRollup: [] },
          { number: 2, title: 'PR 2', headRefName: 'a/T-002-test', mergeStateStatus: 'MERGING', autoMergeRequest: true, statusCheckRollup: [] },
        ],
      },
    });
    const r = await detectorPRBehindDirty(snap);
    assert.strictEqual(r.length, 0);
  });
});

describe('detectorPRChecksRojos', () => {
  it('no reporta si checks verdes', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 1, title: 'PR 1', headRefName: 'a/T-001-test', mergeStateStatus: 'CLEAN', autoMergeRequest: true, statusCheckRollup: [{ name: 'check1', conclusion: 'SUCCESS' }] },
        ],
      },
    });
    const r = await detectorPRChecksRojos(snap);
    assert.strictEqual(r.length, 0);
  });

  it('reporta PR con checks rojos', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 1, title: 'PR 1', headRefName: 'a/T-001-test', mergeStateStatus: 'CLEAN', autoMergeRequest: true, statusCheckRollup: [{ name: 'build', conclusion: 'FAILURE' }, { name: 'test', conclusion: 'SUCCESS' }] },
        ],
      },
    });
    const r = await detectorPRChecksRojos(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].tipo, 'pr-checks-rojos');
    assert.ok(r[0].evidencia.includes('build'));
  });

  it('reporta múltiples PRs con checks rojos', async () => {
    const snap = crearSnapshotBase({
      prs: {
        detallados: [
          { number: 1, title: 'PR 1', headRefName: 'a/T-001-test', mergeStateStatus: 'CLEAN', autoMergeRequest: true, statusCheckRollup: [{ name: 'build', conclusion: 'FAILURE' }] },
          { number: 2, title: 'PR 2', headRefName: 'b/T-002-test', mergeStateStatus: 'CLEAN', autoMergeRequest: true, statusCheckRollup: [{ name: 'lint', conclusion: 'FAILURE' }] },
        ],
      },
    });
    const r = await detectorPRChecksRojos(snap);
    assert.strictEqual(r.length, 2);
  });
});

describe('detectorSinTareaLibre', () => {
  it('no reporta si < 4 ocurrencias', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: { latido: 'hace 5 min', ultimasLineas: ['no hay tarea libre', 'ciclo ok'], errLog: [], directorio: '', estado: {} },
        producto: { latido: 'hace 3 min', ultimasLineas: ['ciclo ok'], errLog: [], directorio: '', estado: {} },
      },
    });
    const r = await detectorSinTareaLibre(snap);
    assert.strictEqual(r.length, 0);
  });

  it('reporta sin-tarea-libre si >= 4 ocurrencias', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: {
          latido: 'hace 5 min',
          ultimasLineas: ['no hay tarea libre', 'no hay tarea libre', 'sin-tarea', 'no hay tarea libre', 'ciclo ok'],
          errLog: [],
          directorio: '',
          estado: {},
        },
        producto: { latido: 'hace 3 min', ultimasLineas: ['ciclo ok'], errLog: [], directorio: '', estado: {} },
      },
    });
    const r = await detectorSinTareaLibre(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].tipo, 'sin-tarea-libre');
    assert.strictEqual(r[0].gravedad, 'media');
  });
});

describe('detectorCuotaLimite', () => {
  it('no reporta si < 2 coincidencias', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: { latido: 'hace 5 min', ultimasLineas: ['429 Too Many Requests'], errLog: [], directorio: '', estado: {} },
        producto: { latido: 'hace 3 min', ultimasLineas: ['ciclo ok'], errLog: [], directorio: '', estado: {} },
      },
    });
    const r = await detectorCuotaLimite(snap);
    assert.strictEqual(r.length, 0);
  });

  it('reporta cuota-limite si >= 2 coincidencias', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: {
          latido: 'hace 5 min',
          ultimasLineas: ['429 Too Many Requests', 'Free usage limit exceeded'],
          errLog: ['Invalid API Key'],
          directorio: '',
          estado: {},
        },
        producto: { latido: 'hace 3 min', ultimasLineas: ['ciclo ok'], errLog: [], directorio: '', estado: {} },
      },
    });
    const r = await detectorCuotaLimite(snap);
    assert.strictEqual(r.length, 1);
    assert.strictEqual(r[0].tipo, 'cuota-limite');
    assert.strictEqual(r[0].gravedad, 'alta');
  });

  it('detecta múltiples patrones: 429, quota, rate limit, expired', async () => {
    const snap = crearSnapshotBase({
      supervisores: {
        plataforma: {
          latido: 'hace 5 min',
          ultimasLineas: ['rate limit exceeded', 'quota exceeded', 'token expired'],
          errLog: [],
          directorio: '',
          estado: {},
        },
        producto: { latido: 'hace 3 min', ultimasLineas: [], errLog: [], directorio: '', estado: {} },
      },
    });
    const r = await detectorCuotaLimite(snap);
    assert.strictEqual(r.length, 1);
  });
});

describe('ACCIONES_PERMITIDAS y validarAccion', () => {
  it('lista blanca contiene solo las 3 acciones permitidas', () => {
    assert.deepStrictEqual(ACCIONES_PERMITIDAS.sort(), ['crearSTOP', 'escribirInforme', 'reiniciarSupervisor'].sort());
  });

  it('validarAccion no lanza para acciones permitidas', () => {
    assert.doesNotThrow(() => validarAccion('reiniciarSupervisor'));
    assert.doesNotThrow(() => validarAccion('crearSTOP'));
    assert.doesNotThrow(() => validarAccion('escribirInforme'));
  });

  it('validarAccion lanza para acciones NO permitidas', () => {
    const prohibidas = ['aprobar', 'merge', 'mergear', 'tocar-secrets', 'branch-protection', 'github-workflows', 'push', 'deploy'];
    for (const a of prohibidas) {
      assert.throws(() => validarAccion(a), { message: /Acción no permitida/ });
    }
  });
});

// ───────────────────────── TESTS DE ESCALADA ─────────────────────────

describe('escalada', () => {
  it('registra problema y escala a 3 ciclos', () => {
    const problemasPendientes = new Map();
    
    function registrar(tipo, evidencia, ciclo) {
      const key = tipo;
      const actual = problemasPendientes.get(key) || { desdeCiclo: ciclo, cuenta: 0 };
      actual.cuenta += 1;
      actual.ultimaEvidencia = evidencia;
      problemasPendientes.set(key, actual);
    }
    
    function debeEscalar(tipo, umbral = 3) {
      const p = problemasPendientes.get(tipo);
      return p && p.cuenta >= umbral;
    }
    
    registrar('fallos-seguidos', 'fallos=3', 1);
    assert.strictEqual(debeEscalar('fallos-seguidos'), false);
    
    registrar('fallos-seguidos', 'fallos=3', 2);
    assert.strictEqual(debeEscalar('fallos-seguidos'), false);
    
    registrar('fallos-seguidos', 'fallos=3', 3);
    assert.strictEqual(debeEscalar('fallos-seguidos'), true);
  });
});

// ───────────────────────── TESTS DE VALIDACIÓN DE TAREAS (lógica pura) ─────────────────────────

describe('validación de tareas propuestas (lógica pura)', () => {
  it('rechaza propuesta sin carril válido', () => {
    function validarCarril(carril) {
      return ['plataforma', 'producto'].includes(carril);
    }
    assert.strictEqual(validarCarril('plataforma'), true);
    assert.strictEqual(validarCarril('producto'), true);
    assert.strictEqual(validarCarril('integradora'), false);
    assert.strictEqual(validarCarril('invalido'), false);
  });

  it('rechaza propuesta con esfuerzo L', () => {
    function validarEsfuerzo(effort) {
      return ['S', 'M'].includes(effort);
    }
    assert.strictEqual(validarEsfuerzo('S'), true);
    assert.strictEqual(validarEsfuerzo('M'), true);
    assert.strictEqual(validarEsfuerzo('L'), false);
  });

  it('requiere al menos 2 criterios de aceptación', () => {
    function validarAcceptance(acceptance) {
      return Array.isArray(acceptance) && acceptance.filter(a => typeof a === 'string' && a.trim().length > 8).length >= 2;
    }
    assert.strictEqual(validarAcceptance(['criterio 1', 'criterio 2']), true);
    assert.strictEqual(validarAcceptance(['corto']), false);
    assert.strictEqual(validarAcceptance([]), false);
    assert.strictEqual(validarAcceptance(['uno muy largo que cumple', 'otro que tambien cumple']), true);
  });

  it('requiere archivos afectados', () => {
    function validarFiles(files) {
      return Array.isArray(files) && files.length > 0;
    }
    assert.strictEqual(validarFiles(['scripts/test.mjs']), true);
    assert.strictEqual(validarFiles([]), false);
    assert.strictEqual(validarFiles(undefined), false);
  });

  it('tipo debe ser válido', () => {
    const TIPOS_VALIDOS = ['security', 'bug', 'refactor', 'test', 'feature', 'docs', 'infra', 'audit'];
    function validarTipo(type) {
      return TIPOS_VALIDOS.includes(type);
    }
    assert.strictEqual(validarTipo('feature'), true);
    assert.strictEqual(validarTipo('bug'), true);
    assert.strictEqual(validarTipo('invalido'), false);
  });

  it('prioridad debe ser válida', () => {
    const PRIORIDADES_VALIDAS = ['P1', 'P2', 'P3'];
    function validarPrioridad(priority) {
      return PRIORIDADES_VALIDAS.includes(priority);
    }
    assert.strictEqual(validarPrioridad('P1'), true);
    assert.strictEqual(validarPrioridad('P2'), true);
    assert.strictEqual(validarPrioridad('P0'), false);
  });
});