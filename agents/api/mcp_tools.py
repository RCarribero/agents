"""
MCP Tools Layer — expone endpoints de agents/api como tools MCP.
Compatible con Model Context Protocol (MCP) spec v1.0.

Cada tool sigue el esquema:
  name: string
  description: string
  inputSchema: JSON Schema
  returns: JSON

Se monta en /mcp/tools sobre la app FastAPI principal.
"""

from __future__ import annotations

import os
import hashlib
import json
import logging
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel, Field

from models.product import ProductSearchParams
from repositories.product_repository import ProductRepository
from supabase_client import get_shared_supabase_client, is_supabase_configured

logger = logging.getLogger(__name__)

DEFAULT_SERVICE_NAME = "agents-api"
DEFAULT_SERVICE_VERSION = "3.1.0"
SERVICE_NAME = os.getenv("SERVICE_NAME", DEFAULT_SERVICE_NAME)
SERVICE_VERSION = os.getenv("SERVICE_VERSION", DEFAULT_SERVICE_VERSION)

router = APIRouter(prefix="/mcp", tags=["MCP"])


# ---------------------------------------------------------------------------
# Schemas de input/output canónicos
# ---------------------------------------------------------------------------

class MCPToolInput(BaseModel):
    name: str
    arguments: dict[str, Any] = {}


class MCPToolResult(BaseModel):
    tool: str
    success: bool
    result: Any
    error: str | None = None
    timestamp: str = Field(default_factory=lambda: datetime.now(timezone.utc).isoformat())


class MCPToolListResponse(BaseModel):
    tools: list[dict[str, Any]]


# ---------------------------------------------------------------------------
# Catálogo de tools disponibles
# ---------------------------------------------------------------------------

TOOL_CATALOG: list[dict[str, Any]] = [
    {
        "name": "health_check",
        "description": "Verifica que el servicio agents-api está operativo.",
        "inputSchema": {
            "type": "object",
            "properties": {},
            "required": []
        }
    },
    {
        "name": "search_products",
        "description": "Busca productos en Supabase por término de búsqueda. Retorna lista paginada.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Término de búsqueda (mínimo 2 caracteres)"
                },
                "limit": {
                    "type": "integer",
                    "description": "Número máximo de resultados (default 20, máx 100)",
                    "default": 20
                },
                "cursor": {
                    "type": "string",
                    "description": "ID del último item para paginación por cursor (opcional)"
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "embed_document",
        "description": "Genera embedding para un documento y lo guarda en agent_memory_vectors.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "content": {
                    "type": "string",
                    "description": "Contenido a embeber (máx 8192 tokens)"
                },
                "source": {
                    "type": "string",
                    "description": "Origen del documento (e.g. 'memoria_global.md', 'session_log.md')"
                },
                "metadata": {
                    "type": "object",
                    "description": "Metadatos adicionales (task_id, agent, etc.)",
                    "default": {}
                }
            },
            "required": ["content", "source"]
        }
    },
    {
        "name": "retrieve_context",
        "description": "Recupera los k documentos más relevantes del vector store para un query dado (RAG).",
        "inputSchema": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "Query de búsqueda semántica"
                },
                "k": {
                    "type": "integer",
                    "description": "Número de documentos a recuperar (default 5, máx 10)",
                    "default": 5
                },
                "source_filter": {
                    "type": "string",
                    "description": "Filtrar por fuente (opcional)"
                }
            },
            "required": ["query"]
        }
    },
    {
        "name": "log_agent_event",
        "description": "Registra un evento de transición de agente en el log estructurado.",
        "inputSchema": {
            "type": "object",
            "properties": {
                "event_type": {
                    "type": "string",
                    "enum": ["AGENT_TRANSITION", "EVAL_TRIGGER", "PHASE_COMPLETE", "ERROR", "ESCALATION"],
                    "description": "Tipo de evento"
                },
                "task_id": {
                    "type": "string",
                    "description": "ID de la tarea en curso"
                },
                "from_agent": {
                    "type": "string",
                    "description": "Agente emisor"
                },
                "to_agent": {
                    "type": "string",
                    "description": "Agente receptor"
                },
                "status": {
                    "type": "string",
                    "description": "Estado del evento (SUCCESS, REJECTED, ESCALATE...)"
                },
                "artifacts": {
                    "type": "array",
                    "items": {"type": "string"},
                    "description": "Artefactos generados en la transición",
                    "default": []
                },
                "notes": {
                    "type": "string",
                    "description": "Notas adicionales del evento",
                    "default": ""
                }
            },
            "required": ["event_type", "task_id", "from_agent", "to_agent", "status"]
        }
    }
]


