-- ═══════════════════════════════════════════════════════════════════════════
-- MIGRATION : Ajout colonne rgpd_prefs sur la table parrains
-- Finalité : stocker les préférences RGPD de chaque parrain
--            (notifications, WhatsApp, leaderboard, emails)
-- Rétrocompatible : si la colonne existe déjà, ne rien faire.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Ajouter la colonne rgpd_prefs (JSONB)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'parrains' AND column_name = 'rgpd_prefs'
  ) THEN
    ALTER TABLE parrains ADD COLUMN rgpd_prefs JSONB DEFAULT '{"notifs":true,"whatsapp":true,"leaderboard":true,"email":false}'::JSONB;
    RAISE NOTICE 'Colonne rgpd_prefs ajoutée à parrains';
  ELSE
    RAISE NOTICE 'Colonne rgpd_prefs existe déjà';
  END IF;
END $$;

-- 2. Ajouter la colonne rgpd_consent (JSONB) pour tracer le consentement
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'parrains' AND column_name = 'rgpd_consent'
  ) THEN
    ALTER TABLE parrains ADD COLUMN rgpd_consent JSONB DEFAULT NULL;
    RAISE NOTICE 'Colonne rgpd_consent ajoutée';
  ELSE
    RAISE NOTICE 'Colonne rgpd_consent existe déjà';
  END IF;
END $$;

-- 3. Initialiser les préférences par défaut pour les parrains existants qui n'en ont pas
UPDATE parrains 
SET rgpd_prefs = '{"notifs":true,"whatsapp":true,"leaderboard":true,"email":false}'::JSONB
WHERE rgpd_prefs IS NULL;

-- ─────────────────────────────────────────────────────────────────────
-- Rollback (si besoin) :
-- ALTER TABLE parrains DROP COLUMN IF EXISTS rgpd_prefs;
-- ALTER TABLE parrains DROP COLUMN IF EXISTS rgpd_consent;
-- ─────────────────────────────────────────────────────────────────────
