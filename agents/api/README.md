# Agents API

API auxiliar del sistema multi-agente. Expone health checks, búsqueda de productos y tools MCP para observabilidad y RAG.

**Requisito:** Python 3.13+

## Endpoints Disponibles

### GET /health
Retorna el estado de salud del servicio.

**Respuesta:**
```json
{
  "status": "healthy",
  "timestamp": "2026-04-07T12:34:56.789Z",
  "service": "agents-api",
  "version": "3.1.0"
}
```

### GET /ping
Endpoint simple para verificar conectividad.

**Respuesta:**
```json
{
  "message": "pong",
  "timestamp": "2026-04-07T12:34:56.789Z"
}
```

### GET /
Endpoint raíz con información de la API.

## Instalación

```bash
# Entrar al subproyecto de API
cd agents/api

# Crear entorno virtual
python -m venv venv

# Activar entorno virtual
# Windows:
venv\Scripts\activate
# Linux/Mac:
source venv/bin/activate

# Instalar dependencias
pip install -r requirements.txt
```

## Ejecución

```bash
# Desde agents/api

# Desarrollo (con auto-reload)
python main.py

# Producción
uvicorn main:app --host 0.0.0.0 --port 8000
```

Desde la raíz del repositorio, los scripts `scripts/run-tests/run-tests.sh` y `scripts/run-lint/run-lint.sh` detectan automáticamente este subproyecto.

## Documentación

Una vez ejecutado el servidor, la documentación interactiva está disponible en:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Tests

```bash
# Desde la raíz del repositorio
./scripts/run-tests/run-tests.sh . --json
./scripts/run-lint/run-lint.sh . --json

# Verificar salud del servicio
curl http://localhost:8000/health

# Verificar conectividad
curl http://localhost:8000/ping
```
