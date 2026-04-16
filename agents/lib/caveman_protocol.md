# Protocolo Caveman - Compresion de tokens inter-agente

Modo por defecto: **ULTRA**. Aplica a toda comunicacion entre agentes y al usuario.

## Que se comprime

Solo los **campos de texto libre** en director_report y agent_report:
- `summary`
- `rejection_reason`
- `rejection_details[].issue` y `rejection_details[].fix`
- `missing_cases[].caso`, `missing_cases[].esperado`, `missing_cases[].encontrado`
- `vulnerabilities[].description`
- `notes`
- `changes`
- `issues`
- Respuestas visibles al usuario

## Que NUNCA se comprime

Los campos estructurales del contrato son **intocables**:
- `task_id`, `status`, `veredicto`, `verification_cycle`
- `branch_name`, `verified_files`, `verified_digest`
- `risk_level`, `test_status`, `next_agent`, `escalate_to`
- `task_state` (JSON completo)
- `learnings[]` (estructura completa)
- Bloques de codigo
- Rutas de archivos
- Valores de configuracion
- Hashes y digests

## Reglas ULTRA (defecto)

1. **Fragmentos, no frases.** `[cosa] [accion] [razon]. [siguiente]`
2. **Abreviar siempre:** DB, auth, config, req, res, fn, impl, dep, env, var, param, err, msg, val, middleware→mw, endpoint→ep, migration→migr, validation→val, component→comp, serializer→ser
3. **Sin articulos** (el/la/un/una/los/las/a/an/the)
4. **Sin filler** (solo/realmente/basicamente/simplemente/correctamente/exitosamente/just/really/basically/actually)
5. **Sin cortesia** (claro/por supuesto/con gusto/sure/certainly/happy to)
6. **Sin hedging** (probablemente/quizas/parece que/podria ser/likely/maybe/seems)
7. **Flechas para causalidad:** `X → Y` en vez de "X causa Y" o "X porque Y"
8. **Una palabra cuando basta una.**
9. **Sin preambulos ni resumen al final.** Ir directo al punto.
10. **Codigo sin cambios.** Los bloques de codigo se escriben normal, sin comprimir.

## Excepciones de claridad (Auto-Clarity)

Suspender caveman temporalmente en:
- Warnings de seguridad criticos (escalar con lenguaje claro)
- Confirmaciones de acciones irreversibles (DELETE, DROP, rm -rf)
- Instrucciones multi-paso donde el orden importa y fragmentos causan ambiguedad
- Cuando el usuario pide aclaracion o repite pregunta

Reanudar caveman inmediatamente despues del fragmento claro.

## Ejemplos

### summary en director_report

Antes (42 tokens):
```
summary: "Se ha completado exitosamente la auditoría de seguridad del módulo de autenticación. Se encontraron 2 hallazgos de severidad media que no bloquean el despliegue."
```

Ultra (14 tokens):
```
summary: "Auth module audit done. 2 medium findings, non-blocking."
```

### rejection_reason

Antes (28 tokens):
```
rejection_reason: "El endpoint de PATCH para actualizar asignaciones no valida correctamente la membresía del usuario al proyecto antes de aplicar el cambio."
```

Ultra (12 tokens):
```
rejection_reason: "PATCH asignaciones: sin val membresia usuario→proyecto."
```

### missing_cases en QA

Antes:
```
missing_cases:
  - caso: "Verificar que un usuario que no pertenece al proyecto no puede ser asignado a una tarea"
    esperado: "La UI debe bloquear la selección de usuarios que no son miembros del proyecto"
    encontrado: "La UI permite seleccionar cualquier usuario del sistema sin filtrar por membresía"
```

Ultra:
```
missing_cases:
  - caso: "Asignar usuario no-miembro a tarea"
    esperado: "UI filtra por membresia proyecto"
    encontrado: "UI muestra todos los usuarios sin filtro"
```

## Referencia por agente

Cada agente incluye en sus reglas:
```
0z. **Caveman ULTRA activo.** Comprimir campos de texto libre segun [`lib/caveman_protocol.md`](lib/caveman_protocol.md). Campos estructurales intactos. Codigo intacto.
```
