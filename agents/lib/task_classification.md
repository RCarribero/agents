# Clasificación de Tareas

Regla de clasificación obligatoria que el orchestrator aplica **antes de planificar**. Define el modo de ejecución y las fases activas.

---

## Regla de clasificación (primer paso obligatorio)

```
¿La tarea es una pregunta, consulta o petición de explicación?
  → MODO CONSULTA → responder directamente, sin fases, sin agentes

¿La tarea modifica menos de 5 archivos, no toca esquema,
no requiere migración y el cambio es localizado?
  → MODO RÁPIDO → flujo mínimo

¿La tarea es una feature nueva, toca esquema, afecta múltiples
módulos o tiene riesgo alto?
  → MODO COMPLETO → flujo actual completo
```

## MODO CONSULTA

**Cuándo:** preguntas, explicaciones, revisiones de código, búsquedas en el codebase.
**Ejemplos:** "¿qué hace esta función?", "¿dónde se maneja el auth?", "explícame este error"

```
Agentes activos: ninguno
Fases activas: ninguna
Acción: orchestrator responde directamente usando researcher si necesita contexto
Tiempo esperado: segundos
```

## MODO RÁPIDO

**Cuándo:** cambios pequeños y localizados con riesgo bajo.
**Ejemplos:** cambiar un color, corregir un typo, ajustar un texto, fix de una línea,
añadir un campo simple a un formulario, cambiar un mensaje de error.

**Señales de modo rápido:**
- Menos de 5 archivos afectados
- Sin cambio de esquema ni migraciones
- Sin nuevos providers, servicios o dependencias
- El cambio es reversible en menos de 1 minuto

```
Fases activas:
  ├── Fase 2b: Implementador directo (sin tdd_enforcer, sin researcher)
  ├── Fase 3b: QA ligero (solo qa, sin auditor ni red_team)
  └── Fase 4: devops

Agentes omitidos: researcher, tdd_enforcer,
                  analyst, dbmanager, auditor, red_team,
                  memory_curator, session_logger

Verificación mínima:
  El implementador corre lint/analyze antes de entregar.
  qa en Fase 3b solo valida:
    - El cambio cumple el objetivo solicitado
    - No hay regresión obvia en archivos afectados
  Timeout qa: 60s
  Si falla lint → corregir antes de pasar a qa.
  Si el implementador detecta que el cambio es más complejo
  de lo esperado → notificar al orchestrator → escalar a MODO COMPLETO

Tiempo esperado: 30-120 segundos
```

## MODO COMPLETO

**Cuándo:** todo lo demás — features, migraciones, cambios en múltiples módulos,
cualquier cosa con riesgo medio o alto.

```
Fases activas: todas (flujo actual sin cambios)
Tiempo esperado: el habitual
```

## Tabla de clasificación rápida

| Señal en la tarea | Modo |
|---|---|
| "¿qué", "cómo", "dónde", "explica", "muéstrame" | CONSULTA |
| "cambia el color", "corrige el texto", "arregla este typo" | RÁPIDO |
| "añade un campo simple", "cambia este mensaje" | RÁPIDO |
| "falla", "bug", "error" + cambio localizado obvio | RÁPIDO |
| "implementa", "crea", "añade feature", "nueva pantalla" | COMPLETO |
| "migración", "tabla", "RLS", "esquema" | COMPLETO |
| "refactor", "reestructura", "mueve módulo" | COMPLETO |
| ambiguo o no clasificable | COMPLETO (por defecto seguro) |

## Checklist de nivel de riesgo MEDIUM vs HIGH

Usar esta verificación al clasificar riesgo en TASK_STATE antes de activar fases:

**Señales HIGH** — al menos una debe estar presente:
- Cambio de esquema de base de datos (nueva tabla, columna, índice, FK)
- Código de autenticación, autorización o RLS
- Infraestructura (CI/CD, Docker, variables de entorno de producción)
- Migraciones de datos irreversibles
- Cambios en contratos de API públicos o webhooks

**Señales MEDIUM** — ninguna de HIGH pero al menos una de estas:
- Lógica de negocio nueva o modificada
- 3 o más archivos afectados
- Flujos de usuario críticos (checkout, login, pago)
- Dependencias externas nuevas

