"""
API de Utilidad Simple
Endpoints básicos de salud y diagnóstico
"""

import os
from datetime import datetime
from fastapi import FastAPI, status, HTTPException, Depends
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import uvicorn
from supabase import create_client, Client
from dotenv import load_dotenv

from api.models.product import ProductSearchParams, ProductSearchResponse
from api.repositories.product_repository import ProductRepository

# Cargar variables de entorno
load_dotenv()


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
    title="API de Utilidad",
    description="Endpoints de salud y diagnóstico",
    version="1.0.0"
)


# Dependency injection para Supabase client
def get_supabase_client() -> Client:
    """
    Retorna un cliente de Supabase configurado.
    Usa variables de entorno SUPABASE_URL y SUPABASE_KEY.
    """
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")
    
    if not url or not key:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Supabase no configurado. Variables SUPABASE_URL y SUPABASE_KEY requeridas."
        )
    
    return create_client(url, key)


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
        timestamp=datetime.utcnow().isoformat(),
        service="api-utilidad",
        version="1.0.0"
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
        timestamp=datetime.utcnow().isoformat()
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
        "service": "API de Utilidad",
        "version": "1.0.0",
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
    
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Error en búsqueda de productos: {str(e)}"
        )


if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True
    )
