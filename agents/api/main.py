"""
Agents API — v3.1
Endpoints de salud, diagnóstico y MCP tools para el sistema multi-agente.
"""

import logging
import os
from datetime import datetime, timezone

from fastapi import FastAPI, status, HTTPException, Depends
from pydantic import BaseModel
from supabase import Client
import uvicorn
from dotenv import load_dotenv

from models.product import ProductSearchParams, ProductSearchResponse
from repositories.product_repository import ProductRepository
from mcp_tools import router as mcp_router
from observability import configure_json_logging, metrics_router
from supabase_client import SupabaseConfigurationError, get_shared_supabase_client


DEFAULT_SERVICE_NAME = "agents-api"
DEFAULT_SERVICE_VERSION = "3.1.0"
PRODUCT_SEARCH_ERROR_MESSAGE = "No se pudo completar la búsqueda de productos."

# Cargar variables de entorno y configurar logging estructurado
load_dotenv()
configure_json_logging()

SERVICE_NAME = os.getenv("SERVICE_NAME", DEFAULT_SERVICE_NAME)
SERVICE_VERSION = os.getenv("SERVICE_VERSION", DEFAULT_SERVICE_VERSION)
logger = logging.getLogger("agents.api.main")


# Modelos de respuesta
class HealthResponse(BaseModel):
    """Modelo de respuesta para el endpoint de salud"""
    status: str
    timestamp: str
    service: str
    version: str


class PingResponse(BaseModel):
    """Modelo de respuesta para el endpoint de ping"""
    message: str
    timestamp: str


# Configuración de la aplicación
app = FastAPI(
    title="Agents API",
    description="API del sistema multi-agente v3. Incluye health checks, búsqueda de productos y MCP tools para RAG y observabilidad.",
    version=SERVICE_VERSION
)

# Montar router MCP y observabilidad
app.include_router(mcp_router)
app.include_router(metrics_router)


# Dependency injection para Supabase client
def get_supabase_client() -> Client:
    """
    Retorna un cliente de Supabase configurado.
    Usa variables de entorno SUPABASE_URL y SUPABASE_KEY.
    """
    try:
        return get_shared_supabase_client()
    except SupabaseConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc)
        ) from exc


def get_product_repository(
    supabase_client: Client = Depends(get_supabase_client)
) -> ProductRepository:
    """
    Dependency injection para ProductRepository.
    Aplica patrón Repository como capa de abstracción según buenas prácticas.
    """
    return ProductRepository(supabase_client)


@app.get("/health", 
         response_model=HealthResponse,
         status_code=status.HTTP_200_OK,
         tags=["Utilidad"],
         summary="Verificar estado del servicio")
async def health_check() -> HealthResponse:
    """
    Endpoint de salud que retorna el estado del servicio.
    
    Retorna:
        HealthResponse con status, timestamp, nombre del servicio y versión
    """
    return HealthResponse(
        status="healthy",
        timestamp=datetime.now(timezone.utc).isoformat(),
        service=SERVICE_NAME,
        version=SERVICE_VERSION
    )


@app.get("/ping",
         response_model=PingResponse,
         status_code=status.HTTP_200_OK,
         tags=["Utilidad"],
         summary="Verificar conectividad")
async def ping() -> PingResponse:
    """
    Endpoint simple de ping para verificar que el servicio responde.
    
    Retorna:
        PingResponse con mensaje de confirmación y timestamp
    """
    return PingResponse(
        message="pong",
        timestamp=datetime.now(timezone.utc).isoformat()
    )


@app.get("/",
         status_code=status.HTTP_200_OK,
         tags=["Utilidad"],
         summary="Endpoint raíz")
async def root() -> dict:
    """
    Endpoint raíz con información básica de la API.
    
    Retorna:
        Diccionario con información del servicio y endpoints disponibles
    """
    return {
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION,
        "endpoints": {
            "health": "/health",
            "ping": "/ping",
            "products_search": "/products/search",
            "docs": "/docs",
            "redoc": "/redoc"
        }
    }


@app.get("/products/search",
         response_model=ProductSearchResponse,
         status_code=status.HTTP_200_OK,
         tags=["Productos"],
         summary="Buscar productos")
async def search_products(
    params: ProductSearchParams = Depends(),
    repository: ProductRepository = Depends(get_product_repository)
) -> ProductSearchResponse:
    """
    Busca productos por término de búsqueda.
    
    Implementación:
    - Usa patrón Repository como capa de abstracción sobre Supabase
    - Validación de input según memoria_global.md (ciclo2-busqueda-endpoint)
    - Paginación por cursor (id > last_seen) en vez de OFFSET
    - Parámetros en queries para prevenir inyección SQL
    
    Args:
        params: Parámetros de búsqueda validados por Pydantic
        repository: Repositorio inyectado con lógica de negocio
        
    Returns:
        ProductSearchResponse con lista de productos y cursor de paginación
    """
    try:
        # Delegar lógica al repositorio (separación de concerns)
        products, next_cursor = await repository.search(
            query=params.query,
            limit=params.limit,
            cursor=params.cursor
        )
        
        # Obtener total para metadata de respuesta
        total = await repository.count_search_results(params.query)
        
        return ProductSearchResponse(
            products=products,
            next_cursor=next_cursor,
            total=total
        )
    
    except Exception:
        logger.exception("Product search failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=PRODUCT_SEARCH_ERROR_MESSAGE
        )


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )
