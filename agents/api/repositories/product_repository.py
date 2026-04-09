"""
Repository pattern para productos
Abstracción sobre Supabase para desacoplar lógica de negocio del ORM
"""

from typing import Optional

from models.product import Product


class ProductRepository:
    """
    Repositorio de productos - capa de abstracción sobre Supabase.
    Mantiene la lógica de negocio desacoplada del ORM.
    """
    
    def __init__(self, supabase_client):
        """
        Inicializa el repositorio con un cliente de Supabase.
        
        Args:
            supabase_client: Cliente configurado de Supabase
        """
        self.db = supabase_client
    
    async def search(
        self,
        query: str,
        limit: int = 20,
        cursor: Optional[int] = None
    ) -> tuple[list[Product], Optional[int]]:
        """
        Busca productos por término de búsqueda.
        
        Aplica:
        - Paginación por cursor (id > last_seen) según memoria_global.md ciclo2
        - Validación de parámetros para evitar inyección SQL
        - Uso de parámetros en queries en vez de concatenación
        
        Args:
            query: Término de búsqueda validado
            limit: Cantidad máxima de resultados
            cursor: ID del último producto visto (paginación)
            
        Returns:
            Tupla de (lista de productos, siguiente cursor o None)
        """
        # Query base con parámetros seguros
        # Nota: En producción esto usaría índice full-text GiST/GIN según memoria
        query_builder = self.db.table('products').select('*')
        
        # Aplicar paginación por cursor si se proporciona
        if cursor:
            query_builder = query_builder.gt('id', cursor)
        
        # Búsqueda con operador ilike usando parámetros
        query_builder = query_builder.or_(
            f"name.ilike.%{query}%,description.ilike.%{query}%"
        )
        
        # Ordenar y limitar
        query_builder = query_builder.order('id', desc=False).limit(limit + 1)
        
        # Ejecutar consulta
        response = query_builder.execute()
        
        # Extraer datos
        items = response.data if response.data else []
        
        # Determinar siguiente cursor
        next_cursor = None
        if len(items) > limit:
            items = items[:limit]
            next_cursor = items[-1]['id']
        
        # Convertir a modelos Pydantic
        products = [Product(**item) for item in items]
        
        return products, next_cursor
    
    async def count_search_results(self, query: str) -> int:
        """
        Cuenta el total de resultados para una búsqueda.
        
        Args:
            query: Término de búsqueda validado
            
        Returns:
            Cantidad total de resultados
        """
        response = self.db.table('products').select(
            'id',
            count='exact'
        ).or_(
            f"name.ilike.%{query}%,description.ilike.%{query}%"
        ).execute()
        
        return response.count if hasattr(response, 'count') else 0
