#!/usr/bin/env python3
"""
rag_indexer.py — Indexa documentos de memoria del sistema al vector store.

Uso:
    python rag_indexer.py [--source FUENTE] [--all]

Fuentes soportadas:
    --all                   Indexa todas las fuentes conocidas
    --source memoria        agents/memoria_global.md
    --source session_log    session_log.md
    --source agents         Todos los .agent.md (sección AUTONOMOUS_LEARNINGS)

Variables de entorno requeridas:
    AGENTS_API_URL   URL de la agents-api (default: http://localhost:8000)
    AGENTS_API_KEY   API key (opcional si sin auth)

Variables opcionales:
    OPENAI_API_KEY   Si presente, usa embeddings reales (text-embedding-3-small)
                     Si ausente, usa embeddings simulados (SHA-256)
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import time
from pathlib import Path

import httpx

SCRIPT_DIR = Path(__file__).parent
REPO_ROOT = SCRIPT_DIR.parent  # agents/api/../ = agents/

AGENTS_API_URL = os.getenv("AGENTS_API_URL", "http://localhost:8000")
AGENTS_API_KEY = os.getenv("AGENTS_API_KEY", "")

SOURCES: dict[str, list[Path]] = {
    "memoria": [REPO_ROOT / "memoria_global.md"],
    "session_log": [REPO_ROOT.parent / "session_log.md"],
    "agents": sorted(REPO_ROOT.glob("*.agent.md")),
}


def get_headers() -> dict[str, str]:
    headers: dict[str, str] = {"Content-Type": "application/json"}
    if AGENTS_API_KEY:
        headers["Authorization"] = f"Bearer {AGENTS_API_KEY}"
    return headers


def chunk_text(text: str, max_chars: int = 2000, overlap: int = 200) -> list[str]:
    """Divide texto en chunks con overlap para preservar contexto."""
    chunks: list[str] = []
    start = 0
    while start < len(text):
        end = min(start + max_chars, len(text))
        # Retroceder al último salto de párrafo para no cortar en medio
        if end < len(text):
            last_break = text.rfind("\n\n", start, end)
            if last_break > start + overlap:
                end = last_break
        chunks.append(text[start:end].strip())
        start = end - overlap if end < len(text) else len(text)
    return [c for c in chunks if len(c) > 50]


def extract_learnings(agent_md: str) -> str:
    """Extrae solo la sección AUTONOMOUS_LEARNINGS del archivo .agent.md."""
    match = re.search(
        r"<!-- AUTONOMOUS_LEARNINGS_START -->(.*?)<!-- AUTONOMOUS_LEARNINGS_END -->",
        agent_md,
        re.DOTALL,
    )
    return match.group(1).strip() if match else ""


def embed_document(content: str, source: str, metadata: dict) -> dict:
    """Llama a /mcp/tools/call con tool embed_document."""
    with httpx.Client(timeout=30) as client:
        resp = client.post(
            f"{AGENTS_API_URL}/mcp/tools/call",
            json={
                "name": "embed_document",
                "arguments": {"content": content, "source": source, "metadata": metadata},
            },
            headers=get_headers(),
        )
        resp.raise_for_status()
        return resp.json()


def index_source(source_key: str) -> tuple[int, int]:
    """Indexa todos los documentos de una fuente. Retorna (ok, errores)."""
    paths = SOURCES.get(source_key, [])
    ok = errors = 0

    for path in paths:
        if not path.exists():
            print(f"  SKIP {path} (no existe)")
            continue

        raw = path.read_text(encoding="utf-8", errors="replace")

        # Para agentes: solo indexar AUTONOMOUS_LEARNINGS
        if source_key == "agents":
            content = extract_learnings(raw)
            if not content:
                print(f"  SKIP {path.name} (sin AUTONOMOUS_LEARNINGS)")
                continue
            chunks = [content]
        else:
            chunks = chunk_text(raw)

        print(f"  Indexando {path.name} → {len(chunks)} chunk(s)")

        for i, chunk in enumerate(chunks):
            try:
                result = embed_document(
                    content=chunk,
                    source=str(path.name),
                    metadata={"chunk": i, "total_chunks": len(chunks), "path": str(path)},
                )
                if result.get("success"):
                    ok += 1
                else:
                    print(f"    ERROR chunk {i}: {result.get('error')}")
                    errors += 1
                # Throttle para no saturar la API
                time.sleep(0.1)
            except Exception as exc:
                print(f"    ERROR chunk {i}: {exc}")
                errors += 1

    return ok, errors


def main() -> None:
    parser = argparse.ArgumentParser(description="Indexa documentos de memoria al vector store")
    parser.add_argument("--all", action="store_true", help="Indexar todas las fuentes")
    parser.add_argument(
        "--source",
        choices=list(SOURCES.keys()),
        help="Fuente específica a indexar",
    )
    args = parser.parse_args()

    if not args.all and not args.source:
        parser.print_help()
        sys.exit(1)

    sources_to_index = list(SOURCES.keys()) if args.all else [args.source]

    print(f"=== rag_indexer.py — agents-api: {AGENTS_API_URL} ===\n")

    total_ok = total_errors = 0
    for source_key in sources_to_index:
        print(f"[{source_key}]")
        ok, errors = index_source(source_key)
        total_ok += ok
        total_errors += errors
        print(f"  → {ok} chunks indexados, {errors} errores\n")

    print(f"Totales: {total_ok} OK, {total_errors} errores")
    sys.exit(1 if total_errors > 0 else 0)


if __name__ == "__main__":
    main()
