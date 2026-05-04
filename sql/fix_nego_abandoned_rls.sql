-- ═══════════════════════════════════════════════════════════════════════
-- FIX RLS : nego_abandoned — autoriser DELETE depuis le BO admin
-- ═══════════════════════════════════════════════════════════════════════
-- Problème : la session admin du BO n'est PAS authentifiée auprès de Supabase
--            (elle est gérée localement via localStorage). Donc les policies
--            "TO authenticated" ne se déclenchent jamais → DELETE rejeté
--            silencieusement, RLS retournant 0 rows affected.
--
-- Solution : aligner sur le pattern du reste du projet (chat_conversations) :
--            policies SANS clause "TO ..." = appliquées à tout le monde.
--            La sécurité est alors gérée côté JS dans le BO (vérification
--            Super Admin avec naIsSuperAdmin() + double confirmation
--            "tapez SUPPRIMER").
--
-- À exécuter UNE FOIS dans le SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════════

-- 1. Supprimer les anciennes policies (qui ciblaient TO authenticated/anon)
DROP POLICY IF EXISTS "anon insert nego_abandoned"     ON public.nego_abandoned;
DROP POLICY IF EXISTS "admin select nego_abandoned"    ON public.nego_abandoned;
DROP POLICY IF EXISTS "admin update nego_abandoned"    ON public.nego_abandoned;
DROP POLICY IF EXISTS "admin delete nego_abandoned"    ON public.nego_abandoned;

-- 2. Recréer sans TO = applicable à tous (anon + authenticated)
CREATE POLICY nego_abandoned_insert_all ON public.nego_abandoned
  FOR INSERT WITH CHECK (TRUE);

CREATE POLICY nego_abandoned_select_all ON public.nego_abandoned
  FOR SELECT USING (TRUE);

CREATE POLICY nego_abandoned_update_all ON public.nego_abandoned
  FOR UPDATE USING (TRUE);

CREATE POLICY nego_abandoned_delete_all ON public.nego_abandoned
  FOR DELETE USING (TRUE);

-- 3. GRANT explicites (au cas où) — anon a déjà SELECT/INSERT, on ajoute UPDATE/DELETE
GRANT SELECT, INSERT, UPDATE, DELETE ON public.nego_abandoned TO anon, authenticated;

-- 4. Vérification : lister les policies actives
SELECT schemaname, tablename, policyname, cmd, qual
FROM pg_policies
WHERE tablename = 'nego_abandoned'
ORDER BY cmd;

-- ═══════════════════════════════════════════════════════════════════════
-- ⚠️ SÉCURITÉ : la sécurité du DELETE est gérée côté JS (BO admin) :
--    - Bouton visible uniquement si naIsSuperAdmin() = true
--    - Double confirmation : taper exactement "SUPPRIMER"
--    - Modal séparé avec choix de cible (résolues / par date / tout)
-- ═══════════════════════════════════════════════════════════════════════
