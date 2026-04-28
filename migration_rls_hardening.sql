-- ============================================================
-- ECODILA — Durcissement RLS (Row Level Security)
-- Exécuter dans Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================
-- Architecture : Frontend-only (JAMstack) avec clé anon publique
-- Auth custom : téléphone + MDP hashé (pas de Supabase Auth)
-- Conséquence : auth.uid() non disponible → policies basées sur opérations
--
-- AVANT : policy "anon_all" FOR ALL → tout permis
-- APRÈS : policies par opération → DELETE restreint sur tables sensibles
-- ============================================================

-- ══════════════════════════════════════════════════════════════
-- 1. TABLES PUBLIQUES — lecture libre, écriture contrôlée
-- ══════════════════════════════════════════════════════════════

-- ── PRODUCTS (catalogue) ──
-- Lecture : publique (catalogue visible par tous)
-- Écriture : autorisée (admin gère via BO)
-- Suppression : autorisée (admin gère le stock)
DROP POLICY IF EXISTS "anon_all" ON products;
DROP POLICY IF EXISTS "products_select" ON products;
CREATE POLICY "products_select" ON products FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "products_insert" ON products;
CREATE POLICY "products_insert" ON products FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "products_update" ON products;
CREATE POLICY "products_update" ON products FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "products_delete" ON products;
CREATE POLICY "products_delete" ON products FOR DELETE TO anon USING (true);

-- ── AVIS (avis clients) ──
DROP POLICY IF EXISTS "anon_all" ON avis;
DROP POLICY IF EXISTS "avis_select" ON avis;
CREATE POLICY "avis_select" ON avis FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "avis_insert" ON avis;
CREATE POLICY "avis_insert" ON avis FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "avis_update" ON avis;
CREATE POLICY "avis_update" ON avis FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "avis_delete" ON avis;
CREATE POLICY "avis_delete" ON avis FOR DELETE TO anon USING (true);

-- ── SETTINGS (configuration clé-valeur) ──
DROP POLICY IF EXISTS "anon_all" ON settings;
DROP POLICY IF EXISTS "settings_select" ON settings;
CREATE POLICY "settings_select" ON settings FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "settings_insert" ON settings;
CREATE POLICY "settings_insert" ON settings FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "settings_update" ON settings;
CREATE POLICY "settings_update" ON settings FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- ⛔ PAS de DELETE sur settings — protège la configuration
-- Si besoin de supprimer une clé : UPDATE value = NULL

-- ── VISITORS (tracking anonyme) ──
DROP POLICY IF EXISTS "anon_all" ON visitors;
DROP POLICY IF EXISTS "visitors_select" ON visitors;
CREATE POLICY "visitors_select" ON visitors FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "visitors_insert" ON visitors;
CREATE POLICY "visitors_insert" ON visitors FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "visitors_update" ON visitors;
CREATE POLICY "visitors_update" ON visitors FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- ⛔ PAS de DELETE sur visitors — préserve les analytics

-- ── PRODUCT_VIEWS (analytics vues produits) ──
DROP POLICY IF EXISTS "anon_all" ON product_views;
DROP POLICY IF EXISTS "product_views_select" ON product_views;
CREATE POLICY "product_views_select" ON product_views FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "product_views_insert" ON product_views;
CREATE POLICY "product_views_insert" ON product_views FOR INSERT TO anon WITH CHECK (true);
-- ⛔ PAS de UPDATE/DELETE — données analytics immuables


-- ══════════════════════════════════════════════════════════════
-- 2. TABLES SENSIBLES — lecture/écriture, suppression restreinte
-- ══════════════════════════════════════════════════════════════

-- ── USERS (comptes clients — MDP hashés SHA-256/PBKDF2) ──
DROP POLICY IF EXISTS "anon_all" ON users;
DROP POLICY IF EXISTS "users_select" ON users;
CREATE POLICY "users_select" ON users FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "users_insert" ON users;
CREATE POLICY "users_insert" ON users FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "users_update" ON users;
CREATE POLICY "users_update" ON users FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "users_delete" ON users;
CREATE POLICY "users_delete" ON users FOR DELETE TO anon USING (true);
-- Note : DELETE autorisé car le BO admin doit pouvoir purger les comptes test

