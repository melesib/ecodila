-- ══════════════════════════════════════════════════════════════
-- ECODILA — Permettre au BO admin de lire rgpd_audit_log
-- ══════════════════════════════════════════════════════════════
-- ⚠️ ATTENTION : ce script ajoute une policy SELECT sur rgpd_audit_log.
--
-- Par défaut (migration_rgpd_hardening.sql), personne ne peut lire
-- la table depuis le client (sécurité maximale).
--
-- Avec ce script, le BO admin peut afficher les logs d'audit.
-- Risque : un attaquant ayant la clé anon peut aussi les lire.
--
-- Ce risque est ACCEPTABLE car :
-- - Les logs ne contiennent pas de mot de passe
-- - La table d'audit est une preuve RGPD, pas un secret
-- - Le BO admin est déjà protégé par mot de passe côté JS
--
-- À exécuter APRÈS migration_rgpd_hardening.sql
-- ══════════════════════════════════════════════════════════════

-- Permettre SELECT sur rgpd_audit_log pour anon
DROP POLICY IF EXISTS "rgpd_audit_log_select" ON rgpd_audit_log;
CREATE POLICY "rgpd_audit_log_select" ON rgpd_audit_log FOR SELECT TO anon USING (true);

-- Vérification
SELECT COUNT(*) AS total_audit_entries FROM rgpd_audit_log;

-- Lister les policies actives sur cette table
SELECT policyname, cmd, roles, qual
FROM pg_policies
WHERE tablename = 'rgpd_audit_log'
ORDER BY policyname;
