---
user-invocable: false
---
# Memoria Global del Sistema de Agentes

Historial de lecciones aprendidas durante sesiones de trabajo. Consulta este archivo antes de cada implementación para evitar errores conocidos y respetar convenciones establecidas.

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

## [2026-04-07] ciclo3-bio-perfil — Campo bio en perfil de usuario

**Agentes:** dbmanager, backend, frontend, auditor, qa, devops

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

## [2026-04-07] ciclo1-color-boton — Cambio de color en botón primario

**Agentes:** frontend, auditor, qa, devops

### Buenas prácticas
- **Cambios cosméticos simples (color, espaciado) aprobables en un solo ciclo** cuando respetan sistema de diseño existente.
- **Verificación de contraste WCAG AA obligatoria** antes de entregar a auditor — frontend debe validar ratio ≥4.5:1 para texto normal.
- **Workflow acelerado para UI sin lógica:** frontend → auditor+qa (paralelo) → devops, sin necesidad de tests adicionales.

### Errores a evitar
- No validar accesibilidad de color en cambios visuales — auditor y qa rechazan si contraste insuficiente.
- No documentar cambios de token de diseño en sistema centralizado — causa divergencia entre componentes.

---

## [2026-04-07] NetTask — Migración de autenticación y bugfixes

**Agentes:** frontend, qa, auditor, memory_curator

### Hallazgo 1: Migración Django Auth (auth-migration-django-001)

**Contexto:**
Frontend estaba configurado para usar Supabase Auth SDK, bloqueando completamente login y registro porque backend solo provee Django Auth + JWT.

**Solución aplicada:**
- Reescritura completa de `frontend/src/api/auth.ts` — eliminó `supabase.auth.signUp/signInWithPassword`, agregó llamadas directas a Django endpoints
- Reescritura completa de `frontend/src/context/AuthContext.tsx` — eliminó listeners de Supabase session, simplificó a JWT + localStorage
- `frontend/src/api/supabase.ts` marcado como obsoleto para auth, mantiene funcionalidad real-time

**Arquitectura antes:**
```
UI → AuthContext → supabase.auth.signInWithPassword() → Supabase Auth → /sync-supabase → Django
```

**Arquitectura después:**
```
UI → AuthContext → axios POST /api/auth/login → Django → JWT tokens → localStorage
```

**Buenas prácticas validadas:**
- Verificar consistencia de stacks de autenticación entre frontend y backend ANTES de deploy
- Testing de prioridad por criticidad: login/register probados primero (88.9% endpoints verificados)
- Usar emails únicos con timestamp en testing para evitar colisiones de datos seed
- Migración sin breaking changes: AuthContext interface idéntica para componentes consumidores

**Antipatrones detectados y documentados:**
- **Magic strings descentralizados:** Tipos de columna hardcodeados sin constantes compartidas ("done", "completado" vs "terminado")
- **No verificar comunicación E2E antes de deploy:** Login funcionaba en backend pero frontend nunca lo llamaba
- **Auth sin fallback = single point of failure:** Frontend dependía 100% de Supabase Auth sin alternativa a Django directo

### Hallazgo 2: Bug de tachado de tareas (task-strikethrough-bug-001)

**Problema:**
Tareas completadas no se tachaban visualmente al moverlas a columna "Terminado", solo después de recargar página.

**Causa raíz:**
Frontend verificaba tipos de columna incorrectos: `destCol?.tipo === "done" || destCol?.tipo === "completado"` cuando el backend usa `TIPO_TERMINADO = 'terminado'`

**Corrección:**
Cambio de 1 línea en `DashboardPage.tsx:218`: `const isCompleting = destCol?.tipo === "terminado";`
Actualización adicional en líneas 147 y 505 para consistencia.

**Impacto:**
- Estado local `completada` ahora se actualiza inmediatamente en drag & drop
- TaskCard renderiza `line-through` sin esperar respuesta del backend (optimistic update)
- 3 líneas modificadas, 0 breaking changes

**Buenas prácticas:**
- Verificar constantes de backend antes de implementar lógica condicional en frontend
- Cambios de valores de constantes (no lógica) = bajo riesgo de regresión
- Optimistic updates mejoran UX cuando la operación backend es altamente probable que tenga éxito

**Antipatrones detectados:**
- **3 valores adicionales de tipo de columna también incorrectos:** "todo" debería ser "backlog", "in_progress" → "progreso", "testing" → "testeo" (no bloqueante, deuda técnica documentada)
- **Magic strings sin archivo de constantes:** Debería existir `frontend/src/constants/columns.ts` con `COLUMN_TYPES = { TERMINADO: 'terminado', ... }`

### Hallazgo 3: Auditoría de seguridad post-migración (auth-migration-django-001.audit)

**Veredicto:** APROBADO CON OBSERVACIONES (severidad MEDIA)

**Hallazgos de severidad MEDIA:**
1. **Exposición de `error.message` en UI sin sanitizar** (ErrorBoundary.tsx:49) — Stack traces pueden exponer arquitectura interna
2. **Console.log activo en producción** (20+ ocurrencias) — Puede exponer tokens decodificados o payloads de API
3. **Mensajes de backend expuestos directamente** (auth.ts:80, LoginPage.tsx:35) — Errores técnicos pueden revelar nombres de tablas o queries SQL

**Hallazgos de severidad BAJA:**
1. CSP permite `'unsafe-inline'` (nginx.conf:30) — Reduce defensa contra XSS
2. Validación de contraseña solo en cliente (LoginPage.tsx:48) — Puede bypassearse con peticiones directas

**Verificaciones positivas:**
- HTTPS en producción ✓
- JWT en Authorization header (protege contra CSRF) ✓
- Logout limpia tokens ✓
- No tokens en URLs ✓
- Token refresh con cola previene race conditions ✓

**Recomendaciones no bloqueantes:**
- Implementar logging centralizado (Sentry) en lugar de console.log
- Mapear errores backend a mensajes user-friendly en frontend
- Considerar httpOnly cookies + refresh token rotation en el futuro

### Resultados consolidados

**Tarea 1 (Verificación endpoints):**
- Status: ✅ CUMPLE
- 8/9 endpoints funcionando (88.9%)
- Login y register operativos en producción

**Tarea 2 (Migración auth):**
- Status: ✅ SUCCESS
- Frontend ahora usa Django Auth directo
- 0% funcionalidad bloqueada por Supabase Auth

**Tarea 3 (Fix tachado):**
- Status: ✅ CUMPLE
- Tareas se tachan inmediatamente
- Deuda técnica identificada y documentada

### Deuda técnica identificada

1. **Prioridad MEDIA:** Corregir magic strings de tipos de columna ("todo", "in_progress", "testing") → valores backend correctos
2. **Prioridad MEDIA:** Crear archivo `constants/columns.ts` con tipos centralizados
3. **Prioridad BAJA:** Deshabilitar console.log en builds de producción (vite.config.ts)
4. **Prioridad BAJA:** Sanitizar mensajes de error en producción con diccionario de mensajes seguros
