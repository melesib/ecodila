-- ═══════════════════════════════════════════════════════════════════════
-- TABLE : nego_abandoned — Négociations abandonnées (pour relances admin)
-- ═══════════════════════════════════════════════════════════════════════
-- Capture les négos qui n'ont PAS abouti à une offre soumise :
--   - Client a tapé un prix mais pas cliqué Suivant
--   - Client a refusé le dernier prix du bot
--   - Client a fermé le modal sans soumettre
--
-- Permet à l'admin de relancer le client via WhatsApp avec contexte complet.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.nego_abandoned (
  id BIGSERIAL PRIMARY KEY,

  -- Identification
  client_id TEXT,                            -- même format que chat_conversations
  client_name TEXT,
  client_phone TEXT,
  client_email TEXT,
  is_logged_in BOOLEAN DEFAULT FALSE,

  -- Produit négocié
  produit_id TEXT,
  produit_nom TEXT,
  produit_marque TEXT,
  produit_modele TEXT,
  etat_choisi TEXT,                          -- Neuf, Occasion, Recyclé
  prix_reference INTEGER,                    -- Prix officiel affiché EcoDila

  -- Détails de l'abandon
  abandon_reason TEXT NOT NULL CHECK (abandon_reason IN (
    'closed_modal',           -- Fermé le modal sans soumettre
    'rejected_final',         -- Refusé le dernier prix du bot
    'no_advance',             -- Tapé un prix mais pas cliqué Suivant
    'closed_offer_form'       -- A rempli le prix mais pas les infos perso
  )),
  last_client_price INTEGER,                 -- Dernier prix proposé par le client
  last_bot_price INTEGER,                    -- Dernière contre-offre du bot
  exchange_count INTEGER DEFAULT 0,          -- Nombre d'échanges dans la négo

  -- Bonus joués
  wheel_used BOOLEAN DEFAULT FALSE,
  wheel_bonus_pc NUMERIC(4,1),               -- ex: 2.5 pour +2.5%
  coinflip_used BOOLEAN DEFAULT FALSE,
  coinflip_won BOOLEAN DEFAULT FALSE,

  -- Historique de la conversation chat (snapshot JSON)
  -- Format : [{who:'bot|user', text:'...', time:'2026-...'}]
  chat_history JSONB DEFAULT '[]'::jsonb,

  -- Suivi admin
  status TEXT DEFAULT 'pending' CHECK (status IN (
    'pending',                -- À relancer
    'contacted',              -- Admin a relancé
    'recovered',              -- Le client a finalisé après relance
    'lost'                    -- Définitivement abandonné (>7j sans réponse)
  )),
  admin_notes TEXT,
  followups JSONB DEFAULT '[]'::jsonb,       -- [{date, channel:'whatsapp', template, by_admin}]

  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_relance_at TIMESTAMPTZ,
  resolved_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_nego_abandoned_client ON public.nego_abandoned(client_id);
CREATE INDEX IF NOT EXISTS idx_nego_abandoned_status ON public.nego_abandoned(status);
CREATE INDEX IF NOT EXISTS idx_nego_abandoned_created ON public.nego_abandoned(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_nego_abandoned_phone ON public.nego_abandoned(client_phone) WHERE client_phone IS NOT NULL;

-- RLS : tout le monde peut INSERT (clients anonymes), SELECT/UPDATE admin only
ALTER TABLE public.nego_abandoned ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon insert nego_abandoned" ON public.nego_abandoned;
CREATE POLICY "anon insert nego_abandoned" ON public.nego_abandoned
  FOR INSERT TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "admin select nego_abandoned" ON public.nego_abandoned;
CREATE POLICY "admin select nego_abandoned" ON public.nego_abandoned
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS "admin update nego_abandoned" ON public.nego_abandoned;
CREATE POLICY "admin update nego_abandoned" ON public.nego_abandoned
  FOR UPDATE TO authenticated
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "admin delete nego_abandoned" ON public.nego_abandoned;
CREATE POLICY "admin delete nego_abandoned" ON public.nego_abandoned
  FOR DELETE TO authenticated
  USING (true);

GRANT SELECT, INSERT ON public.nego_abandoned TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.nego_abandoned TO authenticated;
GRANT USAGE, SELECT ON SEQUENCE public.nego_abandoned_id_seq TO anon, authenticated;

-- Vue de synthèse pour le BO : avec calcul automatique de la priorité
-- (rouge si > 3j sans relance, orange si 1-3j, vert si récent)
CREATE OR REPLACE VIEW public.nego_abandoned_summary AS
SELECT
  n.*,
  EXTRACT(EPOCH FROM (NOW() - n.created_at))/86400 AS days_since_abandon,
  CASE
    WHEN n.last_relance_at IS NULL THEN
      EXTRACT(EPOCH FROM (NOW() - n.created_at))/86400
    ELSE
      EXTRACT(EPOCH FROM (NOW() - n.last_relance_at))/86400
  END AS days_since_last_action,
  CASE
    WHEN n.status = 'recovered' THEN 'success'
    WHEN n.status = 'lost' THEN 'closed'
    WHEN EXTRACT(EPOCH FROM (NOW() - n.created_at))/86400 > 7 THEN 'critical'
    WHEN EXTRACT(EPOCH FROM (NOW() - COALESCE(n.last_relance_at, n.created_at))/86400) > 3 THEN 'urgent'
    WHEN EXTRACT(EPOCH FROM (NOW() - COALESCE(n.last_relance_at, n.created_at))/86400) > 1 THEN 'warm'
    ELSE 'fresh'
  END AS priority,
  COALESCE(jsonb_array_length(n.followups), 0) AS relance_count
FROM public.nego_abandoned n
ORDER BY
  CASE n.status WHEN 'pending' THEN 0 WHEN 'contacted' THEN 1 ELSE 2 END,
  n.created_at DESC;

GRANT SELECT ON public.nego_abandoned_summary TO authenticated;
