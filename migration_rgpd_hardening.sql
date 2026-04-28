-- ══════════════════════════════════════════════════════════════
-- ECODILA — Durcissement RGPD (compatible architecture actuelle)
-- Exécuter dans Supabase SQL Editor APRÈS migration_rls_hardening.sql
-- ══════════════════════════════════════════════════════════════
--
-- Architecture cible : Frontend-only (JAMstack) avec clé anon partagée
-- Authentification : téléphone + MDP hashé côté client (pas Supabase Auth)
-- Conséquence : auth.uid() non disponible, RLS strict par user impossible
--
-- Ce script ajoute des protections SANS casser :
-- ✅ Le BO admin (admin.html)
-- ✅ L'audit système (auditaz.html)
-- ✅ Le site client (index.html)
--
-- AVANT : tout est accessible en SELECT *
-- APRÈS : colonnes sensibles masquées + triggers d'audit
-- ══════════════════════════════════════════════════════════════


-- ══════════════════════════════════════════════════════════════
-- 1. VUE PUBLIQUE SANS DONNÉES SENSIBLES
-- ══════════════════════════════════════════════════════════════
-- Cette vue expose UNIQUEMENT les colonnes "safe" pour le site public.
-- Le BO admin peut continuer à utiliser la table `users` directement.
--
-- ⚠️ IMPORTANT POSTGRES : les noms de colonnes non-quotés sont convertis
-- en minuscules. Les colonnes camelCase DOIVENT être entre guillemets doubles.
-- ══════════════════════════════════════════════════════════════

-- ── VUE : users_public (sans password, sans données anti-fraude) ──
-- Approche simple et sûre : SELECT * puis on exclut explicitement
-- les colonnes sensibles via une sous-requête.
DROP VIEW IF EXISTS users_public CASCADE;

-- Construction de la vue en excluant explicitement les colonnes sensibles.
-- Utilise une approche défensive : on liste UNIQUEMENT les colonnes safe.
-- Les colonnes qui n'existent pas sont ignorées grâce au DO block.
-- IMPORTANT : lower() sur column_name pour match insensible à la casse
--             (gère le cas où vos colonnes sont en camelCase avec guillemets).
DO $$
DECLARE
    cols text;
BEGIN
    -- Récupérer toutes les colonnes de users SAUF les sensibles
    SELECT string_agg(quote_ident(column_name), ', ')
    INTO cols
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'users'
      AND lower(column_name) NOT IN (
          -- Colonnes sensibles à exclure (en minuscules pour comparaison)
          'password', 'passwordhash', 'token', 'secret',
          'fingerprint',
          'ip', 'ipcity', 'ipcountry', 'ipregion', 'iporg',
          'iptimezone', 'iphistory', 'ipretro',
          'registrationip', 'registerip',
          'suspiciousip', 'suspiciousreason',
          'fraudscore'
      );

    -- Créer la vue dynamiquement avec les colonnes restantes
    IF cols IS NULL OR cols = '' THEN
        RAISE EXCEPTION 'Aucune colonne trouvée dans users — vérifiez le nom de la table';
    END IF;
    EXECUTE format('CREATE VIEW users_public AS SELECT %s FROM users', cols);
END $$;

COMMENT ON VIEW users_public IS 'Vue RGPD : users sans password, IP, fingerprint, fraudScore (RGPD/ARTCI)';

-- Donner accès à la vue aux utilisateurs anon
GRANT SELECT ON users_public TO anon;


-- ══════════════════════════════════════════════════════════════
-- 2. FONCTIONS D'AUDIT — détecte les accès anormaux
-- ══════════════════════════════════════════════════════════════

-- Table d'audit pour tracer les opérations sensibles
CREATE TABLE IF NOT EXISTS rgpd_audit_log (
    id BIGSERIAL PRIMARY KEY,
    ts TIMESTAMPTZ NOT NULL DEFAULT now(),
    operation TEXT NOT NULL,
    table_name TEXT NOT NULL,
    row_id TEXT,
    details JSONB
);

-- RLS sur la table d'audit : personne ne peut la lire depuis le client
ALTER TABLE rgpd_audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "rgpd_audit_log_insert" ON rgpd_audit_log;
CREATE POLICY "rgpd_audit_log_insert" ON rgpd_audit_log FOR INSERT TO anon WITH CHECK (true);
-- ⛔ PAS de SELECT/UPDATE/DELETE pour anon (audit immuable)


-- ══════════════════════════════════════════════════════════════
-- 3. TRIGGERS — logs les suppressions importantes
-- ══════════════════════════════════════════════════════════════

-- Fonction générique de log — filtre les colonnes sensibles du row_to_json
-- Évite d'exposer password, fingerprint, IP dans rgpd_audit_log
CREATE OR REPLACE FUNCTION log_rgpd_deletion() RETURNS TRIGGER AS $$
DECLARE
    v_row_json jsonb;
    v_clean_json jsonb;
