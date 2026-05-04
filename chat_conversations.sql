-- Table : chat_conversations
-- Stocke chaque message échangé entre clients et l'équipe via le chat LIDA + BO
-- Chaque conversation est identifiée par un client_id (téléphone ou user_id)

CREATE TABLE IF NOT EXISTS public.chat_conversations (
  id BIGSERIAL PRIMARY KEY,
  -- Identifiant unique du client (téléphone normalisé ou user_id si connecté)
  client_id TEXT NOT NULL,
  -- Métadonnées du client (pour affichage dans le BO)
  client_name TEXT,
  client_phone TEXT,
  client_email TEXT,
  is_logged_in BOOLEAN DEFAULT FALSE,
  -- Sender : 'client' ou 'admin' ou 'bot'
  sender TEXT NOT NULL CHECK (sender IN ('client', 'admin', 'bot')),
  -- Le message
  message TEXT NOT NULL,
  -- Type : 'text', 'whatsapp_redirect' (le client a cliqué un bouton WA),
  --        'admin_reply' (réponse depuis le BO), 'voice' (transcription vocale)
  message_type TEXT DEFAULT 'text',
  -- Statut de lecture côté client
  read_by_client BOOLEAN DEFAULT FALSE,
  -- Statut de lecture côté admin
  read_by_admin BOOLEAN DEFAULT FALSE,
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  -- Méta JSON pour extensions futures (pièces jointes, etc.)
  meta JSONB DEFAULT '{}'::jsonb
);

-- Index pour requêter rapidement les messages d'un client
CREATE INDEX IF NOT EXISTS idx_chat_client_id ON public.chat_conversations(client_id);
CREATE INDEX IF NOT EXISTS idx_chat_created_at ON public.chat_conversations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_unread_client ON public.chat_conversations(client_id, read_by_client) 
  WHERE read_by_client = FALSE;
CREATE INDEX IF NOT EXISTS idx_chat_unread_admin ON public.chat_conversations(read_by_admin) 
  WHERE read_by_admin = FALSE;

-- RLS : autoriser tout le monde à insérer (les clients), mais lecture seulement
-- de ses propres messages (par client_id matchant)
ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;

-- Permettre à tout le monde d'insérer (clients pour leurs messages, admins pour les réponses)
DROP POLICY IF EXISTS chat_insert_all ON public.chat_conversations;
CREATE POLICY chat_insert_all ON public.chat_conversations
  FOR INSERT WITH CHECK (TRUE);

-- Permettre à tout le monde de lire (le filtrage par client_id se fait côté app)
DROP POLICY IF EXISTS chat_select_all ON public.chat_conversations;
CREATE POLICY chat_select_all ON public.chat_conversations
  FOR SELECT USING (TRUE);

-- Permettre les UPDATE (pour marquer comme lu)
DROP POLICY IF EXISTS chat_update_all ON public.chat_conversations;
CREATE POLICY chat_update_all ON public.chat_conversations
  FOR UPDATE USING (TRUE);

-- Vue : conversations groupées par client (pour le BO)
CREATE OR REPLACE VIEW public.chat_conversations_summary AS
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
   ORDER BY created_at DESC LIMIT 1) AS last_sender
FROM public.chat_conversations c
GROUP BY client_id
ORDER BY MAX(created_at) DESC;

-- Permettre à la vue d'être interrogée
GRANT SELECT ON public.chat_conversations_summary TO anon, authenticated;
