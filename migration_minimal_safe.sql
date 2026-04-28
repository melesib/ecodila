-- ═══════════════════════════════════════════════════════════════════════════
-- 🎯 ECODILA — MIGRATION MINIMALE SÉCURISÉE
-- ═══════════════════════════════════════════════════════════════════════════
-- Adaptée à TON schéma existant :
--   ✅ log_rgpd_deletion() existe déjà
--   ✅ Triggers users/orders/trocs existent déjà
--   ✅ Table auditaz_activity existe déjà (pas besoin de auditaz_events)
--
-- Ce script ajoute UNIQUEMENT les éléments manquants, sans rien casser.
-- 100% idempotent (exécutable plusieurs fois sans risque)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1. COLONNES RGPD SUR parrains (le point critique qui manque)
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- rgpd_prefs (préférences : notifs, whatsapp, leaderboard, email)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'parrains' AND column_name = 'rgpd_prefs'
  ) THEN
    ALTER TABLE parrains ADD COLUMN rgpd_prefs JSONB DEFAULT '{"notifs":true,"whatsapp":true,"leaderboard":true,"email":false}'::JSONB;
    RAISE NOTICE '✅ Colonne rgpd_prefs ajoutée';
  ELSE
    RAISE NOTICE '↻  rgpd_prefs existe déjà';
  END IF;

  -- rgpd_consent (traçabilité consentement)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'parrains' AND column_name = 'rgpd_consent'
  ) THEN
    ALTER TABLE parrains ADD COLUMN rgpd_consent JSONB DEFAULT NULL;
    RAISE NOTICE '✅ Colonne rgpd_consent ajoutée';
  ELSE
    RAISE NOTICE '↻  rgpd_consent existe déjà';
  END IF;

  -- deleted_at (soft-delete RGPD)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'parrains' AND column_name = 'deleted_at'
  ) THEN
    ALTER TABLE parrains ADD COLUMN deleted_at TIMESTAMPTZ;
    RAISE NOTICE '✅ Colonne deleted_at ajoutée à parrains';
  ELSE
    RAISE NOTICE '↻  deleted_at existe déjà sur parrains';
  END IF;

  -- anonymized_at (trace anonymisation)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'parrains' AND column_name = 'anonymized_at'
  ) THEN
    ALTER TABLE parrains ADD COLUMN anonymized_at TIMESTAMPTZ;
    RAISE NOTICE '✅ Colonne anonymized_at ajoutée à parrains';
  ELSE
    RAISE NOTICE '↻  anonymized_at existe déjà sur parrains';
  END IF;
END $$;

-- Initialiser les préférences par défaut pour les parrains sans prefs
UPDATE parrains 
SET rgpd_prefs = '{"notifs":true,"whatsapp":true,"leaderboard":true,"email":false}'::JSONB
WHERE rgpd_prefs IS NULL;

-- ─────────────────────────────────────────────────────────────────────────
-- 2. COLONNES RGPD SUR users (anonymisation / soft-delete)
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'deleted_at'
  ) THEN
    ALTER TABLE users ADD COLUMN deleted_at TIMESTAMPTZ;
    RAISE NOTICE '✅ Colonne deleted_at ajoutée à users';
  ELSE
    RAISE NOTICE '↻  deleted_at existe déjà sur users';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'anonymized_at'
  ) THEN
    ALTER TABLE users ADD COLUMN anonymized_at TIMESTAMPTZ;
    RAISE NOTICE '✅ Colonne anonymized_at ajoutée à users';
  ELSE
    RAISE NOTICE '↻  anonymized_at existe déjà sur users';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 3. AJOUTER TRIGGER RGPD SUR parrains (il manque dans ton schéma)
