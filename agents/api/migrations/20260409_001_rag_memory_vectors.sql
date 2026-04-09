-- Migration: RAG system — agent_memory_vectors + agent_events
-- Idempotente: usa IF NOT EXISTS en todos los objetos
-- Requiere: pgvector extension en Supabase

-- 1. Activar pgvector
CREATE EXTENSION IF NOT EXISTS vector;

-- 2. Tabla de vectores de memoria
CREATE TABLE IF NOT EXISTS agent_memory_vectors (
    id          TEXT        PRIMARY KEY,
    content     TEXT        NOT NULL,
    embedding   vector(512) NOT NULL,
    source      TEXT        NOT NULL,
    metadata    JSONB       NOT NULL DEFAULT '{}',
    timestamp   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Índice HNSW para búsqueda de vecinos aproximada (pgvector ≥ 0.5)
CREATE INDEX IF NOT EXISTS idx_agent_memory_vectors_embedding
    ON agent_memory_vectors
    USING hnsw (embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);

-- Índice por fuente para filtrado eficiente
CREATE INDEX IF NOT EXISTS idx_agent_memory_vectors_source
    ON agent_memory_vectors (source);

-- 3. Función de búsqueda semántica
CREATE OR REPLACE FUNCTION match_agent_documents(
    query_embedding vector(512),
    match_count     INT      DEFAULT 5,
    source_filter   TEXT     DEFAULT NULL
)
RETURNS TABLE (
    id          TEXT,
    content     TEXT,
    source      TEXT,
    metadata    JSONB,
    timestamp   TIMESTAMPTZ,
    similarity  FLOAT
)
LANGUAGE sql STABLE
AS $$
    SELECT
        amv.id,
        amv.content,
        amv.source,
        amv.metadata,
        amv.timestamp,
        1 - (amv.embedding <=> query_embedding) AS similarity
    FROM agent_memory_vectors amv
    WHERE
        source_filter IS NULL
        OR amv.source = source_filter
    ORDER BY amv.embedding <=> query_embedding
    LIMIT match_count;
$$;

-- 4. Tabla de eventos de agente (observabilidad)
CREATE TABLE IF NOT EXISTS agent_events (
    id          BIGSERIAL   PRIMARY KEY,
    event_type  TEXT        NOT NULL
                CHECK (event_type IN (
                    'AGENT_TRANSITION',
                    'EVAL_TRIGGER',
                    'PHASE_COMPLETE',
                    'ERROR',
                    'ESCALATION'
                )),
    task_id     TEXT        NOT NULL,
    from_agent  TEXT        NOT NULL,
    to_agent    TEXT        NOT NULL,
    status      TEXT        NOT NULL,
    artifacts   JSONB       NOT NULL DEFAULT '[]',
    notes       TEXT        NOT NULL DEFAULT '',
    timestamp   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_events_task_id
    ON agent_events (task_id);

CREATE INDEX IF NOT EXISTS idx_agent_events_timestamp
    ON agent_events (timestamp DESC);

CREATE INDEX IF NOT EXISTS idx_agent_events_event_type
    ON agent_events (event_type);

-- 5. Vista de métricas por agente (observabilidad - Fase 6)
CREATE OR REPLACE VIEW agent_metrics AS
SELECT
    from_agent                                      AS agent,
    COUNT(*)                                        AS total_transitions,
    COUNT(*) FILTER (WHERE status = 'SUCCESS')      AS success_count,
    COUNT(*) FILTER (WHERE status = 'REJECTED')     AS rejected_count,
    COUNT(*) FILTER (WHERE status = 'ESCALATE')     AS escalated_count,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE status = 'SUCCESS') / NULLIF(COUNT(*), 0),
        2
    )                                               AS success_rate_pct,
    MIN(timestamp)                                  AS first_seen,
    MAX(timestamp)                                  AS last_seen
FROM agent_events
GROUP BY from_agent;

-- 6. RLS: solo service_role puede leer/escribir vectores y eventos
ALTER TABLE agent_memory_vectors ENABLE ROW LEVEL SECURITY;
ALTER TABLE agent_events         ENABLE ROW LEVEL SECURITY;

-- Política para service_role (Supabase service key)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'agent_memory_vectors' AND policyname = 'service_role_all'
    ) THEN
        CREATE POLICY service_role_all ON agent_memory_vectors
            FOR ALL TO service_role USING (true) WITH CHECK (true);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE tablename = 'agent_events' AND policyname = 'service_role_all'
    ) THEN
        CREATE POLICY service_role_all ON agent_events
            FOR ALL TO service_role USING (true) WITH CHECK (true);
    END IF;
END $$;

-- 7. RPC: get_agent_metrics — expone agent_metrics view via Supabase RPC
CREATE OR REPLACE FUNCTION get_agent_metrics()
RETURNS TABLE (
    from_agent        TEXT,
    total_transitions BIGINT,
    success_count     BIGINT,
    rejected          BIGINT,
    escalated         BIGINT,
    success_rate_pct  NUMERIC
)
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
    SELECT
        agent       AS from_agent,
        total_transitions,
        success_count,
        rejected_count  AS rejected,
        escalated_count AS escalated,
        success_rate_pct
    FROM agent_metrics
    ORDER BY total_transitions DESC;
$$;
