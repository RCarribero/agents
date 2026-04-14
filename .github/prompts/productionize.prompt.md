---
name: "productionize"
description: "Prepara el proyecto activo para producción y para una presentación profesional en GitHub: decide el target deployable, reutiliza la lógica de dockerize, limpia artefactos obsoletos con criterio y reescribe README.md"
agent: "agent"
---

Prepara el proyecto activo para producción y para una presentación profesional en GitHub sin perder precisión técnica ni borrar piezas importantes del repositorio.

Ejecuta las fases siguientes en orden. No pidas confirmación entre fases salvo que detectes una ambigüedad real sobre la identidad pública del proyecto, un conflicto de sobreescritura en archivos existentes o un borrado que no esté respaldado por evidencia clara.

---

## Fase 0 — Descubrimiento y scope deployable

1. Lee `stack.md`, `README.md`, `OBSERVER.md` si existe, los manifests principales (`package.json`, `frontend/package.json`, `pyproject.toml`, `pubspec.yaml`, etc.) y `.github/prompts/dockerize.prompt.md`.
2. Determina cuál es el artefacto que realmente debe ir a producción. Elige una de estas salidas:
   - servicio único en la raíz
   - subproyecto deployable en un subdirectorio
   - stack multi-servicio (por ejemplo backend + frontend)
3. Si el repositorio tiene doble identidad plausible y eso cambia de forma material el enfoque del README principal (por ejemplo framework interno vs producto visible), detente y pide al usuario que elija cuál priorizar antes de reescribir la documentación.
4. Detecta variables de entorno, puertos, dependencias externas y comandos reales de build/typecheck/test.

---

## Fase 1 — Dockerización reutilizando `dockerize`

1. Reutiliza la lógica del prompt `.github/prompts/dockerize.prompt.md` en vez de inventar una dockerización desde cero.
2. Ejecútala sobre el target correcto detectado en Fase 0.
3. Si el proyecto requiere varios servicios, adapta la estrategia:
   - Dockerfile por servicio cuando haga falta
   - `docker-compose.yml` en la raíz para orquestar todo el stack
   - `.dockerignore` y `.env.example` coherentes con la arquitectura real
4. Respeta convenciones del repo. En proyectos Node/Astro/React usa `pnpm`, no `npm`, salvo compatibilidad explícita.
5. No hardcodees credenciales ni valores sensibles.

---

## Fase 2 — Limpieza segura del repositorio

1. Haz inventario de archivos o carpetas potencialmente innecesarios, generados, duplicados, obsoletos o redundantes.
2. Borra solo archivos con evidencia clara de que sobran. Ejemplos válidos:
   - artefactos generados reproducibles
   - duplicados obsoletos reemplazados por versión canónica
   - documentación redundante ya absorbida por archivos canónicos
3. Nunca borres sin aprobación explícita del usuario estos elementos salvo evidencia excepcional muy fuerte:
   - `agents/`
   - `scripts/`
   - `.github/`
   - `stack.md`
   - `session_log.md`
   - `agents/evals/`
   - `agents/eval_outputs/`
   - `*.agent.md`
   - prompts del repositorio
   - memoria compartida
4. Si hay dudas, no borres. Clasifica como `REVIEW` y repórtalo.

---

## Fase 3 — README.md profesional para GitHub

Reescribe `README.md` para que sirva como portada pública del repositorio.

Incluye, cuando aplique:

- propuesta de valor clara en primeras líneas
- badges útiles y reales
- overview breve del producto o toolkit
- arquitectura resumida
- quick start local
- quick start con Docker
- variables de entorno
- comandos principales
- estructura del proyecto
- troubleshooting
- documentación relacionada
- estado del proyecto / roadmap si aporta contexto
- licencia

Reglas:

- Mantén precisión técnica. No conviertas el README en marketing vacío.
- Si hay documentación operativa extensa, enlázala desde README en vez de duplicarla completa.
- Si el repo combina toolkit interno y aplicación visible, el README principal debe reflejar la identidad elegida en Fase 0 y derivar lo secundario a secciones o documentos auxiliares.

---

## Fase 4 — Validación final

1. Ejecuta instalación de dependencias, build, typecheck y tests o chequeos mínimos relevantes para cada servicio afectado.
2. Si hay backend y frontend, valida ambos por separado.
3. Verifica que la dockerización generada es coherente con los comandos reales del proyecto.
4. No declares listo para producción si la validación falla; reporta fallos reales y su impacto.

---

## Entregable final

Resume al terminar:

- target deployable elegido y motivo
- archivos creados o modificados
- archivos borrados y por qué
- elementos marcados como `REVIEW`
- comandos exactos para ejecutar localmente y con Docker
- riesgos residuales o trabajo pendiente