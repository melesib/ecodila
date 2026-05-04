-- ════════════════════════════════════════════════════════════════════
-- EcoDila — HARDENING RLS (à exécuter APRÈS audit_rls.sql)
-- ════════════════════════════════════════════════════════════════════
--
-- ⚠️ AVANT D'EXÉCUTER :
--   1. AVOIR FAIT UN BACKUP COMPLET DE LA DB
--      → Supabase Dashboard → Database → Backups → Manual backup
--      OU pg_dump --schema=public > backup-$(date +%Y%m%d).sql
--
--   2. AVOIR LU LES RÉSULTATS DE audit_rls.sql
--
--   3. TESTER EN STAGING SI POSSIBLE
--      Le code applicatif est conçu pour le mode permissif actuel.
--      Un durcissement brutal peut casser certaines fonctionnalités.
--
-- ⚠️ Ce script applique une stratégie DÉFENSE EN PROFONDEUR :
--   - SELECT permis pour tout le monde (le filtrage business se fait côté
--     app via _currentUser, _currentParrain, etc.)
--   - INSERT permis pour tout le monde (anon doit pouvoir s'inscrire)
--   - UPDATE/DELETE restreints au service_role (Edge Functions)
--   OU restreints à la propre row de l'utilisateur
--
-- POUR ALLER PLUS LOIN :
--   Activer Supabase Auth pour gérer auth.uid() proprement, et restreindre
--   SELECT à auth.uid() = user_id sur les tables sensibles.
--   Ça nécessite de migrer le login custom actuel vers Supabase Auth.
--
-- ════════════════════════════════════════════════════════════════════

BEGIN;

-- ────────────────────────────────────────────────────────────────────
-- TABLE : users (clients du site)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.users ENABLE ROW LEVEL SECURITY;

-- Lecture : autorisée (le filtrage par téléphone/login se fait côté app)
DROP POLICY IF EXISTS users_select_all ON public.users;
CREATE POLICY users_select_all ON public.users
  FOR SELECT USING (TRUE);

-- Insertion : autorisée (inscription publique)
DROP POLICY IF EXISTS users_insert_anon ON public.users;
CREATE POLICY users_insert_anon ON public.users
  FOR INSERT WITH CHECK (TRUE);

-- Mise à jour : autorisée (ex: profil, prefs RGPD) — le filtrage par
-- téléphone/login se fait côté app
DROP POLICY IF EXISTS users_update_all ON public.users;
CREATE POLICY users_update_all ON public.users
  FOR UPDATE USING (TRUE);

-- Suppression : INTERDITE depuis le client (anon/authenticated).
-- Pour supprimer un user : utiliser une Edge Function avec service_role,
-- OU passer par RGPD soft-delete (flag _softDeleted)
DROP POLICY IF EXISTS users_delete_none ON public.users;
-- Pas de policy DELETE = aucun DELETE possible


-- ────────────────────────────────────────────────────────────────────
-- TABLE : parrains
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.parrains ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS parrains_select_all ON public.parrains;
CREATE POLICY parrains_select_all ON public.parrains
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS parrains_insert_anon ON public.parrains;
CREATE POLICY parrains_insert_anon ON public.parrains
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS parrains_update_all ON public.parrains;
CREATE POLICY parrains_update_all ON public.parrains
  FOR UPDATE USING (TRUE);

-- Pas de DELETE depuis le client


-- ────────────────────────────────────────────────────────────────────
-- TABLE : orders (commandes)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.orders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS orders_select_all ON public.orders;
CREATE POLICY orders_select_all ON public.orders
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS orders_insert_anon ON public.orders;
CREATE POLICY orders_insert_anon ON public.orders
  FOR INSERT WITH CHECK (TRUE);

-- UPDATE limité (ne pas permettre la modification après création depuis client)
-- Si BO admin doit pouvoir modifier → utiliser service_role
DROP POLICY IF EXISTS orders_update_anon ON public.orders;
CREATE POLICY orders_update_anon ON public.orders
  FOR UPDATE USING (TRUE);


-- ────────────────────────────────────────────────────────────────────
-- TABLE : parrain_commissions (FINANCIER — sensible)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.parrain_commissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS parrain_commissions_select_all ON public.parrain_commissions;
CREATE POLICY parrain_commissions_select_all ON public.parrain_commissions
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS parrain_commissions_insert_anon ON public.parrain_commissions;
CREATE POLICY parrain_commissions_insert_anon ON public.parrain_commissions
  FOR INSERT WITH CHECK (TRUE);

-- ⚠️ Pas d'UPDATE depuis client (impossibilité d'augmenter sa commission)
-- Si BO admin doit pouvoir → service_role


