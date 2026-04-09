---
applyTo: "**"
---

# Instrucciones de Stack Override

Estas instrucciones aplican a todos los agentes y gestionan los overrides de configuración de proyecto.

## Comportamiento de override

- Si existe `.copilot/overrides.md` en el proyecto activo: **léelo antes de actuar**.
- Las instrucciones del override tienen **precedencia** sobre las instrucciones globales (`global.instructions.md`) en lo relativo a convenciones de proyecto, comandos de build/test/lint, y decisiones de arquitectura específicas.
- **Excepción:** las reglas de seguridad definidas en `readonly.instructions.md` **no pueden ser anuladas** por ningún override. Los agentes de solo lectura permanecen de solo lectura independientemente del override.

## Trazabilidad

En el campo `summary` de tu `<director_report>`, documenta qué override se aplicó (ruta del archivo y regla específica) siempre que un override haya influido en tu comportamiento o decisiones.

## Si no existe override

Si `.copilot/overrides.md` no existe, continúa con las instrucciones globales sin interrumpir el flujo. No falles ni escales por la ausencia del archivo.