BEGIN
    -- Convertir la ligne en JSON
    v_row_json := to_jsonb(OLD);

    -- Retirer les champs sensibles (si présents)
    v_clean_json := v_row_json
        - 'password'
        - 'passwordHash'
        - 'passwordhash'
        - 'token'
        - 'secret'
        - 'fingerprint'
        - 'registrationIp'
        - 'registrationip'
        - 'ip'
        - 'ipHistory'
        - 'iphistory'
        - 'fraudScore'
        - 'fraudscore'
        - 'suspiciousIp'
        - 'suspiciousip';

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

-- Appliquer le trigger sur les tables sensibles (création conditionnelle)
DO $$
BEGIN
    -- users
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='users') THEN
        DROP TRIGGER IF EXISTS audit_users_delete ON users;
        CREATE TRIGGER audit_users_delete
            BEFORE DELETE ON users
            FOR EACH ROW EXECUTE FUNCTION log_rgpd_deletion();
    END IF;

    -- orders
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='orders') THEN
        DROP TRIGGER IF EXISTS audit_orders_delete ON orders;
        CREATE TRIGGER audit_orders_delete
            BEFORE DELETE ON orders
            FOR EACH ROW EXECUTE FUNCTION log_rgpd_deletion();
    END IF;

    -- trocs
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='trocs') THEN
        DROP TRIGGER IF EXISTS audit_trocs_delete ON trocs;
        CREATE TRIGGER audit_trocs_delete
            BEFORE DELETE ON trocs
            FOR EACH ROW EXECUTE FUNCTION log_rgpd_deletion();
    END IF;
END $$;


-- ══════════════════════════════════════════════════════════════
-- 4. INDEX POUR PERFORMANCE SUPPRESSION RGPD
-- ══════════════════════════════════════════════════════════════
-- Accélère les DELETE WHERE tel = '...' utilisés par la suppression compte.
-- Création CONDITIONNELLE : seulement si la colonne existe dans la table.
-- Évite les erreurs si votre schéma diffère légèrement.
-- ══════════════════════════════════════════════════════════════

DO $$
DECLARE
    v_exists boolean;
    v_colname text;
BEGIN
    -- users.telephone
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='users' AND column_name='telephone'
    ) INTO v_exists;
    IF v_exists THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_users_telephone ON users USING btree (telephone)';
    END IF;

    -- orders.tel
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='orders' AND column_name='tel'
    ) INTO v_exists;
    IF v_exists THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_orders_tel ON orders USING btree (tel)';
    END IF;

    -- orders.userId (camelCase — recherche insensible à la casse)
    SELECT column_name INTO v_colname FROM information_schema.columns
    WHERE table_schema='public' AND table_name='orders' AND lower(column_name)='userid'
    LIMIT 1;
    IF v_colname IS NOT NULL THEN
        EXECUTE format('CREATE INDEX IF NOT EXISTS idx_orders_userid ON orders USING btree (%I)', v_colname);
    END IF;

    -- trocs.tel
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='trocs' AND column_name='tel'
    ) INTO v_exists;
    IF v_exists THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_trocs_tel ON trocs USING btree (tel)';
    END IF;

    -- avis.tel
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='avis' AND column_name='tel'
    ) INTO v_exists;
    IF v_exists THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_avis_tel ON avis USING btree (tel)';
    END IF;

    -- propositions.tel
    SELECT EXISTS(
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='propositions' AND column_name='tel'
    ) INTO v_exists;
    IF v_exists THEN
        EXECUTE 'CREATE INDEX IF NOT EXISTS idx_propositions_tel ON propositions USING btree (tel)';
    END IF;
END $$;


