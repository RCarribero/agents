---
name: "rag-index"
description: "Indexa memoria y contratos en el vector store del workspace con rag_indexer y resume el resultado"
agent: "agent"
---

Ejecuta el indexado RAG del repositorio y resume el resultado.

Reglas de ejecución:

- Usa este comando:
  - `python ./scripts/rag_indexer.py --all`

Comportamiento esperado:

- Ejecuta solo el indexador RAG.
- No modifiques archivos del workspace.
- Aclara si hubo chunks indexados, skips o errores.
- Si todo pasa, responde con una confirmación breve.
