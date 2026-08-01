-- ============================================================
-- Project Atlas / MofoMusic Pipeline — Observabilidade
-- Migration 002 — idempotente
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- pipeline_metrics — snapshots periódicos do estado do pipeline
--
-- As views dão a foto do "agora"; esta tabela guarda a série
-- histórica, permitindo enxergar tendência (fila crescendo, taxa
-- de erro subindo) e não só o instante atual.
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipeline_metrics (
    id            SERIAL PRIMARY KEY,
    coletado_em   TIMESTAMPTZ NOT NULL DEFAULT now(),
    total_videos  INTEGER     NOT NULL DEFAULT 0,
    pendentes     INTEGER     NOT NULL DEFAULT 0,
    transcrevendo INTEGER     NOT NULL DEFAULT 0,
    transcritos   INTEGER     NOT NULL DEFAULT 0,
    publicando    INTEGER     NOT NULL DEFAULT 0,
    publicados    INTEGER     NOT NULL DEFAULT 0,
    parciais      INTEGER     NOT NULL DEFAULT 0,
    com_erro      INTEGER     NOT NULL DEFAULT 0,
    erros_24h     INTEGER     NOT NULL DEFAULT 0,
    detalhes      JSONB
);

CREATE INDEX IF NOT EXISTS idx_metrics_coletado ON pipeline_metrics (coletado_em DESC);

-- ------------------------------------------------------------
-- Retenção de logs
--
-- pipeline_logs cresce indefinidamente. Esta função apaga o que
-- passou da janela de retenção e é chamada pelo Workflow 04.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION purge_pipeline_logs(dias INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
    removidos INTEGER;
BEGIN
    DELETE FROM pipeline_logs WHERE created_at < now() - (dias || ' days')::INTERVAL;
    GET DIAGNOSTICS removidos = ROW_COUNT;

    DELETE FROM pipeline_metrics WHERE coletado_em < now() - (dias * 6 || ' days')::INTERVAL;

    RETURN removidos;
END;
$$ LANGUAGE plpgsql;

-- ------------------------------------------------------------
-- View de saúde consolidada — uma linha, tudo que importa
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_health AS
SELECT
    (SELECT count(*) FROM videos)                                              AS total_videos,
    (SELECT count(*) FROM videos WHERE status = 'PENDING')                     AS pendentes,
    (SELECT count(*) FROM videos WHERE status = 'TRANSCRIBING')                AS transcrevendo,
    (SELECT count(*) FROM videos WHERE status = 'TRANSCRIBED')                 AS transcritos,
    (SELECT count(*) FROM videos WHERE status = 'PUBLISHING')                  AS publicando,
    (SELECT count(*) FROM videos WHERE status = 'PUBLISHED')                   AS publicados,
    (SELECT count(*) FROM videos WHERE status = 'PARTIAL')                     AS parciais,
    (SELECT count(*) FROM videos WHERE status = 'ERROR')                       AS com_erro,
    (SELECT count(*) FROM pipeline_logs
      WHERE level = 'ERROR' AND created_at > now() - INTERVAL '24 hours')      AS erros_24h,
    (SELECT count(*) FROM video_transcriptions)                                AS transcricoes,
    (SELECT count(*) FROM video_publications WHERE status = 'PUBLISHED')       AS publicacoes_ok,
    -- Vídeos presos: em estado transitório há mais de 1 hora indicam
    -- execução interrompida (queda do n8n, timeout, etc.).
    (SELECT count(*) FROM videos
      WHERE status IN ('TRANSCRIBING', 'PUBLISHING')
        AND updated_at < now() - INTERVAL '1 hour')                            AS travados;

COMMIT;
