-- ============================================================
-- Project Atlas / MofoMusic Pipeline — Schema completo
-- Migration 001 — idempotente (pode rodar várias vezes)
-- ============================================================

BEGIN;

-- ------------------------------------------------------------
-- videos — tabela central do pipeline
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS videos (
    id            SERIAL PRIMARY KEY,
    drive_file_id TEXT        NOT NULL UNIQUE,
    filename      TEXT        NOT NULL,
    status        TEXT        NOT NULL DEFAULT 'PENDING',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Colunas adicionadas depois da Sprint 1 (idempotente)
ALTER TABLE videos ADD COLUMN IF NOT EXISTS updated_at       TIMESTAMPTZ NOT NULL DEFAULT now();
ALTER TABLE videos ADD COLUMN IF NOT EXISTS mime_type        TEXT;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS size_bytes       BIGINT;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS drive_link       TEXT;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS drive_created_at TIMESTAMPTZ;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS current_folder   TEXT NOT NULL DEFAULT 'ENTRADA';
ALTER TABLE videos ADD COLUMN IF NOT EXISTS error_message    TEXT;
ALTER TABLE videos ADD COLUMN IF NOT EXISTS retry_count      INTEGER NOT NULL DEFAULT 0;

-- Estados válidos do pipeline. Constraint nomeada e recriada de forma
-- idempotente para permitir evolução do fluxo em migrations futuras.
ALTER TABLE videos DROP CONSTRAINT IF EXISTS videos_status_check;
ALTER TABLE videos ADD CONSTRAINT videos_status_check CHECK (status IN (
    'PENDING',       -- detectado, aguardando transcrição
    'TRANSCRIBING',  -- em processamento no workflow 02
    'TRANSCRIBED',   -- legenda pronta, aguardando publicação
    'PUBLISHING',    -- em processamento no workflow 03
    'PUBLISHED',     -- publicado em todas as redes habilitadas
    'PARTIAL',       -- publicado em parte das redes
    'ERROR'          -- falha (ver error_message / pipeline_logs)
));

ALTER TABLE videos DROP CONSTRAINT IF EXISTS videos_current_folder_check;
ALTER TABLE videos ADD CONSTRAINT videos_current_folder_check CHECK (current_folder IN (
    'ENTRADA', 'FILA', 'POSTADOS', 'ERRO'
));

CREATE INDEX IF NOT EXISTS idx_videos_status         ON videos (status);
CREATE INDEX IF NOT EXISTS idx_videos_created_at     ON videos (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_videos_status_created ON videos (status, created_at);

-- ------------------------------------------------------------
-- video_transcriptions — resultado do Workflow 02
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS video_transcriptions (
    id               SERIAL PRIMARY KEY,
    video_id         INTEGER     NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    language         TEXT,
    transcript_text  TEXT,
    subtitle_srt     TEXT,
    model            TEXT,
    duration_seconds NUMERIC(10, 3),
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Uma transcrição corrente por vídeo (reprocessamento faz UPSERT).
CREATE UNIQUE INDEX IF NOT EXISTS idx_transcriptions_video_unique
    ON video_transcriptions (video_id);

-- ------------------------------------------------------------
-- social_networks — catálogo de redes (preparado para expansão)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS social_networks (
    id         SERIAL PRIMARY KEY,
    code       TEXT        NOT NULL UNIQUE,
    name       TEXT        NOT NULL,
    enabled    BOOLEAN     NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Instagram e Facebook são o escopo do Workflow 03 (Sprint 3).
-- As demais ficam cadastradas e DESABILITADAS: a arquitetura já suporta,
-- a integração de cada uma é trabalho futuro.
INSERT INTO social_networks (code, name, enabled) VALUES
    ('INSTAGRAM',      'Instagram',       true),
    ('FACEBOOK',       'Facebook',        true),
    ('TIKTOK',         'TikTok',          false),
    ('YOUTUBE_SHORTS', 'YouTube Shorts',  false),
    ('THREADS',        'Threads',         false),
    ('X',              'X',               false),
    ('PINTEREST',      'Pinterest',       false),
    ('LINKEDIN',       'LinkedIn',        false)
ON CONFLICT (code) DO NOTHING;

-- ------------------------------------------------------------
-- video_publications — uma linha por (vídeo, rede)
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS video_publications (
    id               SERIAL PRIMARY KEY,
    video_id         INTEGER     NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    network_id       INTEGER     NOT NULL REFERENCES social_networks (id),
    status           TEXT        NOT NULL DEFAULT 'PENDING',
    external_post_id TEXT,
    permalink        TEXT,
    error_message    TEXT,
    retry_count      INTEGER     NOT NULL DEFAULT 0,
    published_at     TIMESTAMPTZ,
    created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT video_publications_unique UNIQUE (video_id, network_id)
);

ALTER TABLE video_publications DROP CONSTRAINT IF EXISTS video_publications_status_check;
ALTER TABLE video_publications ADD CONSTRAINT video_publications_status_check CHECK (status IN (
    'PENDING', 'PUBLISHING', 'PUBLISHED', 'ERROR', 'SKIPPED'
));

CREATE INDEX IF NOT EXISTS idx_publications_video   ON video_publications (video_id);
CREATE INDEX IF NOT EXISTS idx_publications_status  ON video_publications (status);
CREATE INDEX IF NOT EXISTS idx_publications_network ON video_publications (network_id, status);

-- ------------------------------------------------------------
-- video_status_history — auditoria de transições de estado
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS video_status_history (
    id          SERIAL PRIMARY KEY,
    video_id    INTEGER     NOT NULL REFERENCES videos (id) ON DELETE CASCADE,
    from_status TEXT,
    to_status   TEXT        NOT NULL,
    note        TEXT,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_status_history_video ON video_status_history (video_id, created_at DESC);

-- ------------------------------------------------------------
-- pipeline_logs — log estruturado dos workflows
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pipeline_logs (
    id         SERIAL PRIMARY KEY,
    video_id   INTEGER     REFERENCES videos (id) ON DELETE SET NULL,
    workflow   TEXT        NOT NULL,
    level      TEXT        NOT NULL DEFAULT 'INFO',
    message    TEXT        NOT NULL,
    context    JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE pipeline_logs DROP CONSTRAINT IF EXISTS pipeline_logs_level_check;
ALTER TABLE pipeline_logs ADD CONSTRAINT pipeline_logs_level_check CHECK (level IN (
    'DEBUG', 'INFO', 'WARN', 'ERROR'
));

CREATE INDEX IF NOT EXISTS idx_logs_video   ON pipeline_logs (video_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_level   ON pipeline_logs (level, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_logs_created ON pipeline_logs (created_at DESC);

-- ------------------------------------------------------------
-- Automação: updated_at e histórico de status
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION trg_set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS videos_set_updated_at ON videos;
CREATE TRIGGER videos_set_updated_at
    BEFORE UPDATE ON videos
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

DROP TRIGGER IF EXISTS publications_set_updated_at ON video_publications;
CREATE TRIGGER publications_set_updated_at
    BEFORE UPDATE ON video_publications
    FOR EACH ROW EXECUTE FUNCTION trg_set_updated_at();

-- Registra automaticamente toda troca de status em video_status_history,
-- para que nenhum workflow precise lembrar de fazer isso manualmente.
CREATE OR REPLACE FUNCTION trg_log_video_status() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO video_status_history (video_id, from_status, to_status, note)
        VALUES (NEW.id, NULL, NEW.status, 'registro criado');
    ELSIF NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO video_status_history (video_id, from_status, to_status, note)
        VALUES (NEW.id, OLD.status, NEW.status, NEW.error_message);
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS videos_log_status ON videos;
CREATE TRIGGER videos_log_status
    AFTER INSERT OR UPDATE OF status ON videos
    FOR EACH ROW EXECUTE FUNCTION trg_log_video_status();

-- ------------------------------------------------------------
-- Views de observabilidade (Sprint 4)
-- ------------------------------------------------------------
CREATE OR REPLACE VIEW vw_pipeline_status AS
SELECT status,
       count(*)      AS total,
       min(created_at) AS mais_antigo,
       max(updated_at) AS ultima_atualizacao
FROM videos
GROUP BY status;

CREATE OR REPLACE VIEW vw_videos_detalhado AS
SELECT v.id,
       v.filename,
       v.status,
       v.current_folder,
       v.retry_count,
       v.error_message,
       v.created_at,
       v.updated_at,
       t.language,
       t.model                        AS transcription_model,
       t.duration_seconds,
       (t.id IS NOT NULL)             AS tem_transcricao,
       count(p.id) FILTER (WHERE p.status = 'PUBLISHED') AS redes_publicadas,
       count(p.id) FILTER (WHERE p.status = 'ERROR')     AS redes_com_erro
FROM videos v
LEFT JOIN video_transcriptions t ON t.video_id = v.id
LEFT JOIN video_publications   p ON p.video_id = v.id
GROUP BY v.id, t.id;

CREATE OR REPLACE VIEW vw_publicacoes_por_rede AS
SELECT n.code   AS rede,
       n.name   AS rede_nome,
       n.enabled,
       count(p.id) FILTER (WHERE p.status = 'PUBLISHED') AS publicados,
       count(p.id) FILTER (WHERE p.status = 'ERROR')     AS erros,
       count(p.id) FILTER (WHERE p.status = 'PENDING')   AS pendentes,
       max(p.published_at)                               AS ultima_publicacao
FROM social_networks n
LEFT JOIN video_publications p ON p.network_id = n.id
GROUP BY n.id
ORDER BY n.code;

COMMIT;