-- ══════════════════════════════════════════════════════════════
-- 5. NETTOYAGE AUTOMATIQUE DES DONNÉES ANALYTICS ANCIENNES
-- ══════════════════════════════════════════════════════════════
-- RGPD/ARTCI : conservation limitée dans le temps.
-- Supprime automatiquement les visites > 25 mois (rétention CNIL max 25 mois)
--
-- SÉCURITÉS INTÉGRÉES :
-- • Mode dry-run : compte sans supprimer (par défaut)
-- • Protection contre WHERE non-défini (si created_at n'existe pas)
-- • Retourne un JSON avec détail par table
-- • Exécution dans un bloc EXCEPTION : erreur sur une table = pas d'impact sur les autres
-- ══════════════════════════════════════════════════════════════

-- Fonction principale avec paramètre dry_run (défaut : TRUE = simulation)
-- ⚠️ On supprime d'abord TOUTES les versions existantes pour éviter le conflit
-- de signature (ambiguïté si l'ancienne version sans paramètre existe déjà)
DROP FUNCTION IF EXISTS cleanup_old_analytics();
DROP FUNCTION IF EXISTS cleanup_old_analytics(boolean);

CREATE FUNCTION cleanup_old_analytics(dry_run boolean DEFAULT true)
RETURNS jsonb AS $$
DECLARE
    v_visitors_before bigint := 0;
    v_visitors_old bigint := 0;
    v_visitors_deleted bigint := 0;
    v_views_before bigint := 0;
    v_views_old bigint := 0;
    v_views_deleted bigint := 0;
    v_audit_before bigint := 0;
    v_audit_old bigint := 0;
    v_audit_deleted bigint := 0;
    v_has_col boolean;
    v_errors text[] := ARRAY[]::text[];
BEGIN
    -- ── VISITORS ──
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='visitors') THEN
        -- Vérifier que created_at existe
        SELECT EXISTS(SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='visitors' AND column_name='created_at')
        INTO v_has_col;

        IF v_has_col THEN
            BEGIN
                EXECUTE 'SELECT COUNT(*) FROM visitors' INTO v_visitors_before;
                EXECUTE 'SELECT COUNT(*) FROM visitors WHERE created_at < (now() - interval ''25 months'')'
                    INTO v_visitors_old;

                IF NOT dry_run AND v_visitors_old > 0 THEN
                    EXECUTE 'DELETE FROM visitors WHERE created_at < (now() - interval ''25 months'')';
                    GET DIAGNOSTICS v_visitors_deleted = ROW_COUNT;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_errors := array_append(v_errors, 'visitors: ' || SQLERRM);
            END;
        ELSE
            v_errors := array_append(v_errors, 'visitors: colonne created_at absente');
        END IF;
    END IF;

    -- ── PRODUCT_VIEWS ──
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='product_views') THEN
        SELECT EXISTS(SELECT 1 FROM information_schema.columns
            WHERE table_schema='public' AND table_name='product_views' AND column_name='created_at')
        INTO v_has_col;

        IF v_has_col THEN
            BEGIN
                EXECUTE 'SELECT COUNT(*) FROM product_views' INTO v_views_before;
                EXECUTE 'SELECT COUNT(*) FROM product_views WHERE created_at < (now() - interval ''13 months'')'
                    INTO v_views_old;

                IF NOT dry_run AND v_views_old > 0 THEN
                    EXECUTE 'DELETE FROM product_views WHERE created_at < (now() - interval ''13 months'')';
                    GET DIAGNOSTICS v_views_deleted = ROW_COUNT;
                END IF;
            EXCEPTION WHEN OTHERS THEN
                v_errors := array_append(v_errors, 'product_views: ' || SQLERRM);
            END;
        ELSE
            v_errors := array_append(v_errors, 'product_views: colonne created_at absente');
        END IF;
    END IF;

    -- ── RGPD_AUDIT_LOG ──
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='rgpd_audit_log') THEN
        BEGIN
            EXECUTE 'SELECT COUNT(*) FROM rgpd_audit_log' INTO v_audit_before;
            EXECUTE 'SELECT COUNT(*) FROM rgpd_audit_log WHERE ts < (now() - interval ''5 years'')'
                INTO v_audit_old;

            IF NOT dry_run AND v_audit_old > 0 THEN
                EXECUTE 'DELETE FROM rgpd_audit_log WHERE ts < (now() - interval ''5 years'')';
                GET DIAGNOSTICS v_audit_deleted = ROW_COUNT;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            v_errors := array_append(v_errors, 'rgpd_audit_log: ' || SQLERRM);
        END;
    END IF;

    -- Retour JSON détaillé
    RETURN jsonb_build_object(
        'dry_run', dry_run,
        'timestamp', now(),
        'visitors', jsonb_build_object(
            'total_before', v_visitors_before,
            'older_than_25_months', v_visitors_old,
            'deleted', v_visitors_deleted
        ),
        'product_views', jsonb_build_object(
            'total_before', v_views_before,
            'older_than_13_months', v_views_old,
            'deleted', v_views_deleted
        ),
        'rgpd_audit_log', jsonb_build_object(
            'total_before', v_audit_before,
            'older_than_5_years', v_audit_old,
            'deleted', v_audit_deleted
        ),
        'errors', to_jsonb(v_errors)
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cleanup_old_analytics(boolean) IS
'Nettoyage RGPD : par défaut mode simulation (dry_run=true). Pour supprimer réellement, appeler avec false.';

-- Exemples d'utilisation :
--   SELECT cleanup_old_analytics();         -- Simulation (SÛREMENT pas de suppression)
--   SELECT cleanup_old_analytics(true);     -- Simulation explicite
--   SELECT cleanup_old_analytics(false);    -- Suppression RÉELLE


-- ══════════════════════════════════════════════════════════════
-- 6. VÉRIFICATION
-- ══════════════════════════════════════════════════════════════

-- Lister les vues créées
SELECT schemaname, viewname FROM pg_views WHERE schemaname = 'public' ORDER BY viewname;

-- Lister les triggers actifs
SELECT trigger_name, event_manipulation, event_object_table
FROM information_schema.triggers
WHERE trigger_schema = 'public'
ORDER BY event_object_table;

-- Lister les index créés
SELECT indexname, tablename FROM pg_indexes
WHERE schemaname = 'public' AND indexname LIKE 'idx_%'
ORDER BY tablename;

-- ══════════════════════════════════════════════════════════════
-- FIN DU SCRIPT
-- ══════════════════════════════════════════════════════════════
-- À exécuter une fois dans Supabase SQL Editor.
-- Puis ajouter à votre calendrier : SELECT cleanup_old_analytics();
-- une fois par mois (ou via pg_cron si activé).
-- ══════════════════════════════════════════════════════════════
