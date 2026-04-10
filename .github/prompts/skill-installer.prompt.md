---
mode: agent
description: Detecta el stack del proyecto activo, ejecuta autoskills y construye el skill_context. Invocar manualmente antes de una sesión de trabajo nueva.
---

# Skill Installer — Detección de Stack y Contexto de Skills

Detecta el stack del proyecto activo, instala los skills relevantes con `autoskills` y construye el `skill_context` que los agentes consumirán en la sesión.

## Proceso

### 1. Verifica cache
Lee `skills_cache.md` en la raíz del workspace. Si existe y tiene menos de 24 horas, salta directamente al paso 4.

### 2. Detecta el stack
En orden de preferencia:
- Lee `stack.md` (o fallback `.copilot/stack.md`)
- Detecta desde manifests: `pubspec.yaml` → Flutter/Dart · `package.json` → Node/React/Next · `requirements.txt`/`pyproject.toml` → Python · `go.mod` → Go
- Si no hay manifests, anota `stack: unknown`

### 3. Ejecuta autoskills
```bash
npx --yes autoskills --yes
```
- Si el comando tiene éxito anota `autoskills_status: ok`.
- Si `npx` no está disponible o el comando falla, anota `autoskills_status: unavailable` / `error` y continúa — **nunca bloquea**.

### 4. Lee los skills instalados
Lee la carpeta de skills (ruta en `config.json` → campo `skills_dir`, o `~/.agents/skills/` por defecto) y lista los disponibles.

### 5. Construye skill_context
```json
{
  "stack": ["<stack detectado>"],
  "skills_available": ["<lista de skills encontrados>"],
  "skills_active": ["<skills que aplican al stack>"],
  "cache_timestamp": "<YYYY-MM-DD HH:MM>",
  "autoskills_status": "ok | unavailable | error"
}
```

### 6. Escribe el cache
Actualiza `skills_cache.md` en la raíz del workspace con el `skill_context` resultante.

## Output

Muestra al finalizar:
- Stack detectado
- Resultado de `npx --yes autoskills --yes` (stdout/stderr relevante)
- Skills disponibles y activos
- `skill_context` como JSON copiable

## Notas

- **Nunca bloquea**: cualquier error produce `skill_context: null` y el sistema continúa.
- Si detectas un stack no soportado o un skill útil que falta, anótalo con prefijo `APRENDIZAJE:`.