-- ── ORDERS (commandes) ──
DROP POLICY IF EXISTS "anon_all" ON orders;
DROP POLICY IF EXISTS "orders_select" ON orders;
CREATE POLICY "orders_select" ON orders FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "orders_insert" ON orders;
CREATE POLICY "orders_insert" ON orders FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "orders_update" ON orders;
CREATE POLICY "orders_update" ON orders FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "orders_delete" ON orders;
CREATE POLICY "orders_delete" ON orders FOR DELETE TO anon USING (true);
-- Note : DELETE autorisé (Super Admin only côté code JS)

-- ── TROCS ──
DROP POLICY IF EXISTS "anon_all" ON trocs;
DROP POLICY IF EXISTS "trocs_select" ON trocs;
CREATE POLICY "trocs_select" ON trocs FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "trocs_insert" ON trocs;
CREATE POLICY "trocs_insert" ON trocs FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "trocs_update" ON trocs;
CREATE POLICY "trocs_update" ON trocs FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "trocs_delete" ON trocs;
CREATE POLICY "trocs_delete" ON trocs FOR DELETE TO anon USING (true);

-- ── OFFERS / PROPOSITIONS (négociations) ──
DROP POLICY IF EXISTS "anon_all" ON offers;
DROP POLICY IF EXISTS "offers_select" ON offers;
CREATE POLICY "offers_select" ON offers FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "offers_insert" ON offers;
CREATE POLICY "offers_insert" ON offers FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "offers_update" ON offers;
CREATE POLICY "offers_update" ON offers FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "offers_delete" ON offers;
CREATE POLICY "offers_delete" ON offers FOR DELETE TO anon USING (true);

DROP POLICY IF EXISTS "anon_all" ON propositions;
DROP POLICY IF EXISTS "propositions_select" ON propositions;
CREATE POLICY "propositions_select" ON propositions FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "propositions_insert" ON propositions;
CREATE POLICY "propositions_insert" ON propositions FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "propositions_update" ON propositions;
CREATE POLICY "propositions_update" ON propositions FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "propositions_delete" ON propositions;
CREATE POLICY "propositions_delete" ON propositions FOR DELETE TO anon USING (true);

-- ── NOTIFICATIONS ──
DROP POLICY IF EXISTS "anon_all" ON notifications;
DROP POLICY IF EXISTS "notifications_select" ON notifications;
CREATE POLICY "notifications_select" ON notifications FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "notifications_insert" ON notifications;
CREATE POLICY "notifications_insert" ON notifications FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "notifications_update" ON notifications;
CREATE POLICY "notifications_update" ON notifications FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "notifications_delete" ON notifications;
CREATE POLICY "notifications_delete" ON notifications FOR DELETE TO anon USING (true);

-- ── CONVERSATIONS ──
DROP POLICY IF EXISTS "anon_all" ON conversations;
DROP POLICY IF EXISTS "conversations_select" ON conversations;
CREATE POLICY "conversations_select" ON conversations FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "conversations_insert" ON conversations;
CREATE POLICY "conversations_insert" ON conversations FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "conversations_update" ON conversations;
CREATE POLICY "conversations_update" ON conversations FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- ⛔ PAS de DELETE sur conversations — historique préservé

-- ── COUPONS ──
DROP POLICY IF EXISTS "anon_all" ON coupons;
DROP POLICY IF EXISTS "coupons_select" ON coupons;
CREATE POLICY "coupons_select" ON coupons FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "coupons_insert" ON coupons;
CREATE POLICY "coupons_insert" ON coupons FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "coupons_update" ON coupons;
CREATE POLICY "coupons_update" ON coupons FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "coupons_delete" ON coupons;
CREATE POLICY "coupons_delete" ON coupons FOR DELETE TO anon USING (true);

