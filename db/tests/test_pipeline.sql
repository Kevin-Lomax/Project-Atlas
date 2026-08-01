-- ============================================================
-- Teste automatizado do pipeline (nível de banco)
--
-- Executa exatamente as mesmas queries usadas pelos Workflows 01→04
-- contra dados sintéticos e valida cada etapa. Roda dentro de uma
-- transação com ROLLBACK no final: não deixa resíduo no banco.
--
-- Uso: psql -U n8n_user -d n8n -v ON_ERROR_STOP=1 -f test_pipeline.sql
-- ============================================================

BEGIN;

\set QUIET on
\pset format aligned

DO $$
DECLARE
    v_id        INTEGER;
    v_status    TEXT;
    v_count     INTEGER;
    v_folder    TEXT;
    net_ig      INTEGER;
BEGIN
    RAISE NOTICE '--- WF01: registrar vídeo (INSERT ... ON CONFLICT DO NOTHING) ---';
    INSERT INTO videos (drive_file_id, filename, mime_type, size_bytes, drive_link, drive_created_at, current_folder, status)
    VALUES ('TESTE_DRIVE_ID_001', 'teste-atlas.mp4', 'video/mp4', 12345678,
            'https://drive.google.com/file/d/TESTE_DRIVE_ID_001', now(), 'ENTRADA', 'PENDING')
    RETURNING id INTO v_id;
    ASSERT v_id IS NOT NULL, 'WF01: vídeo não foi inserido';

    RAISE NOTICE 'WF01 OK: vídeo id=%', v_id;

    -- Duplicidade: a segunda tentativa não pode criar linha nova.
    INSERT INTO videos (drive_file_id, filename) VALUES ('TESTE_DRIVE_ID_001', 'teste-atlas.mp4')
    ON CONFLICT (drive_file_id) DO NOTHING;
    SELECT count(*) INTO v_count FROM videos WHERE drive_file_id = 'TESTE_DRIVE_ID_001';
    ASSERT v_count = 1, format('WF01: duplicidade não barrada (%s linhas)', v_count);
    RAISE NOTICE 'WF01 OK: duplicidade barrada';

    -- Auditoria automática do status inicial (trigger).
    SELECT count(*) INTO v_count FROM video_status_history WHERE video_id = v_id;
    ASSERT v_count >= 1, 'Auditoria: histórico inicial não foi gravado pelo trigger';
    RAISE NOTICE 'Auditoria OK: % registro(s) de histórico', v_count;

    UPDATE videos SET current_folder = 'FILA' WHERE id = v_id;

    RAISE NOTICE '--- WF02: transcrição (UPSERT por video_id) ---';
    UPDATE videos SET status = 'TRANSCRIBING' WHERE id = v_id;

    INSERT INTO video_transcriptions (video_id, language, transcript_text, subtitle_srt, model, duration_seconds)
    VALUES (v_id, 'pt', 'texto de teste, com vírgula e ''aspas''',
            '1' || chr(10) || '00:00:00,000 --> 00:00:02,000' || chr(10) || 'teste', 'whisper-large-v3-turbo', 12.5)
    ON CONFLICT (video_id) DO UPDATE SET transcript_text = EXCLUDED.transcript_text;

    -- Reprocessar o mesmo vídeo deve ATUALIZAR, nunca duplicar.
    INSERT INTO video_transcriptions (video_id, language, transcript_text, subtitle_srt, model, duration_seconds)
    VALUES (v_id, 'pt', 'texto reprocessado', 'srt2', 'whisper-large-v3-turbo', 12.5)
    ON CONFLICT (video_id) DO UPDATE SET transcript_text = EXCLUDED.transcript_text;

    SELECT count(*) INTO v_count FROM video_transcriptions WHERE video_id = v_id;
    ASSERT v_count = 1, format('WF02: transcrição duplicada (%s linhas)', v_count);
    RAISE NOTICE 'WF02 OK: UPSERT não duplicou';

    UPDATE videos SET status = 'TRANSCRIBED' WHERE id = v_id;

    RAISE NOTICE '--- WF03: seleção de prontos e publicação ---';
    SELECT count(*) INTO v_count
    FROM videos v LEFT JOIN video_transcriptions t ON t.video_id = v.id
    WHERE v.status = 'TRANSCRIBED' AND v.id = v_id;
    ASSERT v_count = 1, 'WF03: vídeo pronto não apareceu na seleção';
    RAISE NOTICE 'WF03 OK: vídeo elegível para publicação';

    UPDATE videos SET status = 'PUBLISHING' WHERE id = v_id;

    -- Publica só no Instagram: o esperado é status final PARTIAL,
    -- já que o Facebook também está habilitado.
    INSERT INTO video_publications (video_id, network_id, status, external_post_id, published_at)
    SELECT v_id, n.id, 'PUBLISHED', 'IG_POST_TESTE', now() FROM social_networks n WHERE n.code = 'INSTAGRAM'
    ON CONFLICT (video_id, network_id) DO UPDATE SET status = 'PUBLISHED';

    UPDATE videos v SET status = CASE
        WHEN (SELECT count(*) FROM social_networks WHERE enabled) > 0
         AND (SELECT count(*) FROM social_networks WHERE enabled) =
             (SELECT count(*) FROM video_publications p JOIN social_networks n ON n.id = p.network_id
              WHERE p.video_id = v.id AND n.enabled AND p.status = 'PUBLISHED') THEN 'PUBLISHED'
        WHEN EXISTS (SELECT 1 FROM video_publications p WHERE p.video_id = v.id AND p.status = 'PUBLISHED') THEN 'PARTIAL'
        ELSE 'ERROR' END
    WHERE v.id = v_id;

    SELECT status INTO v_status FROM videos WHERE id = v_id;
    ASSERT v_status = 'PARTIAL', format('WF03: esperado PARTIAL com só uma rede publicada, veio %s', v_status);
    RAISE NOTICE 'WF03 OK: status parcial calculado corretamente (%)', v_status;

    -- Agora publica no Facebook também: deve virar PUBLISHED.
    INSERT INTO video_publications (video_id, network_id, status, external_post_id, published_at)
    SELECT v_id, n.id, 'PUBLISHED', 'FB_POST_TESTE', now() FROM social_networks n WHERE n.code = 'FACEBOOK'
    ON CONFLICT (video_id, network_id) DO UPDATE SET status = 'PUBLISHED';

    UPDATE videos v SET status = CASE
        WHEN (SELECT count(*) FROM social_networks WHERE enabled) > 0
         AND (SELECT count(*) FROM social_networks WHERE enabled) =
             (SELECT count(*) FROM video_publications p JOIN social_networks n ON n.id = p.network_id
              WHERE p.video_id = v.id AND n.enabled AND p.status = 'PUBLISHED') THEN 'PUBLISHED'
        WHEN EXISTS (SELECT 1 FROM video_publications p WHERE p.video_id = v.id AND p.status = 'PUBLISHED') THEN 'PARTIAL'
        ELSE 'ERROR' END
    WHERE v.id = v_id;

    SELECT status INTO v_status FROM videos WHERE id = v_id;
    ASSERT v_status = 'PUBLISHED', format('WF03: esperado PUBLISHED, veio %s', v_status);
    RAISE NOTICE 'WF03 OK: status final PUBLISHED';

    UPDATE videos SET current_folder = 'POSTADOS' WHERE id = v_id;
    SELECT current_folder INTO v_folder FROM videos WHERE id = v_id;
    ASSERT v_folder = 'POSTADOS', 'WF03: pasta final não atualizada';
    RAISE NOTICE 'WF03 OK: arquivo marcado em POSTADOS';

    RAISE NOTICE '--- WF04: auto-recuperação de vídeos presos ---';
    UPDATE videos SET status = 'TRANSCRIBING' WHERE id = v_id;

    -- O trigger videos_set_updated_at reescreve updated_at a cada UPDATE,
    -- então não há como "envelhecer" a linha por UPDATE normal. Em produção
    -- isso é o comportamento correto (o tempo passa sozinho); aqui o trigger
    -- é desligado só para simular um vídeo parado há 3 horas.
    ALTER TABLE videos DISABLE TRIGGER videos_set_updated_at;
    UPDATE videos SET updated_at = now() - INTERVAL '3 hours' WHERE id = v_id;
    ALTER TABLE videos ENABLE TRIGGER videos_set_updated_at;

    UPDATE videos SET status = CASE
            WHEN status = 'TRANSCRIBING' THEN 'PENDING'
            WHEN status = 'PUBLISHING'   THEN 'TRANSCRIBED' END
    WHERE status IN ('TRANSCRIBING', 'PUBLISHING') AND updated_at < now() - INTERVAL '1 hour';

    SELECT status INTO v_status FROM videos WHERE id = v_id;
    ASSERT v_status = 'PENDING', format('WF04: destravamento falhou, status=%s', v_status);
    RAISE NOTICE 'WF04 OK: vídeo preso foi devolvido para PENDING';

    RAISE NOTICE '--- Constraints ---';
    BEGIN
        UPDATE videos SET status = 'ESTADO_INVALIDO' WHERE id = v_id;
        RAISE EXCEPTION 'Constraint de status NÃO barrou valor inválido';
    EXCEPTION WHEN check_violation THEN
        RAISE NOTICE 'Constraint OK: status inválido rejeitado';
    END;

    -- Integridade referencial: apagar o vídeo apaga tudo que depende dele.
    DELETE FROM videos WHERE id = v_id;
    SELECT count(*) INTO v_count FROM video_transcriptions WHERE video_id = v_id;
    ASSERT v_count = 0, 'CASCADE: transcrição órfã após apagar vídeo';
    SELECT count(*) INTO v_count FROM video_publications WHERE video_id = v_id;
    ASSERT v_count = 0, 'CASCADE: publicação órfã após apagar vídeo';
    RAISE NOTICE 'CASCADE OK: dependências removidas junto com o vídeo';

    RAISE NOTICE '=========================================';
    RAISE NOTICE 'TODOS OS TESTES PASSARAM';
    RAISE NOTICE '=========================================';
END $$;

ROLLBACK;