-- ─────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger 
    WHERE tgname = 'audit_parrains_delete'
  ) THEN
    EXECUTE 'CREATE TRIGGER audit_parrains_delete 
             BEFORE DELETE ON parrains 
             FOR EACH ROW 
             EXECUTE FUNCTION log_rgpd_deletion()';
    RAISE NOTICE '✅ Trigger audit_parrains_delete créé';
  ELSE
    RAISE NOTICE '↻  Trigger audit_parrains_delete existe déjà';
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────────────────
-- 4. FONCTIONS D'ANONYMISATION (utiles pour suppression RGPD)
-- ─────────────────────────────────────────────────────────────────────────
-- Anonymiser un utilisateur (ex: Art. 17 droit à l'oubli)
CREATE OR REPLACE FUNCTION rgpd_anonymize_user(p_user_id TEXT) RETURNS VOID AS $$
BEGIN
  UPDATE users 
  SET 
    nom = 'Utilisateur supprimé',
    prenom = NULL,
    email = 'anonymized_' || p_user_id || '@ecodila.invalid',
    tel = NULL,
    wa = NULL,
    password = NULL,
    "passwordHash" = NULL,
    anonymized_at = NOW()
  WHERE id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Anonymiser un parrain (ex: Art. 17 droit à l'oubli)
CREATE OR REPLACE FUNCTION rgpd_anonymize_parrain(p_parrain_id TEXT) RETURNS VOID AS $$
BEGIN
  UPDATE parrains 
  SET 
    nom = 'Parrain supprimé',
    email = 'anonymized_' || p_parrain_id || '@ecodila.invalid',
    tel = NULL,
    wa = NULL,
    rib = NULL,
    password = NULL,
    "loginPwd" = NULL,
    "loginPwdHash" = NULL,
    anonymized_at = NOW()
  WHERE id = p_parrain_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─────────────────────────────────────────────────────────────────────────
-- 5. FONCTION D'AUDIT DES ACCÈS (Art. 30 RGPD)
-- ─────────────────────────────────────────────────────────────────────────
-- On utilise la table auditaz_activity qui existe déjà
CREATE OR REPLACE FUNCTION audit_rgpd_access(
  p_table TEXT,
  p_user_id TEXT,
  p_context TEXT DEFAULT NULL
) RETURNS VOID AS $$
BEGIN
  -- Enregistrer dans auditaz_activity (table déjà en place)
  INSERT INTO auditaz_activity (event_type, message, meta, created_at)
  VALUES (
    'rgpd_access_' || p_table,
    'RGPD access: ' || p_table,
    jsonb_build_object(
      'context', p_context, 
      'accessed_by', p_user_id, 
      'table', p_table
    ),
    NOW()
  );
EXCEPTION 
  WHEN undefined_table THEN
    -- Si auditaz_activity n'a pas ces colonnes, ignorer silencieusement
    NULL;
  WHEN undefined_column THEN
    -- Fallback : juste log dans les notices
    RAISE NOTICE 'RGPD access: % by %', p_table, p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ═══════════════════════════════════════════════════════════════════════════
-- BILAN
-- ═══════════════════════════════════════════════════════════════════════════
DO $$
DECLARE
  v_nb INTEGER;
BEGIN
  RAISE NOTICE '';
  RAISE NOTICE '═══════════════════════════════════════════════════════';
  RAISE NOTICE '   BILAN — Migration RGPD';
  RAISE NOTICE '═══════════════════════════════════════════════════════';
  
  SELECT COUNT(*) INTO v_nb FROM information_schema.columns 
  WHERE table_name = 'parrains' AND column_name IN ('rgpd_prefs','rgpd_consent','deleted_at','anonymized_at');
  RAISE NOTICE '• Colonnes RGPD sur parrains : %/4', v_nb;

  SELECT COUNT(*) INTO v_nb FROM information_schema.columns 
  WHERE table_name = 'users' AND column_name IN ('deleted_at','anonymized_at');
  RAISE NOTICE '• Colonnes RGPD sur users    : %/2', v_nb;

  SELECT COUNT(*) INTO v_nb FROM pg_proc 
  WHERE proname IN ('rgpd_anonymize_user','rgpd_anonymize_parrain','audit_rgpd_access');
  RAISE NOTICE '• Fonctions RGPD             : %/3', v_nb;

  SELECT COUNT(*) INTO v_nb FROM pg_trigger 
  WHERE tgname IN ('audit_users_delete','audit_parrains_delete','audit_orders_delete','audit_trocs_delete');
  RAISE NOTICE '• Triggers audit             : %/4', v_nb;

  RAISE NOTICE '';
  RAISE NOTICE '✅ Migration terminée';
  RAISE NOTICE '═══════════════════════════════════════════════════════';
END $$;
