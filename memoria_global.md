# Memoria Global del Sistema de Agentes

Historial de lecciones aprendidas durante sesiones de trabajo. Consulta este archivo antes de cada implementación para evitar errores conocidos y respetar convenciones establecidas.

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
