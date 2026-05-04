-- ═══════════════════════════════════════════════════════════════════
-- AJOUT DES COLONNES POUR PRIORISATION DES CONVERSATIONS
-- + RLS pour permettre aux clients d'écrire et au BO admin de lire
-- À exécuter dans Supabase SQL Editor → Run
-- ═══════════════════════════════════════════════════════════════════

-- ─── 1. Vérifier que la table existe (créer si nécessaire) ──────────
CREATE TABLE IF NOT EXISTS public.conversations (
  id TEXT PRIMARY KEY,
  user_id TEXT,
  admin_id TEXT,
  sujet TEXT,
  statut TEXT DEFAULT 'En attente',
  clientNom TEXT,
  clientTel TEXT,
  commandeId TEXT,
  produit TEXT,
  type TEXT,
  dateCreation TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  messages JSONB DEFAULT '[]'::jsonb,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ─── 2. Ajouter les nouvelles colonnes (idempotent) ─────────────────
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS priorite TEXT DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS score INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS reason TEXT,
  ADD COLUMN IF NOT EXISTS resolu BOOLEAN DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS resolu_le TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS resolu_par TEXT,
  ADD COLUMN IF NOT EXISTS "motDeclencheur" TEXT,
  ADD COLUMN IF NOT EXISTS "botFailedCount" INTEGER DEFAULT 0,
  -- 🆕 Flag pour conversations escaladées manuellement (commande → support)
  ADD COLUMN IF NOT EXISTS escalated BOOLEAN DEFAULT FALSE;

-- ─── 2bis. Vérifier les colonnes camelCase qui peuvent manquer ──────
-- Si la table a été créée avec snake_case, ces colonnes peuvent ne pas exister
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS "clientNom" TEXT,
  ADD COLUMN IF NOT EXISTS "clientTel" TEXT,
  ADD COLUMN IF NOT EXISTS "commandeId" TEXT,
  ADD COLUMN IF NOT EXISTS "dateCreation" TIMESTAMP WITH TIME ZONE;

-- ─── 3. Index pour tri rapide par priorité ─────────────────────────
CREATE INDEX IF NOT EXISTS idx_conv_priorite_created
  ON public.conversations(priorite, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_conv_resolu
  ON public.conversations(resolu, priorite, created_at DESC);

-- ─── 4. RLS (Row Level Security) ────────────────────────────────────
-- Permettre à TOUT le monde (anon + authenticated) de :
-- - INSERT : pour que les clients puissent créer des escalades
-- - SELECT : pour que le BO admin puisse les lire
-- - UPDATE : pour que l'admin puisse marquer comme resolu, changer la priorité, etc.
-- - DELETE : autorisé pour le ménage (purge admin)
-- Le filtrage côté client se fait dans le code JS (par tel/userId).
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS conv_select_all ON public.conversations;
CREATE POLICY conv_select_all ON public.conversations
  FOR SELECT USING (TRUE);

DROP POLICY IF EXISTS conv_insert_all ON public.conversations;
CREATE POLICY conv_insert_all ON public.conversations
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS conv_update_all ON public.conversations;
CREATE POLICY conv_update_all ON public.conversations
  FOR UPDATE USING (TRUE);

DROP POLICY IF EXISTS conv_delete_all ON public.conversations;
CREATE POLICY conv_delete_all ON public.conversations
  FOR DELETE USING (TRUE);

-- ─── 5. Mettre à jour les anciennes conversations sans priorité ─────
UPDATE public.conversations
  SET priorite = 'normal'
  WHERE priorite IS NULL OR priorite = '';

-- ─── 6. Vérification finale (statistiques par priorité) ─────────────
SELECT
  priorite,
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE resolu = false) as non_resolu
FROM public.conversations
GROUP BY priorite
ORDER BY
  CASE priorite
    WHEN 'urgent' THEN 1
    WHEN 'normal' THEN 2
    WHEN 'info' THEN 3
    ELSE 4
  END;

-- ─── 7. Lister les colonnes existantes (pour debug) ─────────────────
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'conversations'
ORDER BY ordinal_position;
