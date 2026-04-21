import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

const checks = [
  {
    file: 'agents/orchestrator.agent.md',
    required: [
      'research_brief.relevant_files',
      'No fuerces rediscovery en implementación.',
      'subconjunto mínimo ejecutable derivado de `research_brief.relevant_files`',
    ],
  },
  {
    file: 'agents/backend.agent.md',
    required: [
      'Consume discovery previo primero.',
      'research gap',
      'No remapees el proyecto completo',
    ],
    forbidden: [
      'Analiza los archivos del contexto para entender arquitectura, patrones y convenciones existentes antes de tocar nada.',
    ],
  },
  {
    file: 'agents/developer.agent.md',
    required: [
      'Consume discovery previo primero.',
      'Lectura local, no rediscovery.',
      'research gap',
    ],
  },
  {
    file: 'agents/frontend.agent.md',
    required: [
      'Consume discovery previo primero.',
      'Lee antes de tocar, pero local.',
      'research gap',
    ],
    forbidden: [
      'Analiza los componentes existentes, el sistema de diseño, los tokens de estilo y los patrones de layout en uso. Sin este análisis, no escribas una línea.',
    ],
  },
  {
    file: 'agents/tdd_enforcer.agent.md',
    required: [
      'Consume discovery previo primero.',
      'Lectura local, no rediscovery.',
      'research gap',
    ],
  },
];

const failures = [];

for (const check of checks) {
  const fullPath = path.join(rootDir, check.file);
  const content = await readFile(fullPath, 'utf8');

  for (const snippet of check.required ?? []) {
    if (!content.includes(snippet)) {
      failures.push(`${check.file}: missing required snippet -> ${snippet}`);
    }
  }

  for (const snippet of check.forbidden ?? []) {
    if (content.includes(snippet)) {
      failures.push(`${check.file}: forbidden broad-discovery snippet still present -> ${snippet}`);
    }
  }
}

if (failures.length > 0) {
  console.error('Agent scope guard failed.');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exitCode = 1;
} else {
  console.log('Agent scope guard passed.');
}