# ---------------------------------------------------------------------------
# Endpoints MCP
# ---------------------------------------------------------------------------

@router.get("/tools", response_model=MCPToolListResponse, summary="Listar tools MCP disponibles")
async def list_tools() -> MCPToolListResponse:
    """Retorna el catálogo de tools MCP disponibles en agents-api."""
    return MCPToolListResponse(tools=TOOL_CATALOG)


@router.post("/tools/call", response_model=MCPToolResult, summary="Invocar un tool MCP")
async def call_tool(payload: MCPToolInput) -> MCPToolResult:
    """
    Dispatcher central de tools MCP.
    Valida el nombre del tool y delega a la implementación correspondiente.
    """
    handler = _TOOL_HANDLERS.get(payload.name)
    if handler is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Tool '{payload.name}' no encontrado. Tools disponibles: {list(_TOOL_HANDLERS.keys())}"
        )
    try:
        result = await handler(payload.arguments)
        return MCPToolResult(tool=payload.name, success=True, result=result)
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("Error ejecutando tool '%s'", payload.name)
        return MCPToolResult(tool=payload.name, success=False, result=None, error=str(exc))


# ---------------------------------------------------------------------------
# Implementaciones de tools
# ---------------------------------------------------------------------------

async def _tool_health_check(_args: dict) -> dict:
    return {
        "status": "healthy",
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "service": SERVICE_NAME,
        "version": SERVICE_VERSION
    }


async def _tool_search_products(args: dict) -> dict:
    """Delega a la lógica existente de búsqueda de productos."""
    if not is_supabase_configured():
        raise HTTPException(status_code=503, detail="Supabase no configurado")

    repo = ProductRepository(get_shared_supabase_client())
    params = ProductSearchParams(
        query=args["query"],
        limit=args.get("limit", 20),
        cursor=args.get("cursor")
    )
    products, next_cursor = await repo.search(
        query=params.query,
        limit=params.limit,
        cursor=params.cursor,
    )
    total = await repo.count_search_results(params.query)

    return {
        "products": [product.model_dump(mode="json") for product in products],
        "next_cursor": next_cursor,
        "total": total,
    }


async def _tool_embed_document(args: dict) -> dict:
    """
    Genera embedding para un documento y lo persiste en agent_memory_vectors.
    Usa openai text-embedding-3-small (512 dims) via openai SDK.
    Si OPENAI_API_KEY no está disponible, usa hash SHA-256 como embedding simulado.
    """
    content: str = args["content"]
    source: str = args["source"]
    metadata: dict = args.get("metadata", {})

    # Limitar a 8192 chars para no sobresaturar el modelo
    content_truncated = content[:8192]

    embedding: list[float]
    model_used: str

    openai_key = os.getenv("OPENAI_API_KEY")
    if openai_key:
        try:
            import openai
            client_ai = openai.AsyncOpenAI(api_key=openai_key)
            response = await client_ai.embeddings.create(
                model="text-embedding-3-small",
                input=content_truncated,
                dimensions=512
            )
            embedding = response.data[0].embedding
            model_used = "text-embedding-3-small"
        except Exception as exc:
            logger.warning("OpenAI embedding fallido: %s — usando hash simulado", exc)
            embedding = _hash_embedding(content_truncated)
            model_used = "sha256-simulated"
    else:
        embedding = _hash_embedding(content_truncated)
        model_used = "sha256-simulated"

    doc_id = hashlib.sha256(f"{source}:{content_truncated[:256]}".encode()).hexdigest()[:32]

    if is_supabase_configured():
        client = get_shared_supabase_client()
        client.table("agent_memory_vectors").upsert({
            "id": doc_id,
            "content": content_truncated,
            "embedding": embedding,
            "source": source,
            "metadata": json.dumps(metadata),
            "timestamp": datetime.now(timezone.utc).isoformat()
        }).execute()

    return {
        "id": doc_id,
        "source": source,
        "model": model_used,
        "dimensions": len(embedding),
        "persisted": is_supabase_configured()
    }


