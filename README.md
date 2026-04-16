# Sistema Multi-Agente v3.1

[![Version](https://img.shields.io/badge/version-v3.1.1-0a7ea4?style=for-the-badge)](SISTEMA_COMPLETO.md)
[![Python](https://img.shields.io/badge/python-3.13-3776AB?style=for-the-badge&logo=python&logoColor=white)](stack.md)
[![Licencia](https://img.shields.io/badge/licencia-uso%20interno-6f42c1?style=for-the-badge)](LICENSE)

Swarm de agentes con estado compartido, verificación por fases, trazabilidad operativa y toolkit local para bootstrap, instalación de layout y soporte del flujo de trabajo.

## Índice

- [Qué es](#qué-es)
- [Stack](#stack)
- [Arquitectura](#arquitectura)
- [TASK_STATE](#task_state)
- [Agentes](#agentes)
- [Estructura](#estructura)
- [Manual de uso](#manual-de-uso)
- [Prompts disponibles](#prompts-disponibles)
- [Archivos ejecutables](#archivos-ejecutables)
- [Comandos útiles](#comandos-útiles)
- [Documentación](#documentación)
- [Licencia](#licencia)

## Qué es

Este repositorio contiene el núcleo operativo de un sistema multi-agente orientado a desarrollo de software. El workspace local incluye:

- contratos de agentes en `agents/*.agent.md`
- documentación operativa en `SISTEMA_COMPLETO.md`
- scripts de bootstrap, instalación y soporte en `scripts/`
- customizaciones de Copilot en `.github/`
- memoria compartida y audit trail del sistema
- artefactos de evaluación y verificación contractual en `agents/evals/` y `agents/eval_outputs/`

## Stack

| Capa | Tecnología | Ubicación |
|---|---|---|
| Orquestación | contratos Markdown | `agents/*.agent.md` |
| Toolkit local | Python + Bash + PowerShell | `scripts/` |
| Automatización | GitHub Actions | `.github/workflows/` |
| Estado compartido | `TASK_STATE` | flujo completo del swarm |

Notas importantes:

- El stack efectivo del workspace está curado en `stack.md`.
- Flutter/Dart solo aplica cuando la tarea apunta a un proyecto externo con `pubspec.yaml`.
- La configuración MCP del repo no depende de un servicio HTTP embebido local.

## Arquitectura

El sistema está coordinado por `orchestrator` y usa un flujo por fases con verificación paralela antes de cualquier despliegue.

```mermaid
flowchart TD
    U[Usuario] --> O[orchestrator]
    O -.->|Fase -1| SI[skill_installer]
    O -->|Fase 0a| R[researcher]
    O -->|Fase 0| A[analyst]
    O -->|Fase 1| DB[dbmanager]
    O -->|Fase 2a| TDD[tdd_enforcer]
    O -->|Fase 2| IMP[backend / frontend / developer]
    IMP --> V{Fase 3 — Verificacion paralela}
    V --> AUD[auditor]
    V --> QA[qa]
    V --> RT[red_team]
    AUD --> O
    QA --> O
    RT --> O
    O -->|Fase 4| D[devops]
    D -->|Fase 5| SL[session_logger]
    D -->|Fase 5| MC[memory_curator]
    O -.->|Proteccion .agent.md| ER[eval_runner]
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
  "timeout_seconds": 0,
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
- `timeout_seconds` define el presupuesto duro de la fase activa
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
├── .github/
│   ├── copilot-instructions.md
│   ├── prompts/
│   └── workflows/
├── agents/
│   ├── *.agent.md
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
├── stack.md
└── README.md
```

Rutas importantes:

- `agents/memoria_global.md`: memoria compartida persistente
- `agents/evals/`: catálogo y plantillas de evaluación
- `agents/eval_outputs/`: reportes históricos o generados por corridas de evaluación
- `session_log.md`: traza append-only del sistema

## Manual de uso

### 1. Preparar el entorno

Requisitos:

- Git Bash en Windows o Bash compatible en Linux/macOS
- Python disponible en PATH
- opcional: Docker si vas a trabajar con `docker-launcher/`

En Windows:

- si usas Git Bash o WSL, `./scripts/...` funciona directamente
- si usas PowerShell, usa los wrappers `./scripts/<nombre>/<nombre>.ps1`, que localizan Git Bash automáticamente y evitan el `bash.exe` de WSL

Variables de entorno frecuentes:

- `POSTGRES_DB_URL` si el proyecto activo necesita queries directas por MCP Postgres
- `GITHUB_TOKEN` para integraciones remotas con GitHub
- `OPENAI_API_KEY` si alguna tarea o skill externa la requiere

Bootstrap recomendado:

- Instalar prompts y toolkit globales en tu perfil de VS Code: `./scripts/install-copilot-layout/install-copilot-layout.ps1 --force` o `bash ./scripts/install-copilot-layout/install-copilot-layout.sh --force`
- Recargar VS Code
- Usar `/start` desde el chat en cualquier workspace para bootstrap del repo actual

Bootstrap manual del repo actual:

- PowerShell: `./scripts/start/start.ps1 .`
- Bash: `bash ./scripts/start/start.sh .`

`install-copilot-layout` instala prompts globales en la carpeta de usuario de VS Code y deja un toolkit en el perfil del usuario. Después, `/start` usa ese toolkit para hacer un bootstrap mínimo del repo actual: copiar `.github/copilot-instructions.md` si falta, crear `stack.md` si falta e intentar descargar skills con `autoskills` si está disponible. `/start` no materializa `.github/prompts`, `.github/workflows`, `scripts/` ni archivos `.env*` dentro del repo destino.

### 2. Dockerizar un proyecto activo

Puedes invocarlo desde el chat con `/dockerize` o trabajar directamente con la carpeta `scripts/docker-launcher/` cuando el repo ya tenga artefactos Docker.

Flujo recomendado:

1. Asegura que `stack.md` exista con `/start` o `scripts/start/start.*`.
2. Revisa `.env.example` y las variables del proyecto activo.
3. Ejecuta `/dockerize` para generar Dockerfile, compose, `.dockerignore` y `docker-launcher/` adaptados al stack.

### 3. Flujo de trabajo recomendado

1. revisar memoria compartida y documentación
2. bootstrap del repo con `/start` si `stack.md` no existe
3. ejecutar la tarea a través de `orchestrator`
4. verificar el cambio con las herramientas nativas del proyecto activo
5. revisar `session_log.md`, `verified_digest` y memoria al cierre del ciclo cuando corresponda

## Prompts disponibles

Los slash commands mantenidos en este workspace son estos:

- `/start`: bootstrap mínimo del repo actual; crea `.github/copilot-instructions.md` y `stack.md` si faltan e intenta descargar skills.
- `/dockerize`: dockeriza el proyecto activo y genera artefactos de setup local y despliegue.
- `/productionize`: decide qué parte del repo debe ir a producción, reutiliza la lógica de `/dockerize`, limpia artefactos obsoletos con criterio y deja `README.md` listo para GitHub.
- `/skill-installer`: detecta stack y skills útiles para el proyecto activo.
- `/create-project`: inicia un nuevo proyecto desde cero; captura la idea, analiza el stack y genera un brief completo con roadmap.

Estos prompts viven en `.github/prompts/` y también pueden instalarse como prompts globales con `install-copilot-layout`.

## Archivos ejecutables

Los entrypoints operativos reales del repositorio son estos.

Nota para Windows PowerShell: cada script `.sh` listado abajo tiene un wrapper `.ps1` equivalente en la misma subcarpeta cuando aplica.

| Archivo | Qué hace | Uso principal |
|---|---|---|
| `scripts/install-copilot-layout/install-copilot-layout.sh` | Instala los prompts globales preservados y un toolkit portable en el perfil de usuario de VS Code. | `bash ./scripts/install-copilot-layout/install-copilot-layout.sh --force` |
| `scripts/install-repo-layout/install-repo-layout.sh` | Instala el layout canónico completo del repo actual en `.github/` y copia los scripts de soporte todavía vigentes. | `bash ./scripts/install-repo-layout/install-repo-layout.sh .` |
| `scripts/start/start.sh` | Bootstrap mínimo del proyecto: copia `.github/copilot-instructions.md` si falta, crea `stack.md` si falta e intenta descargar skills con `autoskills` sin bloquear si falla. | `bash ./scripts/start/start.sh .` |
| `scripts/docker-launcher/setup.sh` | Prepara el entorno local para el flujo Docker generado por `/dockerize`. | `bash ./scripts/docker-launcher/setup.sh` |
| `scripts/docker-launcher/build.sh` | Construye las imágenes y artefactos del proyecto dockerizado. | `bash ./scripts/docker-launcher/build.sh` |
| `scripts/docker-launcher/launch.sh` | Levanta el stack Docker del proyecto activo con la configuración generada. | `bash ./scripts/docker-launcher/launch.sh` |
| `scripts/verified_digest.py` | Calcula `verified_digest` para un conjunto de archivos y valida consenso entre reports de Fase 3. | `python ./scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md` |

Atajos útiles por archivo:

- `start.sh`: acepta `bash ./scripts/start/start.sh [PROJECT_ROOT]` o `./scripts/start/start.ps1 [PROJECT_ROOT]`
- `verified_digest.py`: soporta `compute` y `verify-consensus`

Ejemplos rápidos:

```bash
# Bootstrap del repo actual
bash ./scripts/start/start.sh .

# Instalar prompts y toolkit globales
bash ./scripts/install-copilot-layout/install-copilot-layout.sh --force

# Digest de archivos críticos
python ./scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md agents/devops.agent.md
```

## Comandos útiles

| Objetivo | Comando |
|---|---|
| Bootstrap del proyecto por chat | `/start` |
| Dockerizar el proyecto por chat | `/dockerize` |
| Detectar skills por chat | `/skill-installer` |
| Instalar prompts y toolkit globales | `./scripts/install-copilot-layout/install-copilot-layout.ps1 --force` en PowerShell, `bash ./scripts/install-copilot-layout/install-copilot-layout.sh --force` en Bash |
| Bootstrap del proyecto | `/start` o `./scripts/start/start.ps1 .` en PowerShell, `bash ./scripts/start/start.sh .` en Bash |
| Instalar layout canónico completo en el repo actual | `./scripts/install-repo-layout/install-repo-layout.ps1 .` en PowerShell, `bash ./scripts/install-repo-layout/install-repo-layout.sh .` en Bash |
| Preparar launcher Docker | `./scripts/docker-launcher/setup.ps1` en PowerShell, `bash ./scripts/docker-launcher/setup.sh` en Bash |
| Construir imágenes Docker | `./scripts/docker-launcher/build.ps1` en PowerShell, `bash ./scripts/docker-launcher/build.sh` en Bash |
| Lanzar stack Docker | `./scripts/docker-launcher/launch.ps1` en PowerShell, `bash ./scripts/docker-launcher/launch.sh` en Bash |
| Calcular digest verificado | `python ./scripts/verified_digest.py compute --workspace-root . agents/orchestrator.agent.md` |

## Documentación

- `SISTEMA_COMPLETO.md`: contratos, fases, reglas de verificación y evolución del sistema
- `.github/copilot-instructions.md`: convenciones del repo cargadas por Copilot
- `.github/prompts/`: slash commands del workspace (`/start`, `/dockerize`, `/skill-installer`, `/create-project`)
- `.github/workflows/`: workflows canónicos de GitHub Actions (`ci.yml` y `rollback.yml`)
- `stack.md`: stack efectivo del workspace
- `agents/memoria_global.md`: memoria compartida del sistema

## Licencia

Este repositorio se distribuye bajo una licencia de uso interno y evaluación. Consulta el archivo `LICENSE` para condiciones completas de uso, redistribución y autorización.

## Estado actual

El workspace está preparado para:

- bootstrap mínimo de repositorios con `/start`
- operar con `TASK_STATE` compartido y salida dual por agente
- materializar layout canónico con `install-repo-layout`
- generar entornos Docker con `/dockerize` y `docker-launcher/`
- documentar decisiones y trazabilidad del swarm de forma consistente