**Regla de desempate:** Si la clasificación es ambigua entre MEDIUM y HIGH, usar **MEDIUM** (no HIGH). HIGH activa validaciones extra que no deben dispararse innecesariamente. Solo escalar a HIGH cuando la evidencia es clara.

## Escalación de modo durante ejecución

El implementador puede escalar de `MODO RÁPIDO` a `MODO COMPLETO` si detecta:
- Más archivos afectados de los esperados
- Dependencias no previstas
- Riesgo no obvio en el cambio

Formato de escalación:

```xml
<director_report>
task_id: quick-001
status: ESCALATE
next_agent: orchestrator
escalate_to: none
summary: Cambio más complejo de lo esperado — requiere MODO COMPLETO
reason: El fix de UI toca el provider de estado — riesgo de regresión
</director_report>
```

El orchestrator recibe la escalación, reclasifica como `MODO COMPLETO` y reinicia
el flujo desde Fase 0a con el contexto acumulado.

## Documentar el modo en cada plan

El orchestrator indica el modo al inicio de cada plan:

```markdown
## Plan: Cambiar color del botón primario
**MODO:** RÁPIDO
**Motivo:** 1 archivo, sin esquema, cambio reversible

## Plan: Implementar sistema de notificaciones
**MODO:** COMPLETO
**Motivo:** nueva feature, múltiples módulos, nueva tabla
```

## Regla de routing para dbmanager

**Invocar dbmanager SOLO si la tarea requiere alguna de estas operaciones:**
- CREATE TABLE o nueva entidad de datos
- ALTER TABLE (añadir, renombrar o eliminar columna)
- ADD COLUMN / DROP COLUMN
- Nueva RLS policy o modificación de política existente
- Migración de datos estructural
- Nuevo índice no trivial (índice compuesto, parcial o funcional sobre columna nueva)

**NO invocar dbmanager si la tarea es:**
- Búsqueda, consulta o filtrado sobre esquema existente
- Optimización de query sin cambio de índices
- Bugfix de lógica de aplicación (normalización, validación, formateo)
- Lectura de datos o construcción de listados
- UI o lógica que consulta tablas ya definidas

**Clasificación de tipo de tarea antes de decidir:**
```
¿La descripción contiene alguna de estas palabras?
  → "falla", "bug", "error", "rompe", "no funciona", "incorrecto"
  → Tipo: BUGFIX → flujo: [developer | backend] → auditor ∥ qa ∥ red_team → devops
  → dbmanager: OMITIDO salvo que el bugfix requiera rollback de migración

¿La descripción contiene alguna de estas palabras?
  → "buscar", "consultar", "listar", "filtrar", "mostrar", "obtener"
  → Tipo: CONSULTA → flujo: [backend | frontend] → auditor ∥ qa ∥ red_team → devops
  → dbmanager: OMITIDO

¿La descripción contiene alguna de estas palabras?
  → "añadir campo", "nueva tabla", "migración", "esquema", "columna", "RLS"
  → Tipo: SCHEMA_CHANGE → flujo: dbmanager → [backend | frontend] → auditor ∥ qa ∥ red_team → devops
  → dbmanager: REQUERIDO

¿Ninguna de las anteriores?
  → Tipo: FEATURE → revisar si hay cambio de esquema implícito
  → Si hay duda: preguntar al usuario antes de incluir dbmanager
```

**En el plan, documentar siempre la decisión:**
```markdown
**dbmanager:** OMITIDO — tarea de consulta sin cambio de esquema
**dbmanager:** OMITIDO — bugfix de lógica de aplicación
**dbmanager:** REQUERIDO — añadir columna `bio` a tabla `profiles`
```

## Regla de routing para developer vs backend

```
¿La tarea tiene tdd_status: RED y el único objetivo es pasar tests a GREEN?
  → developer

¿La tarea es implementación de lógica de negocio, APIs, endpoints o servicios?
  → backend

¿La tarea toca UI, componentes o pantallas?
  → frontend

¿La tarea es fullstack sin dominio claro?
  → developer (implementador generalista)
```
