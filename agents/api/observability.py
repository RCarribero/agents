"""
observability.py — Logging estructurado JSON para el sistema multi-agente v3.

Proporciona:
  - StructuredLogger: emite eventos JSON a stdout (consumibles por cualquier aggregator)
  - AgentMetrics: calcula métricas desde agent_events (Supabase) o desde logs locales
  - metrics_router: FastAPI router en /metrics

Uso:
    from api.observability import StructuredLogger, metrics_router

    app.include_router(metrics_router)
    logger = StructuredLogger("backend")
    logger.transition(task_id="t001", to_agent="auditor", status="SUCCESS", artifacts=[])
"""

from __future__ import annotations

import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Any

from fastapi import APIRouter

log = logging.getLogger("agents.observability")

# Configurar root logger para emitir JSON si LOG_FORMAT=json
def configure_json_logging() -> None:
    """Configura el root logger para emitir líneas JSON a stdout."""
    if os.getenv("LOG_FORMAT", "json") != "json":
        return
    handler = logging.StreamHandler()
    handler.setFormatter(_JsonFormatter())
    logging.root.handlers = [handler]
    logging.root.setLevel(logging.INFO)


class _JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        payload: dict[str, Any] = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        # Si el mensaje es ya un dict JSON, mergearlo
        try:
            parsed = json.loads(record.getMessage())
            if isinstance(parsed, dict):
                payload.update(parsed)
        except (json.JSONDecodeError, TypeError):
            pass
        return json.dumps(payload, ensure_ascii=False)


class StructuredLogger:
    """
    Emite eventos de transición de agente como JSON estructurado.
    También persiste en agent_events via MCP si AGENTS_API_URL está configurado.
    """

    def __init__(self, agent_name: str) -> None:
        self.agent = agent_name
        self._log = logging.getLogger(f"agents.{agent_name}")

    def transition(
        self,
        task_id: str,
        to_agent: str,
        status: str,
        artifacts: list[str] | None = None,
        notes: str = "",
        event_type: str = "AGENT_TRANSITION",
    ) -> None:
        event = {
            "event": "agent_transition",
            "event_type": event_type,
            "task_id": task_id,
            "from_agent": self.agent,
            "to_agent": to_agent,
            "status": status,
            "artifacts": artifacts or [],
            "notes": notes,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        self._log.info(json.dumps(event))
        self._persist_async(event)

    def phase_complete(self, task_id: str, phase: str, artifacts: list[str]) -> None:
        self.transition(
            task_id=task_id,
            to_agent="orchestrator",
            status="SUCCESS",
            artifacts=artifacts,
            notes=f"Fase completada: {phase}",
            event_type="PHASE_COMPLETE",
        )

    def escalation(self, task_id: str, reason: str) -> None:
        self.transition(
            task_id=task_id,
            to_agent="human",
            status="ESCALATE",
            notes=reason,
            event_type="ESCALATION",
        )

    def _persist_async(self, event: dict) -> None:
        """Persiste el evento vía MCP log_agent_event (fire-and-forget, no bloquea)."""
        import threading
        threading.Thread(target=self._persist_sync, args=(event,), daemon=True).start()

    def _persist_sync(self, event: dict) -> None:
        api_url = os.getenv("AGENTS_API_URL")
        api_key = os.getenv("AGENTS_API_KEY", "")
        if not api_url:
            return
        try:
            import httpx
            headers = {"Content-Type": "application/json"}
            if api_key:
                headers["Authorization"] = f"Bearer {api_key}"
            httpx.post(
                f"{api_url}/mcp/tools/call",
                json={
                    "name": "log_agent_event",
                    "arguments": {
                        "event_type": event.get("event_type", "AGENT_TRANSITION"),
                        "task_id": event["task_id"],
                        "from_agent": event["from_agent"],
                        "to_agent": event["to_agent"],
                        "status": event["status"],
                        "artifacts": event.get("artifacts", []),
                        "notes": event.get("notes", ""),
                    },
                },
                headers=headers,
                timeout=5.0,
            )
        except Exception:
            pass  # No propagar errores de observabilidad


# ---------------------------------------------------------------------------
# Métricas router
# ---------------------------------------------------------------------------

metrics_router = APIRouter(prefix="/metrics", tags=["Observability"])


@metrics_router.get("/agents", summary="Métricas de éxito por agente")
async def get_agent_metrics() -> dict:
    """
    Retorna métricas de éxito/rechazo por agente desde agent_events (Supabase).
    Si Supabase no está disponible, retorna estructura vacía con aviso.
    """
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_KEY")
    if not supabase_url or not supabase_key:
        return {"error": "Supabase no configurado", "metrics": []}

    from supabase import create_client
    client = create_client(supabase_url, supabase_key)
    result = client.rpc("get_agent_metrics").execute()
    return {"metrics": result.data or [], "timestamp": datetime.now(timezone.utc).isoformat()}


@metrics_router.get("/tasks/{task_id}", summary="Traza completa de un task_id")
async def get_task_trace(task_id: str) -> dict:
    """
    Retorna todos los eventos asociados a un task_id, ordenados cronológicamente.
    Permite reconstruir el flujo completo de un ciclo.
    """
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_KEY")
    if not supabase_url or not supabase_key:
        return {"error": "Supabase no configurado", "events": []}

    from supabase import create_client
    client = create_client(supabase_url, supabase_key)
    result = (
        client.table("agent_events")
        .select("*")
        .eq("task_id", task_id)
        .order("timestamp")
        .execute()
    )
    return {
        "task_id": task_id,
        "events": result.data or [],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@metrics_router.get("/summary", summary="Resumen del sistema")
async def get_system_summary() -> dict:
    """
    Resumen global: total eventos, agentes activos, últimas escalaciones.
    """
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_KEY")
    if not supabase_url or not supabase_key:
        return {"error": "Supabase no configurado"}

    from supabase import create_client
    client = create_client(supabase_url, supabase_key)

    total = client.table("agent_events").select("id", count="exact").execute()
    escalations = (
        client.table("agent_events")
        .select("*")
        .eq("event_type", "ESCALATION")
        .order("timestamp", desc=True)
        .limit(5)
        .execute()
    )
    metrics = client.from_("agent_metrics").select("*").execute()

    return {
        "total_events": total.count,
        "recent_escalations": escalations.data or [],
        "agent_metrics": metrics.data or [],
        "generated_at": datetime.now(timezone.utc).isoformat(),
    }
