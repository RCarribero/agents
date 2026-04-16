# Protocolo de Aprendizaje entre Agentes

Define el ciclo completo de retroalimentacion para que los agentes aprendan de errores pasados y no repitan fallos.

---

## Problema que resuelve

Sin este protocolo, los agentes repiten errores porque:
- Los rechazos de auditor/qa/red_team nunca se persisten como aprendizajes
- Los implementadores (backend/frontend/developer) no leen las notas de los verificadores
- Las lecciones quedan atrapadas en el historial de sesion y se pierden al cerrar

## Ciclo de aprendizaje

```
                              ┌──────────────────────────┐
                              │   memoria_global.md      │
                              │   (lecciones generales)  │
                              └────────┬─────────────────┘
                                       │ lee al inicio
                    ┌──────────────────▼──────────────────┐
                    │        orchestrator                   │
                    │ filtra learnings relevantes           │
                    │ los inyecta en context.learnings      │
                    └───┬──────────────────────────┬───────┘
                        │                          │
               context.learnings            context.learnings
               + auditor warnings           + qa gaps conocidos
                        │                          │
                ┌───────▼────────┐        ┌───────▼────────┐
                │  implementador  │        │  verificador    │
                │  (backend/FE)   │        │  (audit/qa/RT)  │
                │                 │        │                 │
                │ lee warnings    │        │ emite APRENDIZ. │
                │ antes de        │        │ en notes del    │
                │ implementar     │        │ director_report │
                └────────────────┘        └───────┬─────────┘
                                                  │
                                       ┌──────────▼──────────┐
                                       │  memory_curator      │
                                       │  extrae + clasifica  │
                                       │  + escribe           │
                                       └──────────────────────┘
```

## 1. Cuando se dispara la curacion

| Evento | Tipo de curacion | Que se extrae |
|---|---|---|
| Ciclo exitoso (post-devops) | `curacion parcial` | Decisiones de diseno, patrones que funcionaron |
| **Rechazo en Fase 3** (cualquier verificador) | `curacion de rechazo` | **ERROR** Motivo del rechazo + fix aplicado |
| **Reintento exitoso** (implementador corrigio) | `curacion de correccion` | Patron error-correccion completo |
| Escalacion a human | `curacion parcial` | Que bloqueo y por que |
| Cierre de sesion | `curacion completa` | Todo lo anterior consolidado |

La clave es que **los rechazos son la fuente mas valiosa de aprendizaje** y ahora siempre disparan curacion.

## 2. Formato de APRENDIZAJE en director_report

Cuando un agente detecta un error recurrente, un patron util o un antipatron, lo emite asi:

```
APRENDIZAJE: <tipo> | <descripcion concisa> | <contexto>
```

Tipos validos:
- `ERROR_RECURRENTE` -- error que ya se vio antes o que se espera recurrente
- `PATRON_UTIL` -- tecnica que funciono bien y deberia repetirse
- `ANTIPATRON` -- practica que causo problemas y debe evitarse
- `CONVENCION` -- regla del proyecto clarificada o establecida

Ejemplos reales:
```
APRENDIZAJE: ERROR_RECURRENTE | Endpoint PATCH sin validacion de membresia causa 400 en asignaciones | backend
APRENDIZAJE: ANTIPATRON | Console.log activo en produccion expone tokens | frontend
APRENDIZAJE: PATRON_UTIL | Paginacion por cursor > OFFSET en tablas grandes | backend
APRENDIZAJE: CONVENCION | Constantes centralizadas si >3 ocurrencias del mismo literal | frontend
```

## 3. Que lee cada agente antes de actuar

### Implementadores (backend, frontend, developer)

Antes de escribir codigo, leer:
1. `memoria_global.md` -- seccion "Errores a evitar" relevante al dominio
2. Su propia seccion `AUTONOMOUS_LEARNINGS`
3. **`context.learnings`** -- warnings inyectados por el orchestrator (ver seccion 4)

El implementador debe **verificar activamente** que su codigo no repite ningun error listado en estos 3 fuentes. Si detecta que esta a punto de cometer uno, corregir antes de entregar.

### Verificadores (auditor, qa, red_team)

Antes de verificar, leer:
1. `memoria_global.md` -- antipatrones conocidos (si reaparecen, severidad mayor)
2. Su propia seccion `AUTONOMOUS_LEARNINGS`
3. Si `retry_count > 0`: los rejection_details del intento anterior como checklist prioritaria

