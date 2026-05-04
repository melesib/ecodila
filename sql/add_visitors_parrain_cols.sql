-- ============================================================
-- Migration : ajout des colonnes parrain tracking dans visitors
-- ============================================================
--
-- BUG : Quand un client clique sur un lien parrain (?ref=NDAW), le tracking
--    front insere des donnees comme entry.refCode et entry.parrainCode dans la
--    table visitors. Si ces colonnes n existent pas, Postgres rejette l insert
--    silencieusement et le parrain ne voit AUCUN clic sur son lien.
--
-- FIX : Ajouter toutes les colonnes manquantes dans visitors avec IF NOT EXISTS
--    (idempotent : safe a executer plusieurs fois).
-- ============================================================

-- 1. Colonnes critiques pour le tracking parrain
ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "refCode" TEXT;

ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "parrainCode" TEXT;

ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "parrainNom" TEXT;

ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "parrainId" TEXT;

-- 2. Colonnes pour deduplication / anti-fraude
ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "visitorIp" TEXT;

ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "fingerprint" TEXT;

ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "sessionId" TEXT;

-- 3. Colonnes geographiques
ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "geoSource" TEXT;

ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "platform" TEXT;

-- 4. Page d arrivee
ALTER TABLE public.visitors
  ADD COLUMN IF NOT EXISTS "page" TEXT;

-- 5. Index pour requeter rapidement par parrain
CREATE INDEX IF NOT EXISTS idx_visitors_refcode ON public.visitors("refCode")
  WHERE "refCode" IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_visitors_parraincode ON public.visitors("parrainCode")
  WHERE "parrainCode" IS NOT NULL;

-- 6. RLS : autoriser lecture/insert public (le filtrage se fait cote app)
ALTER TABLE public.visitors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS visitors_insert_all ON public.visitors;
CREATE POLICY visitors_insert_all ON public.visitors
  FOR INSERT WITH CHECK (TRUE);

DROP POLICY IF EXISTS visitors_select_all ON public.visitors;
CREATE POLICY visitors_select_all ON public.visitors
  FOR SELECT USING (TRUE);

-- 7. Verification
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'visitors'
    AND column_name IN ('refCode', 'parrainCode', 'parrainNom', 'parrainId',
                        'visitorIp', 'fingerprint', 'sessionId', 'geoSource',
                        'platform', 'page');

  IF v_count >= 10 THEN
    RAISE NOTICE 'OK Migration appliquee : % colonnes parrain tracking presentes', v_count;
  ELSE
    RAISE WARNING 'PROBLEME : seulement % colonnes (attendu 10)', v_count;
  END IF;
END $$;

-- Pour tester :
-- SELECT "refCode", "parrainCode", "parrainNom", date, source FROM visitors
-- WHERE "refCode" IS NOT NULL ORDER BY created_at DESC LIMIT 10;
