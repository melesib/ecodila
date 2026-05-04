-- ECODILA — Préférences RGPD clients (consolidation Supabase) — VERSION CORRIGÉE
-- 
-- ⚠️ FIX 2026-04-25 : la colonne _softDeleted n'existe pas en SQL (c'est un flag JS).
-- On utilise donc une version sans filtrage _softDeleted.
--
-- OBJECTIF :
-- Permettre aux clients (table users) d'avoir des préférences RGPD durables,
-- analogues aux parrains.

-- 1. Ajouter la colonne rgpd_prefs sur users si elle n'existe pas
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'rgpd_prefs'
  ) THEN
    ALTER TABLE users ADD COLUMN rgpd_prefs JSONB DEFAULT NULL;
    COMMENT ON COLUMN users.rgpd_prefs IS
      'Préférences RGPD du client : { whatsapp:bool, email:bool, notifs:bool, marketing:bool, defined_at:ISO }';
    RAISE NOTICE 'Colonne rgpd_prefs ajoutée à users';
  ELSE
    RAISE NOTICE 'Colonne rgpd_prefs existe déjà sur users';
  END IF;
END $$;

-- 2. Index pour requêtes statistiques rapides
CREATE INDEX IF NOT EXISTS idx_users_rgpd_prefs_email
  ON users ((rgpd_prefs->>'email'))
  WHERE rgpd_prefs IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_rgpd_prefs_whatsapp
  ON users ((rgpd_prefs->>'whatsapp'))
  WHERE rgpd_prefs IS NOT NULL;

-- 3. Fonction d'opt-out clients
CREATE OR REPLACE FUNCTION rgpd_check_client_optout(
  p_user_id TEXT,
  p_channel TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefs JSONB;
BEGIN
  IF p_user_id IS NULL OR p_user_id = '' THEN
    RETURN false;
  END IF;

  SELECT rgpd_prefs INTO v_prefs
  FROM users
  WHERE id::TEXT = p_user_id OR telephone = p_user_id
  LIMIT 1;

  IF v_prefs IS NULL THEN
    -- Pas de prefs définies = défauts standards
    IF p_channel IN ('email', 'marketing') THEN
      RETURN true;  -- opt-in requis pour email et marketing
    END IF;
    RETURN false; -- whatsapp/notifs autorisés par défaut
  END IF;

  IF p_channel = 'email' THEN
    RETURN COALESCE((v_prefs->>'email')::boolean, false) = false;
  ELSIF p_channel = 'whatsapp' THEN
    RETURN COALESCE((v_prefs->>'whatsapp')::boolean, true) = false;
  ELSIF p_channel = 'notifs' THEN
    RETURN COALESCE((v_prefs->>'notifs')::boolean, true) = false;
  ELSIF p_channel = 'marketing' THEN
    RETURN COALESCE((v_prefs->>'marketing')::boolean, false) = false;
  END IF;

  RETURN false;
END;
$$;

COMMENT ON FUNCTION rgpd_check_client_optout(TEXT, TEXT) IS
  'Retourne true si le client a opt-out sur le canal demandé (email/whatsapp/notifs/marketing)';

-- 4. Vue stats SANS filtre _softDeleted (filtrage côté JS)
CREATE OR REPLACE VIEW v_rgpd_clients_stats AS
SELECT
  COUNT(*) FILTER (WHERE rgpd_prefs IS NOT NULL) AS clients_avec_prefs,
  COUNT(*) FILTER (WHERE rgpd_prefs IS NULL) AS clients_defaut,
  COUNT(*) AS clients_total,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'whatsapp' = 'true' OR rgpd_prefs IS NULL) AS optin_whatsapp,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'whatsapp' = 'false') AS optout_whatsapp,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'email' = 'true') AS optin_email,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'email' != 'true' OR rgpd_prefs IS NULL) AS optout_email,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'notifs' = 'true' OR rgpd_prefs IS NULL) AS optin_notifs,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'notifs' = 'false') AS optout_notifs,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'marketing' = 'true') AS optin_marketing,
  COUNT(*) FILTER (WHERE rgpd_prefs->>'marketing' != 'true' OR rgpd_prefs IS NULL) AS optout_marketing
FROM users;

COMMENT ON VIEW v_rgpd_clients_stats IS
  'Statistiques agrégées de consentement RGPD des clients (pour rapport ARTCI)';

-- 5. Tests de vérification
SELECT
  'Test client_optout - inexistant' AS test,
  rgpd_check_client_optout('user_inexistant', 'whatsapp') AS optout_wa,
  rgpd_check_client_optout('user_inexistant', 'email') AS optout_email,
  rgpd_check_client_optout('user_inexistant', 'marketing') AS optout_marketing
UNION ALL
SELECT
  'Test client_optout - vrai user' AS test,
  rgpd_check_client_optout(id::TEXT, 'whatsapp') AS optout_wa,
  rgpd_check_client_optout(id::TEXT, 'email') AS optout_email,
  rgpd_check_client_optout(id::TEXT, 'marketing') AS optout_marketing
FROM users
LIMIT 3;

-- 6. Stats agrégées
SELECT * FROM v_rgpd_clients_stats;
