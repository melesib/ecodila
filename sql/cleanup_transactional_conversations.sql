-- ═══════════════════════════════════════════════════════════════════
-- NETTOYAGE : retirer les conversations transactionnelles polluant la BDD
--
-- Ces conversations (type='commande'|'offre'|'troc') ont été créées par
-- erreur AVANT le déploiement du filtre. Elles n'ont rien à faire en BDD
-- (BO admin Support n'a pas besoin de les voir — il a déjà des pages
-- dédiées commandes/offres/trocs).
--
-- Les escaladées (priorite='urgent' OU escalated=true) sont préservées.
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Voir d'abord ce qui va être supprimé (DRY RUN) ──────────────
SELECT
  type,
  priorite,
  escalated,
  COUNT(*) as count
FROM public.conversations
WHERE type IN ('commande', 'offre', 'troc')
  AND COALESCE(escalated, FALSE) = FALSE
  AND COALESCE(priorite, 'normal') != 'urgent'
GROUP BY type, priorite, escalated;

-- ─── 2. Supprimer les conversations transactionnelles non-escaladées ─
DELETE FROM public.conversations
WHERE type IN ('commande', 'offre', 'troc')
  AND COALESCE(escalated, FALSE) = FALSE
  AND COALESCE(priorite, 'normal') != 'urgent';

-- ─── 3. Vérifier le résultat ────────────────────────────────────────
SELECT
  COALESCE(type, '(null)') as type,
  COALESCE(priorite, '(null)') as priorite,
  COUNT(*) as total
FROM public.conversations
GROUP BY type, priorite
ORDER BY type, priorite;

-- ─── 4. Au cas où created_at est NULL pour les conv qui restent : fix ─
UPDATE public.conversations
  SET created_at = NOW()
  WHERE created_at IS NULL;
