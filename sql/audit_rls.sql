-- ════════════════════════════════════════════════════════════════════
-- EcoDila — AUDIT RLS (à exécuter dans Supabase SQL Editor)
-- ════════════════════════════════════════════════════════════════════
--
-- Ce script ne MODIFIE rien. Il liste l'état actuel des politiques RLS
-- sur toutes les tables du schéma public.
--
-- USAGE :
--   1. Aller sur Supabase Dashboard → SQL Editor → New query
--   2. Coller ce script
--   3. Cliquer "Run"
--   4. Examiner les résultats — chercher en particulier :
--      - Tables avec rls_enabled = FALSE → CRITIQUE, à activer
--      - Politiques avec USING (TRUE) → permissives, à durcir si donnée sensible
--
-- ════════════════════════════════════════════════════════════════════

-- 1. Tables du schéma public + état RLS
SELECT 
  schemaname,
  tablename,
  rowsecurity AS rls_enabled,
  CASE WHEN rowsecurity THEN '✓' ELSE '⚠️ DÉSACTIVÉ' END AS status,
  -- Nombre de policies définies sur cette table
  (SELECT COUNT(*) FROM pg_policies p WHERE p.schemaname = pt.schemaname AND p.tablename = pt.tablename) AS policies_count
FROM pg_tables pt
WHERE schemaname = 'public'
ORDER BY 
  rowsecurity ASC,  -- Les tables sans RLS d'abord (à fixer en priorité)
  tablename;


-- 2. Toutes les politiques RLS détaillées
SELECT 
  schemaname,
  tablename,
  policyname,
  CASE 
    WHEN cmd = 'ALL' THEN 'ALL (SELECT/INSERT/UPDATE/DELETE)'
    ELSE cmd 
  END AS commands,
  CASE 
    WHEN qual = 'true' THEN '⚠️ PERMISSIVE (USING TRUE)'
    WHEN qual IS NULL THEN '✓ INSERT-only (no USING needed)'
    ELSE '✓ Filtré'
  END AS using_status,
  qual AS using_clause,
  with_check AS check_clause,
  roles
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY 
  CASE WHEN qual = 'true' THEN 0 ELSE 1 END,  -- Permissives d'abord
  tablename,
  policyname;


-- 3. Tables sensibles SANS aucune RLS (= lecture publique via anon key !)
-- Cette liste est CRITIQUE à examiner
SELECT 
  '🚨 CRITIQUE — Table sensible sans RLS' AS alerte,
  tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND rowsecurity = FALSE
  AND tablename IN (
    -- Liste des tables à RLS-prioriser identifiées dans la doc 02-base-de-donnees-supabase.md
    'users',
    'parrains',
    'admins',
    'auditaz_users',
    'orders',
    'propositions',
    'trocs',
    'parrain_commissions',
    'parrain_paiements',
    'parrain_concours',
    'parrain_statuts',
    'concours_paiements',
    'chat_conversations',
    'chat_tickets',
    'conversations',
    'avis',
    'visitors',
    'product_views',
    'notifications',
    'challenges',
    'cart_history',
    'coupons',
    'error_logs',
    'rgpd_audit_log',
    'auditaz_activity',
    'auditaz_transfers',
    'auditaz_resolved',
    'auditaz_banned_ips',
    'auditaz_blocked_users',
    'auditaz_config',
    'auditaz_permissions',
    'offers',
    'offer_logs',
    'nego_abandoned',
    'settings'
  );


-- 4. Permissions accordées aux rôles anon et authenticated par table
-- Si anon a SELECT sur une table de PII → potentiel problème
SELECT 
  tg.table_name,
  tg.grantee,
  STRING_AGG(tg.privilege_type, ', ' ORDER BY tg.privilege_type) AS privileges
FROM information_schema.role_table_grants tg
WHERE tg.table_schema = 'public'
  AND tg.grantee IN ('anon', 'authenticated')
GROUP BY tg.table_name, tg.grantee
ORDER BY tg.table_name, tg.grantee;


-- 5. Checklist humaine à compléter en regardant les résultats ci-dessus
-- Pour chaque table sensible (users, orders, parrain_*, chat_*, ...) :
--   [ ] RLS activée (Q1) ?
--   [ ] Au moins une policy SELECT non-permissive (Q2) ?
--   [ ] Pas de politique avec qual = 'true' (USING TRUE) sur des PII ?
--   [ ] Si anon a SELECT (Q4) → vérifier que les RLS protègent
--
-- Si une table a RLS = FALSE OU qual = 'true' sur des PII → DURCIR
-- (utiliser harden_rls.sql ou rédiger des policies sur mesure)