-- ────────────────────────────────────────────────────────────────────
-- TABLE : parrain_paiements (FINANCIER CRITIQUE — Mobile Money)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.parrain_paiements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS parrain_paiements_select_all ON public.parrain_paiements;
CREATE POLICY parrain_paiements_select_all ON public.parrain_paiements
  FOR SELECT USING (TRUE);

-- INSERT autorisé (parrain peut demander un retrait)
DROP POLICY IF EXISTS parrain_paiements_insert_anon ON public.parrain_paiements;
CREATE POLICY parrain_paiements_insert_anon ON public.parrain_paiements
  FOR INSERT WITH CHECK (TRUE);

-- ⚠️ PAS d'UPDATE depuis client (un parrain ne doit pas pouvoir changer
-- "demande" → "effectue" par lui-même)
-- → Mise à jour réservée au service_role (BO Admin via Edge Function)


-- ────────────────────────────────────────────────────────────────────
-- TABLE : chat_conversations (MESSAGES — PII)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.chat_conversations ENABLE ROW LEVEL SECURITY;

-- Permissif (le filtrage par client_id se fait côté app)
-- ⚠️ Acceptable pour l'instant car le client_id est un téléphone normalisé
-- difficilement énumérable. Une amélioration future = restreindre par
-- auth.uid() après migration vers Supabase Auth.
DROP POLICY IF EXISTS chat_select_all ON public.chat_conversations;
CREATE POLICY chat_select_all ON public.chat_conversations
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS chat_insert_all ON public.chat_conversations;
CREATE POLICY chat_insert_all ON public.chat_conversations
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS chat_update_all ON public.chat_conversations;
CREATE POLICY chat_update_all ON public.chat_conversations
  FOR UPDATE USING (TRUE);


-- ────────────────────────────────────────────────────────────────────
-- TABLE : chat_tickets
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.chat_tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chat_tickets_select_all ON public.chat_tickets;
CREATE POLICY chat_tickets_select_all ON public.chat_tickets
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS chat_tickets_insert_all ON public.chat_tickets;
CREATE POLICY chat_tickets_insert_all ON public.chat_tickets
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS chat_tickets_update_all ON public.chat_tickets;
CREATE POLICY chat_tickets_update_all ON public.chat_tickets
  FOR UPDATE USING (TRUE);


-- ────────────────────────────────────────────────────────────────────
-- TABLE : avis
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.avis ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS avis_select_all ON public.avis;
CREATE POLICY avis_select_all ON public.avis
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS avis_insert_anon ON public.avis;
CREATE POLICY avis_insert_anon ON public.avis
  FOR INSERT WITH CHECK (TRUE);

