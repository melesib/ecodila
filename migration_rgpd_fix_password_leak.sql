-- ══════════════════════════════════════════════════════════════
-- ECODILA — CORRECTIF URGENT : trigger RGPD sans fuite password
-- ══════════════════════════════════════════════════════════════
-- À exécuter dans Supabase SQL Editor
--
-- Contexte : une entrée existante dans rgpd_audit_log contient
-- un password hashé + fingerprint + IP d'un utilisateur supprimé.
-- Ce script :
--   1. Met à jour le trigger log_rgpd_deletion pour filtrer les champs sensibles
--   2. Nettoie les entrées existantes compromises
--   3. Vérifie que tout est en ordre
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
-- 1. METTRE À JOUR LE TRIGGER (filtre les champs sensibles)
-- ══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION log_rgpd_deletion() RETURNS TRIGGER AS $$
DECLARE
    v_row_json jsonb;
    v_clean_json jsonb;
BEGIN
    -- Convertir la ligne en JSON
    v_row_json := to_jsonb(OLD);

    -- Retirer tous les champs sensibles (sécurité, anti-fraude, IP, tokens)
    v_clean_json := v_row_json
        - 'password'
        - 'passwordHash'
        - 'passwordhash'
        - 'token'
        - 'secret'
        - 'apiKey'
        - 'fingerprint'
        - 'ip'
        - 'ipCity'
        - 'ipCountry'
        - 'ipRegion'
        - 'ipOrg'
        - 'ipTimezone'
        - 'ipHistory'
        - 'iphistory'
        - 'ipRetro'
        - 'registrationIp'
        - 'registrationip'
        - 'registerIp'
        - 'fraudScore'
        - 'fraudscore'
        - 'suspiciousIp'
        - 'suspiciousip'
        - 'suspiciousReason'
        - 'registrationCity'
        - 'registrationCountry';

    INSERT INTO rgpd_audit_log (operation, table_name, row_id, details)
    VALUES (
        TG_OP,
        TG_TABLE_NAME,
        COALESCE(OLD.id::text, 'unknown'),
        jsonb_build_object(
            'deleted_at', now(),
            'row_safe', v_clean_json
        )
    );
    RETURN OLD;
EXCEPTION WHEN OTHERS THEN
    -- Ne JAMAIS bloquer la suppression à cause d'un problème de log
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ══════════════════════════════════════════════════════════════
-- 2. NETTOYER LES ENTRÉES EXISTANTES COMPROMISES
-- ══════════════════════════════════════════════════════════════
-- Parcourt toutes les entrées existantes dans rgpd_audit_log
-- et retire les champs sensibles de details.row (ancien format)
-- ══════════════════════════════════════════════════════════════

UPDATE rgpd_audit_log
SET details = jsonb_build_object(
    'deleted_at', COALESCE(details->>'deleted_at', ts::text),
    'sanitized_at', now()::text,
    'row_safe', COALESCE(details->'row', details->'row_safe', '{}'::jsonb)
        - 'password'
        - 'passwordHash'
        - 'passwordhash'
        - 'token'
        - 'secret'
        - 'apiKey'
        - 'fingerprint'
        - 'ip'
        - 'ipCity'
        - 'ipCountry'
        - 'ipRegion'
        - 'ipOrg'
        - 'ipTimezone'
        - 'ipHistory'
        - 'iphistory'
        - 'ipRetro'
        - 'registrationIp'
        - 'registrationip'
        - 'registerIp'
        - 'fraudScore'
        - 'fraudscore'
        - 'suspiciousIp'
        - 'suspiciousip'
        - 'suspiciousReason'
        - 'registrationCity'
        - 'registrationCountry'
)
WHERE details ? 'row' OR details ? 'row_safe';


-- ══════════════════════════════════════════════════════════════
-- 3. VÉRIFICATION
-- ══════════════════════════════════════════════════════════════

-- a) Confirmer que le nouveau trigger est actif (doit contenir 'v_clean_json')
SELECT
    'Trigger actif avec filtre sensibles :' AS check_name,
    CASE
        WHEN prosrc LIKE '%v_clean_json%' THEN '✅ OUI'
        ELSE '❌ NON — le trigger n''est pas à jour'
    END AS status
FROM pg_proc
WHERE proname = 'log_rgpd_deletion';

-- b) Vérifier qu'aucune entrée ne contient encore de password
SELECT
    'Entrées avec password restantes :' AS check_name,
    COUNT(*)::text AS count
FROM rgpd_audit_log
WHERE details::text LIKE '%password%'
   OR details::text LIKE '%fingerprint%'
   OR details::text LIKE '%registrationIp%';
-- Doit retourner 0

-- c) Afficher un échantillon des logs nettoyés
SELECT
    row_id,
    table_name,
    ts,
    CASE
        WHEN details ? 'row_safe' THEN '✅ nettoyé (row_safe)'
        WHEN details ? 'row' THEN '❌ ancien format (row)'
        ELSE '— format inconnu'
    END AS format,
    CASE
        WHEN details->'row_safe' ? 'password' THEN '❌ fuite password'
        WHEN details->'row' ? 'password' THEN '❌ fuite password (ancien format)'
        ELSE '✅ pas de password'
    END AS password_check
FROM rgpd_audit_log
ORDER BY ts DESC
LIMIT 10;


-- ══════════════════════════════════════════════════════════════
-- 4. TEST FONCTIONNEL (créer + supprimer un user test)
-- ══════════════════════════════════════════════════════════════
-- Décommentez ce bloc pour tester que le nouveau trigger filtre bien
-- ══════════════════════════════════════════════════════════════

/*
-- Créer un user test
INSERT INTO users (id, nom, telephone, password, "dateCreation")
VALUES (
    'TEST-TRIGGER-' || extract(epoch from now())::text,
    'Test Trigger',
    '+2250700000099',
    'SECRET_PASSWORD_HASH_TEST',
    now()
);

-- Récupérer son ID pour le supprimer
DO $$
DECLARE
    v_test_id text;
BEGIN
    SELECT id INTO v_test_id FROM users
    WHERE nom = 'Test Trigger'
    ORDER BY "dateCreation" DESC
    LIMIT 1;

    DELETE FROM users WHERE id = v_test_id;

    RAISE NOTICE 'Test ID: %', v_test_id;
END $$;

-- Vérifier le dernier log — doit être sans password
SELECT details
FROM rgpd_audit_log
WHERE table_name = 'users'
ORDER BY ts DESC
LIMIT 1;
-- Doit montrer "row_safe" SANS le champ "password"
*/
