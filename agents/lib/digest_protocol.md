# Protocolo de Digest Verificado

Protocolo estándar para computar `verified_digest` sobre un conjunto de archivos. Aplicable a: `auditor`, `qa`, `red_team` y `devops`.

---

## Algoritmo

1. Tomar la lista de archivos de `context.files` (o `context.verified_files` para devops)
2. **Excluir** `session_log.md` — es un `audit_trail_artifact` fuera del scope del digest
3. Para cada archivo restante: leer el contenido actual en disco
4. Calcular el hash SHA-256 de cada contenido
5. Ordenar los hashes alfabéticamente por ruta del archivo
6. Concatenar todos los hashes ordenados en un único string
7. El `verified_digest` es el SHA-256 de esa concatenación

## Regla de comparación

**Si `context.verified_digest` fue provisto explícitamente** por el orchestrator:

- Recomputar el digest independientemente usando el algoritmo arriba
- **Si coincide:** continuar con la operación normal del agente
- **Si NO coincide:** emitir rechazo inmediato por `digest_mismatch`:
  - No emitir hallazgos, gaps funcionales ni vulnerabilidades del código
  - Solo emitir el rechazo por integridad con el motivo `"digest_mismatch — artifacts modificados entre implementación y verificación"`
  - El veredicto específico del agente en caso de mismatch:
    - `auditor`: `status: REJECTED`, `veredicto: RECHAZADO`
    - `qa`: `status: REJECTED`, `veredicto: NO CUMPLE`, `test_status: NOT_APPLICABLE`
    - `red_team`: `status: ESCALATE`, `veredicto: NO EVALUADO`

**Si `context.verified_digest` NO fue provisto:**
- Continuar con la operación normal del agente
- Emitir el digest recomputado como `verified_digest` de salida

## Notas

- Cada agente recomputa el digest de forma **independiente** — no hereda el hash del contrato de entrada
- `devops` verifica adicionalmente que los tres digests de los reportes de Fase 3 coincidan entre sí
- `devops` recomputa una tercera vez sobre el snapshot stageado (no el working tree) antes del commit