-- UPDATE seulement par modération admin (pas d'UPDATE policy = pas autorisé)


-- ────────────────────────────────────────────────────────────────────
-- TABLE : products (lecture publique, écriture admin)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.products ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS products_select_all ON public.products;
CREATE POLICY products_select_all ON public.products
  FOR SELECT USING (TRUE);

-- INSERT/UPDATE/DELETE produits : RÉSERVÉ AU service_role (BO Admin)
-- Pas de policy = pas autorisé depuis anon/authenticated
-- → Si tu veux que le BO admin écrive en direct (sans Edge Function),
--   il faudra une policy supplémentaire. Mais c'est PLUS SÛR que ce soit
--   strictement service_role.


-- ────────────────────────────────────────────────────────────────────
-- TABLE : visitors
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.visitors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS visitors_insert_anon ON public.visitors;
CREATE POLICY visitors_insert_anon ON public.visitors
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS visitors_update_anon ON public.visitors;
CREATE POLICY visitors_update_anon ON public.visitors
  FOR UPDATE USING (TRUE);

-- SELECT : restreint (pas de besoin pour anon de lire la liste de visiteurs)
-- Pas de policy SELECT = pas autorisé


-- ────────────────────────────────────────────────────────────────────
-- TABLE : product_views
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.product_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS product_views_insert_anon ON public.product_views;
CREATE POLICY product_views_insert_anon ON public.product_views
  FOR INSERT WITH CHECK (TRUE);

-- SELECT : restreint au service_role (analytics admin uniquement)


-- ────────────────────────────────────────────────────────────────────
-- TABLE : notifications
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS notifications_select_all ON public.notifications;
CREATE POLICY notifications_select_all ON public.notifications
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS notifications_insert_anon ON public.notifications;
CREATE POLICY notifications_insert_anon ON public.notifications
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS notifications_update_all ON public.notifications;
CREATE POLICY notifications_update_all ON public.notifications
  FOR UPDATE USING (TRUE);


-- ────────────────────────────────────────────────────────────────────
-- TABLE : settings (configuration)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.settings ENABLE ROW LEVEL SECURITY;

-- Lecture publique des settings (le site public lit la config)
DROP POLICY IF EXISTS settings_select_all ON public.settings;
CREATE POLICY settings_select_all ON public.settings
  FOR SELECT USING (TRUE);

-- ⚠️ Écriture RÉSERVÉE au service_role (BO admin uniquement)
-- Pas de policy INSERT/UPDATE/DELETE = pas autorisé depuis anon
-- C'est CRITIQUE : sinon n'importe qui pourrait modifier les marges, etc.


-- ────────────────────────────────────────────────────────────────────
-- TABLE : admins (compte équipe — TRÈS sensible)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.admins ENABLE ROW LEVEL SECURITY;

-- ⚠️ AUCUNE policy = aucun accès depuis anon
-- Tout l'accès aux admins se fait via service_role (Edge Functions)
-- ou via les hashes locaux EcoSec côté admin.html (qui sont chiffrés)
-- Si tu lis admins depuis le BO via anon key → ça ne marchera plus.
-- Vérifier le code et router via service_role.


-- ────────────────────────────────────────────────────────────────────
-- TABLE : auditaz_users (idem admins)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.auditaz_users ENABLE ROW LEVEL SECURITY;
-- Aucune policy = aucun accès anon


-- ────────────────────────────────────────────────────────────────────
-- TABLE : error_logs (peut contenir des données sensibles)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.error_logs ENABLE ROW LEVEL SECURITY;

-- INSERT autorisé (pour que le client puisse logguer ses erreurs)
DROP POLICY IF EXISTS error_logs_insert_anon ON public.error_logs;
CREATE POLICY error_logs_insert_anon ON public.error_logs
  FOR INSERT WITH CHECK (TRUE);

-- SELECT réservé au service_role (pas de policy = pas d'accès anon)


-- ────────────────────────────────────────────────────────────────────
-- TABLE : rgpd_audit_log (légalement sensible)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.rgpd_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rgpd_audit_insert_anon ON public.rgpd_audit_log;
CREATE POLICY rgpd_audit_insert_anon ON public.rgpd_audit_log
  FOR INSERT WITH CHECK (TRUE);

-- SELECT/UPDATE/DELETE = service_role uniquement


-- ────────────────────────────────────────────────────────────────────
-- TABLES auditaz_* (sécurité interne)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.auditaz_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.auditaz_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.auditaz_resolved ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.auditaz_banned_ips ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.auditaz_blocked_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.auditaz_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.auditaz_permissions ENABLE ROW LEVEL SECURITY;

-- INSERT pour anon (logging d'événements depuis le site)
DROP POLICY IF EXISTS auditaz_activity_insert ON public.auditaz_activity;
CREATE POLICY auditaz_activity_insert ON public.auditaz_activity
  FOR INSERT WITH CHECK (TRUE);

-- SELECT/UPDATE/DELETE = service_role uniquement (Auditaz BO)
-- Comme auditaz s'authentifie aussi via Supabase anon key,
-- TU DEVRAS peut-être ajouter une policy SELECT pour que auditaz puisse lire.
-- → À tester APRÈS application de ce script. Si auditaz ne fonctionne plus,
--   ajouter :
--   CREATE POLICY auditaz_activity_select ON public.auditaz_activity
--     FOR SELECT USING (TRUE);


-- ────────────────────────────────────────────────────────────────────
-- TABLES nego (négociation)
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.offers ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.offer_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.nego_abandoned ENABLE ROW LEVEL SECURITY;

-- INSERT pour anon (logging négociation côté client)
DROP POLICY IF EXISTS offers_insert_anon ON public.offers;
CREATE POLICY offers_insert_anon ON public.offers
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS offer_logs_insert_anon ON public.offer_logs;
CREATE POLICY offer_logs_insert_anon ON public.offer_logs
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS nego_abandoned_insert_anon ON public.nego_abandoned;
CREATE POLICY nego_abandoned_insert_anon ON public.nego_abandoned
  FOR INSERT WITH CHECK (TRUE);

-- SELECT permissif (pour récupération côté BO admin)
DROP POLICY IF EXISTS offers_select_all ON public.offers;
CREATE POLICY offers_select_all ON public.offers FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS offer_logs_select_all ON public.offer_logs;
CREATE POLICY offer_logs_select_all ON public.offer_logs FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS nego_abandoned_select_all ON public.nego_abandoned;
CREATE POLICY nego_abandoned_select_all ON public.nego_abandoned FOR SELECT USING (TRUE);


-- ────────────────────────────────────────────────────────────────────
-- TABLES restantes : autres avec lecture publique
-- ────────────────────────────────────────────────────────────────────
ALTER TABLE IF EXISTS public.coupons ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS coupons_select_all ON public.coupons;
CREATE POLICY coupons_select_all ON public.coupons FOR SELECT USING (TRUE);

ALTER TABLE IF EXISTS public.challenges ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS challenges_select_all ON public.challenges;
CREATE POLICY challenges_select_all ON public.challenges FOR SELECT USING (TRUE);

ALTER TABLE IF EXISTS public.parrain_concours ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS parrain_concours_select_all ON public.parrain_concours;
CREATE POLICY parrain_concours_select_all ON public.parrain_concours FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS parrain_concours_insert_anon ON public.parrain_concours;
CREATE POLICY parrain_concours_insert_anon ON public.parrain_concours FOR INSERT WITH CHECK (TRUE);

ALTER TABLE IF EXISTS public.parrain_statuts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS parrain_statuts_select_all ON public.parrain_statuts;
CREATE POLICY parrain_statuts_select_all ON public.parrain_statuts FOR SELECT USING (TRUE);

ALTER TABLE IF EXISTS public.concours_paiements ENABLE ROW LEVEL SECURITY;
-- ⚠️ Pas de SELECT anon (sensible financièrement) → service_role uniquement

ALTER TABLE IF EXISTS public.trocs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS trocs_select_all ON public.trocs;
CREATE POLICY trocs_select_all ON public.trocs FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS trocs_insert_anon ON public.trocs;
CREATE POLICY trocs_insert_anon ON public.trocs FOR INSERT WITH CHECK (TRUE);

ALTER TABLE IF EXISTS public.propositions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS propositions_select_all ON public.propositions;
CREATE POLICY propositions_select_all ON public.propositions FOR SELECT USING (TRUE);
DROP POLICY IF EXISTS propositions_insert_anon ON public.propositions;
CREATE POLICY propositions_insert_anon ON public.propositions FOR INSERT WITH CHECK (TRUE);

ALTER TABLE IF EXISTS public.cart_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cart_history_insert_anon ON public.cart_history;
CREATE POLICY cart_history_insert_anon ON public.cart_history FOR INSERT WITH CHECK (TRUE);


-- ────────────────────────────────────────────────────────────────────
COMMIT;

-- ════════════════════════════════════════════════════════════════════
-- VÉRIFICATION POST-EXÉCUTION
-- ════════════════════════════════════════════════════════════════════
-- Relancer audit_rls.sql pour vérifier l'état final
-- Tester immédiatement :
--   - Site public charge normalement
--   - Login user fonctionne
--   - BO admin charge le dashboard
--   - BO parrain charge le dashboard
--   - AUDITAZ charge sa section dashboard
-- Si quelque chose casse :
--   - Identifier la table qui pose problème dans la console (erreur 401/403)
--   - Ajouter une policy pour cette table
--   - Re-tester
-- ════════════════════════════════════════════════════════════════════