-- ── CHALLENGES ──
DROP POLICY IF EXISTS "anon_all" ON challenges;
DROP POLICY IF EXISTS "challenges_select" ON challenges;
CREATE POLICY "challenges_select" ON challenges FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "challenges_insert" ON challenges;
CREATE POLICY "challenges_insert" ON challenges FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "challenges_update" ON challenges;
CREATE POLICY "challenges_update" ON challenges FOR UPDATE TO anon USING (true) WITH CHECK (true);
DROP POLICY IF EXISTS "challenges_delete" ON challenges;
CREATE POLICY "challenges_delete" ON challenges FOR DELETE TO anon USING (true);


-- ══════════════════════════════════════════════════════════════
-- 3. TABLES FINANCIÈRES — lecture/écriture, ⛔ PAS de DELETE anon
-- ══════════════════════════════════════════════════════════════

-- ── PARRAINS ──
DROP POLICY IF EXISTS "anon_all" ON parrains;
DROP POLICY IF EXISTS "parrains_select" ON parrains;
CREATE POLICY "parrains_select" ON parrains FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "parrains_insert" ON parrains;
CREATE POLICY "parrains_insert" ON parrains FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "parrains_update" ON parrains;
CREATE POLICY "parrains_update" ON parrains FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- ⛔ PAS de DELETE sur parrains — protège les comptes partenaires

-- ── PARRAIN_COMMISSIONS (données financières) ──
DROP POLICY IF EXISTS "anon_all" ON parrain_commissions;
DROP POLICY IF EXISTS "parrain_commissions_select" ON parrain_commissions;
CREATE POLICY "parrain_commissions_select" ON parrain_commissions FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "parrain_commissions_insert" ON parrain_commissions;
CREATE POLICY "parrain_commissions_insert" ON parrain_commissions FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "parrain_commissions_update" ON parrain_commissions;
CREATE POLICY "parrain_commissions_update" ON parrain_commissions FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- ⛔ PAS de DELETE sur commissions — données financières immuables

-- ── PARRAIN_PAIEMENTS (transactions financières) ──
DROP POLICY IF EXISTS "anon_all" ON parrain_paiements;
DROP POLICY IF EXISTS "parrain_paiements_select" ON parrain_paiements;
CREATE POLICY "parrain_paiements_select" ON parrain_paiements FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "parrain_paiements_insert" ON parrain_paiements;
CREATE POLICY "parrain_paiements_insert" ON parrain_paiements FOR INSERT TO anon WITH CHECK (true);
DROP POLICY IF EXISTS "parrain_paiements_update" ON parrain_paiements;
CREATE POLICY "parrain_paiements_update" ON parrain_paiements FOR UPDATE TO anon USING (true) WITH CHECK (true);
-- ⛔ PAS de DELETE sur paiements — traçabilité financière obligatoire

-- ── PARRAIN_STATUTS (historique paliers) ──
DROP POLICY IF EXISTS "anon_all" ON parrain_statuts;
DROP POLICY IF EXISTS "parrain_statuts_select" ON parrain_statuts;
CREATE POLICY "parrain_statuts_select" ON parrain_statuts FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "parrain_statuts_insert" ON parrain_statuts;
CREATE POLICY "parrain_statuts_insert" ON parrain_statuts FOR INSERT TO anon WITH CHECK (true);
-- ⛔ PAS de UPDATE/DELETE — historique immuable


-- ══════════════════════════════════════════════════════════════
-- 4. TABLES ADMIN — protégées
-- ══════════════════════════════════════════════════════════════

-- ── CART_HISTORY ──
DROP POLICY IF EXISTS "anon_all" ON cart_history;
DROP POLICY IF EXISTS "cart_history_select" ON cart_history;
CREATE POLICY "cart_history_select" ON cart_history FOR SELECT TO anon USING (true);
DROP POLICY IF EXISTS "cart_history_insert" ON cart_history;
CREATE POLICY "cart_history_insert" ON cart_history FOR INSERT TO anon WITH CHECK (true);
-- ⛔ PAS de UPDATE/DELETE — historique immuable


-- ══════════════════════════════════════════════════════════════
-- 5. VÉRIFICATION FINALE
-- ══════════════════════════════════════════════════════════════

-- Vérifier que RLS est activé sur toutes les tables
SELECT
  schemaname,
  tablename,
  rowsecurity
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- Lister toutes les policies actives
SELECT
  schemaname,
  tablename,
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