async def _tool_retrieve_context(args: dict) -> dict:
    """
    Recupera documentos relevantes usando cosine similarity sobre agent_memory_vectors.
    Requiere pgvector extension en Supabase.
    """
    query: str = args["query"]
    k: int = min(args.get("k", 5), 10)
    source_filter: str | None = args.get("source_filter")

    if not is_supabase_configured():
        return {"results": [], "warning": "Supabase no configurado — RAG no disponible"}

    # Generar embedding del query
    query_embedding = await _get_embedding(query)

    client = get_shared_supabase_client()

    # Usar función RPC match_documents (definida en la migración RAG)
    rpc_args: dict = {"query_embedding": query_embedding, "match_count": k}
    if source_filter:
        rpc_args["source_filter"] = source_filter

    response = client.rpc("match_agent_documents", rpc_args).execute()
    results = response.data or []

    return {
        "query": query,
        "k": k,
        "results": [
            {
                "id": r["id"],
                "content": r["content"],
                "source": r["source"],
                "similarity": r.get("similarity", 0),
                "timestamp": r.get("timestamp")
            }
            for r in results
        ]
    }


async def _tool_log_agent_event(args: dict) -> dict:
    """Persiste un evento de transición en la tabla agent_events (observabilidad)."""
    event = {
        "event_type": args["event_type"],
        "task_id": args["task_id"],
        "from_agent": args["from_agent"],
        "to_agent": args["to_agent"],
        "status": args["status"],
        "artifacts": json.dumps(args.get("artifacts", [])),
        "notes": args.get("notes", ""),
        "timestamp": datetime.now(timezone.utc).isoformat()
    }

    if is_supabase_configured():
        client = get_shared_supabase_client()
        client.table("agent_events").insert(event).execute()

    # También emitir como log estructurado JSON (observabilidad local)
    logger.info(json.dumps({"event": "agent_transition", **event}))

    return {"logged": True, "event_type": args["event_type"], "task_id": args["task_id"]}


# ---------------------------------------------------------------------------
# Helpers privados
# ---------------------------------------------------------------------------

def _hash_embedding(text: str) -> list[float]:
    """
    Genera un embedding simulado usando SHA-256.
    Produce 512 floats en rango [0, 1] — solo para dev/fallback.
    NO usar en producción como embedding real.
    """
    digest = hashlib.sha256(text.encode()).digest()
    # Repetir el digest para llegar a 512 dimensiones
    repeated = (digest * ((512 // len(digest)) + 1))[:512]
    return [b / 255.0 for b in repeated]


async def _get_embedding(text: str) -> list[float]:
    """Genera embedding para un texto corto (query)."""
    openai_key = os.getenv("OPENAI_API_KEY")
    if openai_key:
        try:
            import openai
            client_ai = openai.AsyncOpenAI(api_key=openai_key)
            response = await client_ai.embeddings.create(
                model="text-embedding-3-small",
                input=text[:1024],
                dimensions=512
            )
            return response.data[0].embedding
        except Exception:
            pass
    return _hash_embedding(text)


# Dispatch table
_TOOL_HANDLERS = {
    "health_check": _tool_health_check,
    "search_products": _tool_search_products,
    "embed_document": _tool_embed_document,
    "retrieve_context": _tool_retrieve_context,
    "log_agent_event": _tool_log_agent_event,
}
