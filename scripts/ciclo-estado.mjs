#!/usr/bin/env node
// Resumen del ciclo autónomo: qué hace cada carril, presupuesto, fallos, últimos eventos y PRs.
//   node scripts/ciclo-estado.mjs
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const aqui = dirname(fileURLToPath(import.meta.url));
const cfg = JSON.parse(readFileSync(join(aqui, 'ciclo.config.json'), 'utf8'));
const base = resolve(process.env.ALTARDIARIO_SESIONES || join(aqui, '..', '..', 'sesiones'));
const hoy = new Date().toLocaleDateString('sv-SE');

console.log(`Sesiones: ${base}`);
console.log(`Freno global STOP: ${existsSync(join(base, 'STOP')) ? 'ACTIVO (los ciclos se detienen)' : 'no'}\n`);

for (const lane of Object.keys(cfg.carriles)) {
  const dir = join(base, `${lane}-auto`);
  console.log(`━━ ${lane} ━━`);
  if (!existsSync(dir)) { console.log('  sin actividad todavía\n'); continue; }
  let e = {};
  try { e = JSON.parse(readFileSync(join(dir, 'estado.json'), 'utf8')); } catch { /* sin estado */ }
  const ciclos = e.fecha === hoy ? e.ciclos : 0;
  let latido = 'sin latido';
  try { const min = Math.round((Date.now() - statSync(join(dir, 'latido.txt')).mtimeMs) / 60000); latido = `hace ${min} min${min > 40 ? '  ⚠ posiblemente parado' : ''}`; } catch { /* sin fichero */ }
  console.log(`  ciclos hoy: ${ciclos}/${cfg.maxCiclosDia} · fallos seguidos: ${e.fallosSeguidos ?? 0}/${cfg.maxFallosSeguidos} · última tarea: ${e.ultimaTarea ?? '—'} · latido: ${latido}`);
  if (e.parado) console.log(`  ⛔ PARADO: ${e.parado} (ver ${join(dir, 'PARADO.md')})`);
  if (existsSync(join(dir, 'STOP'))) console.log('  ⏸ freno STOP propio activo');
  try {
    const lineas = readFileSync(join(dir, 'ciclo.log'), 'utf8').trim().split('\n').slice(-6);
    console.log('  últimos eventos:\n' + lineas.map((l) => '    ' + l.slice(0, 160)).join('\n'));
  } catch { /* sin log */ }
  console.log('');
}

// Auditor
const auditorDir = join(base, 'auditor-auto');
console.log(`━━ auditor ━━`);
if (!existsSync(auditorDir)) {
  console.log('  sin actividad todavía\n');
} else {
  let e = {};
  try { e = JSON.parse(readFileSync(join(auditorDir, 'estado.json'), 'utf8')); } catch { /* sin estado */ }
  const ciclos = e.fecha === hoy ? e.ciclos : 0;
  let latido = 'sin latido';
  try {
    const min = Math.round((Date.now() - statSync(join(auditorDir, 'latido.txt')).mtimeMs) / 60000);
    latido = `hace ${min} min${min > 40 ? '  ⚠ posiblemente parado' : ''}`;
  } catch { /* sin fichero */ }
  console.log(`  ciclos hoy: ${ciclos} · latido: ${latido}`);
  if (e.problemasPendientes !== undefined) {
    console.log(`  problemas abiertos: ${e.problemasPendientes}`);
  }
  if (existsSync(join(auditorDir, 'STOP'))) console.log('  ⏸ freno STOP propio activo');
  // ESCALADA.md en la raíz de sesiones (base)
  if (existsSync(join(base, 'ESCALADA.md'))) {
    console.log('  🚨 ESCALADA.md existe — revisar');
  }
  try {
    const lineas = readFileSync(join(auditorDir, 'ciclo.log'), 'utf8').trim().split('\n').slice(-6);
    console.log('  últimos eventos:\n' + lineas.map((l) => '    ' + l.slice(0, 160)).join('\n'));
  } catch { /* sin log */ }
  console.log('');
}

const r = spawnSync(process.execPath, [join(aqui, 'board.mjs')], { encoding: 'utf8' });
const pend = (r.stdout || '').split('\n').filter((l) => /EN REVISIÓN|RESERVADA/.test(l));
console.log('PRs de tareas en curso:\n' + (pend.length ? pend.map((l) => '  ' + l).join('\n') : '  ninguno'));
const prs = spawnSync('gh', ['pr', 'list', '--repo', cfg.repo, '--state', 'open', '--label', 'autonomo', '--json', 'number,title,reviewDecision,mergeStateStatus', '--jq', '.[]|"  #\\(.number) [\\(.mergeStateStatus)] \\(.title[0:80])"'], { encoding: 'utf8' });
console.log('\nPRs autónomos abiertos (los de rutas protegidas esperan tu aprobación):\n' + ((prs.stdout || '').trim() || '  ninguno'));