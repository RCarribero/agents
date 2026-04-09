# Sistema Multi-Agente v3.1

[![Version](https://img.shields.io/badge/version-v3.1.0-0a7ea4?style=for-the-badge)](SISTEMA_COMPLETO.md)
[![Python](https://img.shields.io/badge/python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](.copilot/stack.md)
[![FastAPI](https://img.shields.io/badge/FastAPI-agents%20api-009688?style=for-the-badge&logo=fastapi&logoColor=white)](agents/api/README.md)
[![Tests](https://img.shields.io/badge/tests-passing-2ea043?style=for-the-badge)](scripts/run-tests.sh)
[![Lint](https://img.shields.io/badge/lint-passing-22863a?style=for-the-badge)](scripts/run-lint.sh)
[![Licencia](https://img.shields.io/badge/licencia-uso%20interno-6f42c1?style=for-the-badge)](LICENSE)

Swarm de agentes con estado compartido, verificación por fases, trazabilidad operativa y una API auxiliar embebida para MCP, observabilidad y utilidades de backend.

## Índice

- [Qué es](#qué-es)
- [Stack](#stack)
- [Arquitectura](#arquitectura)
- [TASK_STATE](#task_state)
- [Agentes](#agentes)
- [Estructura](#estructura)
- [Manual de uso](#manual-de-uso)
- [Comandos útiles](#comandos-útiles)
- [API embebida](#api-embebida)
- [Documentación](#documentación)
- [Licencia](#licencia)

## Qué es

Este repositorio contiene el núcleo operativo de un sistema multi-agente orientado a desarrollo de software. El workspace local incluye:

- contratos de agentes en `agents/*.agent.md`
- documentación operativa en `SISTEMA_COMPLETO.md`
- scripts de validación, lint y test en `scripts/`
- memoria compartida y audit trail del sistema
- una API FastAPI en `agents/api` para MCP, observabilidad y utilidades

## Stack

| Capa | Tecnología | Ubicación |
|---|---|---|
| Orquestación | agentes por contrato Markdown | `agents/*.agent.md` |
| Backend auxiliar | Python + FastAPI | `agents/api` |
| Persistencia / integración | Supabase | `agents/api` |
| Automatización | Bash | `scripts/` |
| Estado compartido | `TASK_STATE` | flujo completo del swarm |

Notas importantes:

- El stack efectivo del workspace está curado en `.copilot/stack.md`.
- Flutter/Dart solo aplica cuando la tarea apunta a un proyecto externo con `pubspec.yaml`.

## Arquitectura

El sistema está coordinado por `orchestrator` y usa un flujo por fases con verificación paralela antes de cualquier despliegue.

```mermaid
flowchart TD
    U[Usuario] --> O[orchestrator]
    O --> SI[skill_installer]
    O --> R[researcher]
    O --> A[analyst]
    O --> DB[dbmanager]
    O --> TDD[tdd_enforcer]
    O --> IMP[backend | frontend | developer]
    IMP --> AUD[auditor]
    IMP --> QA[qa]
    IMP --> RT[red_team]
    AUD --> O
    QA --> O
    RT --> O
    O --> D[devops]
    D --> SL[session_logger]
    D --> MC[memory_curator]
```

La especificación completa del flujo, reintentos, gates y handoffs vive en `SISTEMA_COMPLETO.md`.

## TASK_STATE

Todo el swarm gira alrededor de un estado compartido mínimo:

```json
{
  "task_id": "",
  "goal": "",
  "plan": [],
  "current_step": "",
  "files": [],
  "risk_level": "LOW | MEDIUM | HIGH",
  "attempts": 0,
  "history": []
}
```

Extensiones compatibles del proyecto:

- `constraints`
- `risks`
- `artifacts`

Reglas clave:

- `history` siempre hace append
- `risk_level` se clasifica antes de planificar
- `files` define el scope operativo del ciclo
- los agentes operativos emiten `director_report` y `agent_report`

## Agentes

### Núcleo de ejecución

- `orchestrator`: clasifica, planifica y sincroniza el swarm
- `backend`, `frontend`, `developer`: implementadores según dominio
- `dbmanager`: diseño y migraciones de datos
- `tdd_enforcer`: tests en RED antes de producción

### Verificación

- `auditor`: seguridad y correctitud crítica
- `qa`: verificación funcional
- `red_team`: edge cases y vectores hostiles

### Soporte del ciclo

- `skill_installer`: detecta stack y skills activos
- `researcher`: mapea el módulo afectado
- `analyst`: análisis estratégico y features ausentes
- `devops`: único agente con permisos git
- `session_logger`: audit trail append-only
- `memory_curator`: consolidación de aprendizajes

## Estructura

```text
.
├── .copilot/
├── .github/
├── agents/
│   ├── *.agent.md
│   ├── api/
│   ├── eval_outputs/
│   ├── evals/
│   └── memoria_global.md
├── instructions/
├── logs/
├── runs/
├── scripts/
├── session-state/
├── session_log.md
├── SISTEMA_COMPLETO.md
└── README.md
```

Rutas importantes:

- `agents/api/migrations/`: migraciones SQL del workspace
- `agents/api/tests/`: tests de la API
- `agents/memoria_global.md`: memoria compartida persistente
- `session_log.md`: traza append-only del sistema

## Manual de uso

### 1. Preparar el entorno

Requisitos:

- Git Bash en Windows o Bash compatible en Linux/macOS
- Python disponible en PATH
- dependencias de `agents/api/requirements.txt`

Instalación base:

```bash
python -m pip install -r ./agents/api/requirements.txt
```

### 2. Validar el workspace

```bash
./scripts/validate-stack.sh .
./scripts/validate-agents.sh
./scripts/validate-memory.sh
```

`validate-stack.sh` resuelve automáticamente el subproyecto real cuando la raíz del repo no contiene los manifests directos.

### 3. Ejecutar tests y lint

```bash
./scripts/run-tests.sh . --json
./scripts/run-lint.sh . --json
```

Ambos scripts detectan el stack y trabajan contra `agents/api` cuando corresponde.

### 4. Levantar la API embebida

```bash
cd agents/api
python main.py
```

O con Uvicorn:

```bash
cd agents/api
uvicorn main:app --host 0.0.0.0 --port 8000
```

### 5. Flujo de trabajo recomendado

1. validar stack y contratos
2. revisar memoria compartida y documentación
3. ejecutar la tarea a través de `orchestrator`
4. verificar tests/lint desde raíz
5. revisar `session_log.md` y memoria al cierre del ciclo

## Comandos útiles

| Objetivo | Comando |
|---|---|
| Detectar stack | `./scripts/validate-stack.sh .` |
| Validar contratos | `./scripts/validate-agents.sh` |
| Validar memoria | `./scripts/validate-memory.sh` |
| Ejecutar tests | `./scripts/run-tests.sh . --json` |
| Ejecutar lint | `./scripts/run-lint.sh . --json` |
| Arrancar API | `cd agents/api && python main.py` |

## API embebida

La API auxiliar vive en `agents/api` y expone:

- `/health`
- `/ping`
- `/products/search`
- `/mcp/tools`
- `/metrics/*`

Más detalle en `agents/api/README.md`.

## Documentación

- `SISTEMA_COMPLETO.md`: contratos, fases, reglas de verificación y evolución del sistema
- `.github/copilot-instructions.md`: convenciones del repo
- `.copilot/stack.md`: stack efectivo del workspace
- `agents/memoria_global.md`: memoria compartida del sistema
- `agents/api/README.md`: documentación específica de la API

## Licencia

Este repositorio se distribuye bajo una licencia de uso interno y evaluación. Consulta el archivo `LICENSE` para condiciones completas de uso, redistribución y autorización.

## Estado actual

El workspace está preparado para:

- validar contratos de agentes
- ejecutar tests y lint desde la raíz
- resolver automáticamente el subproyecto backend
- operar con `TASK_STATE` compartido y salida dual por agente
- documentar decisiones y trazabilidad del swarm de forma consistente