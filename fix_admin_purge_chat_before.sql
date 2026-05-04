-- ============================================================
-- FIX : admin_purge_chat_before
-- ============================================================
-- Bugs corriges :
--   1. relation "chat_messages" does not exist (42P01)
--      -> la vraie table est "chat_conversations" (pas chat_messages)
--   2. DELETE requires a WHERE clause (21000) quand p_before_date = NULL
--      -> ajout de WHERE id IS NOT NULL (toujours vrai)
--
-- Tables reelles utilisees par le BO Admin :
--   - chat_conversations : messages individuels (col: id, client_id, created_at, ...)
--   - chat_tickets       : tickets (col: id, status, created_at, closed_at, last_admin_message_at)
--   - chat_conversations_summary : VUE agregee (col: client_id, last_message_at, ...)
--
-- A executer dans le SQL Editor de Supabase.
-- ============================================================

CREATE OR REPLACE FUNCTION public.admin_purge_chat_before(p_before_date TIMESTAMPTZ DEFAULT NULL)
RETURNS TABLE(deleted_messages BIGINT, deleted_tickets BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_msg_count BIGINT := 0;
  v_tk_count  BIGINT := 0;
BEGIN
  IF p_before_date IS NULL THEN
    -- Mode "tout effacer" : WHERE id IS NOT NULL = toujours vrai
    DELETE FROM chat_conversations WHERE id IS NOT NULL;
    GET DIAGNOSTICS v_msg_count = ROW_COUNT;

    DELETE FROM chat_tickets WHERE id IS NOT NULL;
    GET DIAGNOSTICS v_tk_count = ROW_COUNT;
  ELSE
    -- Mode "avant date X"
    DELETE FROM chat_conversations WHERE created_at < p_before_date;
    GET DIAGNOSTICS v_msg_count = ROW_COUNT;

    -- Pour les tickets : on supprime ceux dont le dernier message admin est avant la date
    -- (ou ceux qui n'ont jamais eu de reponse admin et sont anciens)
    DELETE FROM chat_tickets
    WHERE created_at < p_before_date
      AND (last_admin_message_at IS NULL OR last_admin_message_at < p_before_date);
    GET DIAGNOSTICS v_tk_count = ROW_COUNT;
  END IF;

  RETURN QUERY SELECT v_msg_count, v_tk_count;
END;
$$;

-- Permissions API REST
GRANT EXECUTE ON FUNCTION public.admin_purge_chat_before(TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_purge_chat_before(TIMESTAMPTZ) TO anon;

-- ============================================================
-- IMPORTANT : apres avoir execute ce SQL, RAFRAICHIR le cache PostgREST
-- (sinon l'erreur 404 Not Found peut persister 30-60 secondes)
--
-- Pour forcer le refresh immediat :
--   NOTIFY pgrst, 'reload schema';
--
-- Ou attendre ~1 minute apres l'execution.
-- ============================================================

-- Refresh du cache PostgREST (resout l'erreur 404)
NOTIFY pgrst, 'reload schema';

-- ============================================================
-- Test post-deploiement (dans le SQL Editor) :
--
--   -- Test 1 : mode "avant date" (sur 1900 ne supprime rien)
--   SELECT * FROM admin_purge_chat_before('1900-01-01'::timestamptz);
--
--   -- Test 2 : mode "tout effacer" (ATTENTION sur env de dev !)
--   -- SELECT * FROM admin_purge_chat_before(NULL);
-- ============================================================
