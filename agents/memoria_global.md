---
user-invocable: false
---
# Memoria Global del Sistema de Agentes

Historial de lecciones aprendidas durante sesiones de trabajo. Consulta este archivo antes de cada implementación para evitar errores conocidos y respetar convenciones establecidas.

---

## Política de esta memoria

Solo se registran lecciones aplicables a cualquier proyecto con el mismo stack, con patrón que seguirá siendo relevante en un proyecto diferente, y que pueden describirse sin mencionar nombres de vistas, tablas, rutas o entidades del proyecto actual. Si cualquiera de esas tres condiciones falla, la lección se anota en `session_log.md`, no aquí.

---

## [2026-04-10] multiagent-hygiene-002 — Política de modelos por agente

**Agentes:** todos

El modelo de cada agente es una decisión de diseño: refleja el balance entre coste, velocidad y capacidad de razonamiento exigido por el rol. Cambiar un modelo requiere actualizar la justificación inline en el frontmatter (`model: 'X'  # justificación`) y pasar eval-gate. No se aceptan cambios de modelo sin ambas condiciones cumplidas.

---

## [2026-04-07] routing-fix-v1.0.1 — Reglas de routing para dbmanager

**Agentes:** orchestrator (corregido)

### Problema detectado
El orchestrator sobre-invocaba dbmanager en tareas que no requerían cambio de esquema.
Detectado en eval-002 (tarea de consulta) y eval-005 (bugfix de lógica).
Score grupo Routing: 60% antes del fix.

### Causa raíz
El orchestrator interpretaba "verificar si existe un índice" o "comprobar constraints"
como razón suficiente para invocar dbmanager, cuando el umbral debe ser
exclusivamente cambios estructurales.

### Fix aplicado
Reglas de routing explícitas en orchestrator.agent.md:

**Invocar dbmanager SOLO si:**
- CREATE TABLE / nueva entidad
- ALTER TABLE
- ADD COLUMN / DROP COLUMN
- Nueva RLS policy o modificación de existente
- Migración de datos estructural
- Índice compuesto, parcial o funcional sobre columna nueva

**NO invocar dbmanager si:**
- Búsqueda, consulta o filtrado sobre esquema existente
- Bugfix de lógica de aplicación
- Optimización de query sin cambio de índices
- UI o lógica que consulta tablas ya definidas

**Clasificación de tipo de tarea:**
- Palabras clave BUGFIX: "falla", "bug", "error", "rompe", "no funciona"
- Palabras clave CONSULTA: "buscar", "consultar", "listar", "filtrar", "obtener"
- Palabras clave SCHEMA_CHANGE: "añadir campo", "nueva tabla", "migración", "columna", "RLS"

### Resultado
Score grupo Routing: 60% → 100%
Score general: 80% → 93%
Evals recuperadas: eval-002, eval-005

### Errores a evitar (Antipatrón)
NO hacer esto en el plan:
```
Fase 1 — [dbmanager] → Verificar existencia de tabla y evaluar índices
```
cuando la tarea es solo una búsqueda o un bugfix de código.

### Buenas prácticas (Patrón correcto)
Documentar siempre la decisión en el plan:
```
**dbmanager:** OMITIDO — tarea de consulta sin cambio de esquema
**dbmanager:** OMITIDO — bugfix de lógica de aplicación
**dbmanager:** REQUERIDO — añadir columna X a tabla Y
```

---

## [2026-04-07] patrón: campo de texto largo con validación multicapa

**Agentes:** dbmanager, backend, frontend

### Buenas prácticas
- **Flujo completo DB→Backend→UI funciona sin fricción** cuando la migración de esquema precede a la implementación de lógica.
- **Campo de texto largo requiere validación a tres niveles:** DB (CHECK length), backend (max chars), frontend (contador visual).
- **Migración idempotente con backward compatibility:** agregar columna nullable primero, rellenar datos si aplica, luego añadir constraints.

### Errores a evitar
- No implementar UI de campo de texto sin validación de longitud máxima — causa overflow visual y problemas de UX.
- No confiar solo en validación de frontend; backend debe validar independientemente antes de persistir.

---

## [2026-04-07] ciclo2-busqueda-endpoint — Endpoint de búsqueda

**Agentes:** dbmanager, backend, auditor, qa, devops

### Buenas prácticas
- **Índice de búsqueda full-text debe preceder al endpoint:** crear índice GiST o GIN en columnas de texto antes de implementar la query para evitar table scans.
- **Paginación por cursor > OFFSET** en tablas con crecimiento esperado; usar `id > last_seen_id LIMIT n` en vez de `OFFSET n`.
- **RLS obligatoria en tablas consultadas:** auditor rechaza automáticamente si falta policy de lectura basada en `auth.uid()`.

### Errores a evitar
- No usar `LIKE '%term%'` sin índice — causa degradación exponencial con millones de filas.
- No validar input de búsqueda en backend permite inyección SQL si se construye query dinámicamente (usar parámetros siempre).

---

## [2026-04-07] patrón: ciclo1 cambio cosmético — validación de accesibilidad en UI

**Agentes:** frontend, auditor, qa, devops

### Buenas prácticas
- **Cambios cosméticos simples (color, espaciado) aprobables en un solo ciclo** cuando respetan sistema de diseño existente.
- **Verificación de contraste WCAG AA obligatoria** antes de entregar a auditor — frontend debe validar ratio ≥4.5:1 para texto normal.
- **Workflow acelerado para UI sin lógica:** frontend → auditor+qa (paralelo) → devops, sin necesidad de tests adicionales.

### Errores a evitar
- No validar accesibilidad de color en cambios visuales — auditor y qa rechazan si contraste insuficiente.
- No documentar cambios de token de diseño en sistema centralizado — causa divergencia entre componentes.

---

## [2026-04-07] patrón: migración de stack de autenticación y magic strings

**Agentes:** frontend, auditor, qa

### Buenas prácticas
- **Verificar consistencia de stacks de auth entre frontend y backend ANTES de implementar.** Frontend que llama al SDK incorrecto bloquea login completamente al llegar a producción.
- **Interfaz del contexto de autenticación idéntica tras migración:** permite cambiar el proveedor de auth sin romper componentes consumidores (cambio en una capa, no en cascada).
- **Optimistic updates en operaciones de baja latencia:** actualizar estado local inmediatamente y hacer rollback solo si el backend devuelve error. Mejora UX sin riesgo de inconsistencia.

### Errores a evitar
- **Magic strings sin archivo de constantes:** valores de estado/tipo hardcodeados en múltiples lugares divergen silenciosamente. Si hay >3 ocurrencias del mismo literal, crear archivo de constantes.
- **Console.log activo en producción:** puede exponer tokens decodificados o payloads sensibles. Deshabilitar mediante configuración de build (por ejemplo `vite.config.ts`).
- **Mensajes de error de backend expuestos directamente en UI:** mapear errores a mensajes genéricos user-friendly para no revelar arquitectura interna.
- **Auth como single point of failure sin fallback:** verificar que el frontend tiene una ruta de auth funcional antes de eliminar la anterior.
