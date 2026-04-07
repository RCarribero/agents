"""
Modelos de datos para productos
"""

from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


class Product(BaseModel):
    """Modelo de producto"""
    id: int
    name: str
    description: Optional[str] = None
    price: float
    created_at: datetime
    updated_at: datetime


class ProductSearchParams(BaseModel):
    """Parámetros de búsqueda de productos"""
    query: str = Field(..., min_length=1, max_length=200, description="Término de búsqueda")
    limit: int = Field(default=20, ge=1, le=100, description="Cantidad de resultados")
    cursor: Optional[int] = Field(default=None, ge=1, description="ID del último producto visto para paginación")


class ProductSearchResponse(BaseModel):
    """Respuesta de búsqueda de productos"""
    products: list[Product]
    next_cursor: Optional[int] = None
    total: int
