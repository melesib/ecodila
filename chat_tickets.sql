-- ════════════════════════════════════════════════════════════════════
-- Évolution du chat : système de tickets avec statuts + auto-fermeture
-- ════════════════════════════════════════════════════════════════════

-- 1. Ajouter les colonnes de ticket à chat_conversations
ALTER TABLE public.chat_conversations 
  ADD COLUMN IF NOT EXISTS ticket_id BIGINT,
  ADD COLUMN IF NOT EXISTS auto_close_warning_shown BOOLEAN DEFAULT FALSE;

-- 2. Créer la table tickets
CREATE TABLE IF NOT EXISTS public.chat_tickets (
  id BIGSERIAL PRIMARY KEY,
  client_id TEXT NOT NULL,
  client_name TEXT,
  client_phone TEXT,
  client_email TEXT,
  -- Statuts possibles :
  -- 'open'        : nouveau ticket, client a écrit, en attente de réponse admin
  -- 'in_progress' : admin a répondu, en attente du retour client
  -- 'resolved'    : résolu manuellement par admin (générique)
  -- 'order_made'  : résolu : devenu commande
  -- 'info_given'  : résolu : juste de l'info fournie
  -- 'auto_closed' : auto-fermé après 48h sans retour client
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved','order_made','info_given','auto_closed')),
  -- Sujet auto-déduit du 1er message (pour affichage rapide dans la liste)
  subject TEXT,
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_client_message_at TIMESTAMPTZ DEFAULT NOW(),
  last_admin_message_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  -- Note interne admin (pas visible par le client)
  admin_note TEXT,
  meta JSONB DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_tickets_client_id ON public.chat_tickets(client_id);
CREATE INDEX IF NOT EXISTS idx_tickets_status ON public.chat_tickets(status);
CREATE INDEX IF NOT EXISTS idx_tickets_last_client ON public.chat_tickets(last_client_message_at);

-- 3. RLS
ALTER TABLE public.chat_tickets ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tickets_all ON public.chat_tickets;
CREATE POLICY tickets_all ON public.chat_tickets FOR ALL USING (TRUE) WITH CHECK (TRUE);

-- 4. Fonction : récupérer ou créer le ticket actif d'un client
-- Logique :
--   - S'il a un ticket actif (open ou in_progress) ET dernier message client < 48h → réutiliser
--   - Sinon → créer un nouveau ticket
CREATE OR REPLACE FUNCTION public.get_or_create_ticket(
  p_client_id TEXT,
  p_client_name TEXT DEFAULT NULL,
  p_client_phone TEXT DEFAULT NULL,
  p_client_email TEXT DEFAULT NULL,
  p_first_message TEXT DEFAULT NULL
) RETURNS BIGINT AS $$
DECLARE
  v_ticket_id BIGINT;
  v_subject TEXT;
BEGIN
  -- Chercher un ticket actif récent (< 48h sans retour)
  SELECT id INTO v_ticket_id
  FROM public.chat_tickets
  WHERE client_id = p_client_id
    AND status IN ('open', 'in_progress')
    AND last_client_message_at > NOW() - INTERVAL '48 hours'
  ORDER BY id DESC
  LIMIT 1;

  -- Si trouvé : mettre à jour last_client_message_at + retourner
  IF v_ticket_id IS NOT NULL THEN
    UPDATE public.chat_tickets 
      SET last_client_message_at = NOW(),
          status = CASE 
            WHEN status = 'in_progress' THEN 'open'  -- retour client = on attend admin à nouveau
            ELSE status 
          END
      WHERE id = v_ticket_id;
    RETURN v_ticket_id;
  END IF;

  -- Sinon : créer un nouveau ticket
  v_subject := COALESCE(LEFT(p_first_message, 80), 'Nouvelle conversation');
  INSERT INTO public.chat_tickets(
    client_id, client_name, client_phone, client_email, status, subject, last_client_message_at
  ) VALUES (
    p_client_id, p_client_name, p_client_phone, p_client_email, 'open', v_subject, NOW()
  ) RETURNING id INTO v_ticket_id;
  
  RETURN v_ticket_id;
END;
$$ LANGUAGE plpgsql;

-- 5. Fonction : auto-fermer les tickets > 48h sans retour client
-- Le BO peut appeler ça périodiquement
CREATE OR REPLACE FUNCTION public.auto_close_stale_tickets() RETURNS INTEGER AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.chat_tickets
    SET status = 'auto_closed',
        closed_at = NOW()
    WHERE status IN ('open', 'in_progress')
      AND last_client_message_at < NOW() - INTERVAL '48 hours'
      AND last_admin_message_at IS NOT NULL  -- au moins un échange a eu lieu
      AND last_admin_message_at < NOW() - INTERVAL '48 hours';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$ LANGUAGE plpgsql;

-- 6. Mettre à jour la vue summary pour inclure le statut du dernier ticket
CREATE OR REPLACE VIEW public.chat_conversations_summary AS
SELECT
  c.client_id,
  MAX(c.client_name) AS client_name,
  MAX(c.client_phone) AS client_phone,
  MAX(c.client_email) AS client_email,
  BOOL_OR(c.is_logged_in) AS is_logged_in,
  COUNT(*) AS total_messages,
  COUNT(*) FILTER (WHERE c.sender = 'client' AND c.read_by_admin = FALSE) AS unread_count,
  MAX(c.created_at) AS last_message_at,
  (SELECT message FROM public.chat_conversations c2 
   WHERE c2.client_id = c.client_id 
   ORDER BY created_at DESC LIMIT 1) AS last_message,
  (SELECT sender FROM public.chat_conversations c2 
   WHERE c2.client_id = c.client_id 
   ORDER BY created_at DESC LIMIT 1) AS last_sender,
  -- Statut du ticket actif le plus récent
  (SELECT status FROM public.chat_tickets t 
   WHERE t.client_id = c.client_id 
   ORDER BY t.id DESC LIMIT 1) AS current_ticket_status,
  (SELECT id FROM public.chat_tickets t 
   WHERE t.client_id = c.client_id 
   ORDER BY t.id DESC LIMIT 1) AS current_ticket_id,
  (SELECT subject FROM public.chat_tickets t 
   WHERE t.client_id = c.client_id 
   ORDER BY t.id DESC LIMIT 1) AS current_ticket_subject
FROM public.chat_conversations c
GROUP BY c.client_id
ORDER BY MAX(c.created_at) DESC;

GRANT SELECT ON public.chat_conversations_summary TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_or_create_ticket TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.auto_close_stale_tickets TO anon, authenticated;
