-- ═══════════════════════════════════════════════════════════════════════
-- FIX : Ajouter 'system' aux senders autorisés dans chat_conversations
-- ═══════════════════════════════════════════════════════════════════════
-- Problème : la contrainte CHECK (sender IN ('client','admin','bot'))
--            empêche d'enregistrer les événements automatiques (redirections
--            WhatsApp, clics sur boutons d'action) comme un type distinct.
-- Solution : élargir la contrainte pour inclure 'system'
-- À exécuter UNE FOIS dans le SQL Editor de Supabase.
-- ═══════════════════════════════════════════════════════════════════════

-- 1. Supprimer l'ancienne contrainte
ALTER TABLE public.chat_conversations
  DROP CONSTRAINT IF EXISTS chat_conversations_sender_check;

-- 2. Recréer avec 'system' inclus
ALTER TABLE public.chat_conversations
  ADD CONSTRAINT chat_conversations_sender_check
  CHECK (sender IN ('client', 'admin', 'bot', 'system'));

-- 3. Vérification (doit retourner la nouvelle contrainte)
SELECT pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conname = 'chat_conversations_sender_check';

-- ═══════════════════════════════════════════════════════════════════════
-- Note : pour les anciens messages dupliqués déjà en base (avant ce fix),
-- vous pouvez optionnellement les nettoyer avec :
--
-- UPDATE public.chat_conversations
-- SET sender = 'system'
-- WHERE sender = 'client'
--   AND message LIKE 'Bonjour 👋, je %';
--
-- ⚠️ À utiliser avec précaution : faire un SELECT avant pour vérifier
-- ═══════════════════════════════════════════════════════════════════════
