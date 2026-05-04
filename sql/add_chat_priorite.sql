-- ============================================================
-- Migration : ajout de la colonne priorite dans chat_conversations
-- ============================================================
--
-- BUG : Quand un client clique le bouton SOS Humain (urgent, score 100),
--    le BO admin recevait l escalade mais n affichait PAS le badge URGENT
--    car la table chat_conversations n avait pas de colonne priorite.
--    Le BO admin lisait c.priorite || 'normal' = toujours "normal".
--
-- FIX : Ajouter la colonne priorite (urgent/normal/info) ET la propager dans
--    la vue chat_conversations_summary que le BO admin lit.
-- ============================================================

-- 1. Ajouter la colonne priorite a chat_conversations (si elle n existe pas)
ALTER TABLE public.chat_conversations
  ADD COLUMN IF NOT EXISTS priorite TEXT DEFAULT 'normal'
  CHECK (priorite IN ('urgent', 'normal', 'info'));

-- 2. Index pour requeter rapidement les conversations urgentes
CREATE INDEX IF NOT EXISTS idx_chat_priorite ON public.chat_conversations(priorite)
  WHERE priorite = 'urgent';

-- 3. DROP VIEW puis CREATE VIEW (CREATE OR REPLACE refuse les changements de colonnes)
DROP VIEW IF EXISTS public.chat_conversations_summary CASCADE;

-- 4. Recreer la vue chat_conversations_summary pour inclure priorite
--    Logique : on prend la priorite la plus haute parmi tous les messages du client
--    (urgent > normal > info), pour qu un seul SOS suffise a marquer urgent.
CREATE VIEW public.chat_conversations_summary AS
SELECT
  client_id,
  MAX(client_name) AS client_name,
  MAX(client_phone) AS client_phone,
  MAX(client_email) AS client_email,
  BOOL_OR(is_logged_in) AS is_logged_in,
  COUNT(*) AS total_messages,
  COUNT(*) FILTER (WHERE sender = 'client' AND read_by_admin = FALSE) AS unread_count,
  MAX(created_at) AS last_message_at,
  (SELECT message FROM public.chat_conversations c2
   WHERE c2.client_id = c.client_id
   ORDER BY created_at DESC LIMIT 1) AS last_message,
  (SELECT sender FROM public.chat_conversations c2
   WHERE c2.client_id = c.client_id
   ORDER BY created_at DESC LIMIT 1) AS last_sender,
  CASE
    WHEN BOOL_OR(priorite = 'urgent') THEN 'urgent'
    WHEN BOOL_OR(priorite = 'normal') THEN 'normal'
    ELSE 'info'
  END AS priorite
FROM public.chat_conversations c
GROUP BY client_id
ORDER BY
  CASE
    WHEN BOOL_OR(priorite = 'urgent') THEN 1
    WHEN BOOL_OR(priorite = 'normal') THEN 2
    ELSE 3
  END,
  MAX(created_at) DESC;

-- 5. Re-grant SELECT sur la vue (recreation efface les permissions)
GRANT SELECT ON public.chat_conversations_summary TO anon, authenticated;

-- 6. Verification finale
DO $$
DECLARE
  v_col_exists BOOLEAN;
  v_view_exists BOOLEAN;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'chat_conversations'
      AND column_name = 'priorite'
  ) INTO v_col_exists;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.views
    WHERE table_schema = 'public'
      AND table_name = 'chat_conversations_summary'
  ) INTO v_view_exists;

  IF v_col_exists AND v_view_exists THEN
    RAISE NOTICE 'OK Migration appliquee : colonne priorite + vue mise a jour';
  ELSE
    RAISE WARNING 'PROBLEME : colonne_existe=% vue_existe=%', v_col_exists, v_view_exists;
  END IF;
END $$;

-- Pour tester :
-- SELECT priorite, last_message FROM chat_conversations_summary LIMIT 5;
