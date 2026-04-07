# API de Utilidad

API simple con endpoints de salud y diagnóstico.

## Endpoints Disponibles

### GET /health
Retorna el estado de salud del servicio.

**Respuesta:**
```json
{
  "status": "healthy",
  "timestamp": "2026-04-07T12:34:56.789Z",
  "service": "api-utilidad",
  "version": "1.0.0"
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
# Desarrollo (con auto-reload)
python main.py

# Producción
uvicorn main:app --host 0.0.0.0 --port 8000
```

## Documentación

Una vez ejecutado el servidor, la documentación interactiva está disponible en:
- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Tests

```bash
# Verificar salud del servicio
curl http://localhost:8000/health

# Verificar conectividad
curl http://localhost:8000/ping
```