### Orchestrator

Antes de delegar:
1. Leer `memoria_global.md`
2. Leer AUTONOMOUS_LEARNINGS de los agentes que va a invocar
3. Filtrar las notas relevantes a la tarea actual
4. Inyectarlas en `context.learnings` del contrato de entrada

## 4. Inyeccion de learnings por el orchestrator

El orchestrator filtra las lecciones relevantes y las inyecta en el campo `context.learnings` de cada agente:

```json
{
  "context": {
    "learnings": [
      {
        "source": "auditor.AUTONOMOUS_LEARNINGS",
        "type": "ANTIPATRON",
        "lesson": "Console.log en produccion expone tokens",
        "relevance": "el cambio actual toca archivos frontend"
      },
      {
        "source": "memoria_global.md",
        "type": "ERROR_RECURRENTE",
        "lesson": "Validar input de busqueda siempre con parametros, nunca concatenar strings",
        "relevance": "la tarea implementa un endpoint de busqueda"
      }
    ]
  }
}
```

### Criterios de filtrado

Solo inyectar un learning si cumple AL MENOS UNO:
- Toca el mismo dominio que la tarea (backend/frontend/db/auth)
- Menciona el mismo tipo de operacion (busqueda, PATCH, drag&drop, migracion)
- Fue un rechazo en una tarea similar anterior en la misma sesion

**Maximo 5 learnings por agente** para no saturar el contexto.

## 5. Formato de AUTONOMOUS_LEARNINGS

Cada nota en la seccion AUTONOMOUS_LEARNINGS debe seguir este formato:

```markdown
- **[TIPO]** Descripcion concisa de la leccion. Contexto minimo si es necesario.
```

Tipos: `[ERROR]`, `[PATRON]`, `[ANTIPATRON]`, `[CONVENCION]`

Ejemplo real (auditor):
```markdown
<!-- AUTONOMOUS_LEARNINGS_START -->
## Notas operativas aprendidas
- **[ERROR]** Endpoints de busqueda sin parametros preparados = vector de inyeccion SQL critico.
- **[ERROR]** RLS faltante en tablas consultadas publicamente = hallazgo automatico de severidad Alta.
- **[ANTIPATRON]** Console.log activo en produccion puede exponer tokens y payloads sensibles.
- **[CONVENCION]** Token blacklist 401 en logout es comportamiento esperado de Django, NO es bug.
<!-- AUTONOMOUS_LEARNINGS_END -->
```

## 6. Reglas de curacion del memory_curator

### Curacion de rechazo (NUEVA)

Cuando se invoca tras un rechazo en Fase 3:

1. **Extraer** el `rejection_reason` y `rejection_details` del director_report del verificador
2. **Sintetizar** la leccion: que salio mal + como se corrigio (si hubo reintento exitoso)
3. **Clasificar** con los tipos definidos arriba
4. **Escribir** en AUTONOMOUS_LEARNINGS del agente que cometio el error Y del verificador que lo detecto
5. Si el patron es generalizable (pasa las 3 preguntas): promover a `memoria_global.md`

### Regla de deduplicacion

Antes de escribir cualquier nota, verificar:
- No existe ya una nota con el mismo concepto en AUTONOMOUS_LEARNINGS del agente
- No existe ya una entrada equivalente en `memoria_global.md`
- Si existe pero es mas vaga, reemplazar con la version mas precisa
- Si existe y es identica, descartar

### Regla de relevancia temporal

- Notas que no se han activado (no han prevenido un error) en 20 ciclos: mover a archivo
- Notas que han prevenido un error al menos 1 vez: mantener indefinidamente

## 7. Verificacion de que el sistema funciona

El ciclo de aprendizaje es funcional si:
- [ ] Tras un rechazo, memory_curator se invoca y escribe una nota
- [ ] En el siguiente ciclo similar, el orchestrator inyecta esa nota en context.learnings
- [ ] El implementador lee la nota y evita el error
- [ ] El verificador confirma que el error no se repitio
- [ ] Si el error se repite a pesar de la nota: escalar severidad

Un error que se repite 3+ veces CON nota existente en memoria es un **fallo critico del sistema de aprendizaje** y debe escalarse con tag `LEARNING_FAILURE` en session_log.
