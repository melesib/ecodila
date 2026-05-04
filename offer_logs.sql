-- ═══════════════════════════════════════════════════════════════════════
-- TABLE offer_logs : analytics fines de la négociation EcoDila
-- ═══════════════════════════════════════════════════════════════════════
-- Capture chaque interaction du client durant la négociation pour analyser :
--   - où les clients abandonnent
--   - taux de conversion par zone (vert/jaune/orange/rouge)
--   - efficacité de la roue chance
--   - bonus les plus utilisés
--   - pourcentage de scénario "envoyer aux conseillers"
--   - prix moyen accepté par catégorie de produit
--
-- Optimisation 2G/lent : les logs sont batchés côté client toutes les 8s
-- et persistés en localStorage en cas d'échec réseau pour retry.
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS offer_logs (
  id          TEXT PRIMARY KEY,
  session_id  TEXT NOT NULL,
  event_type  TEXT NOT NULL,
  payload     JSONB,
  product_id  TEXT,
  etat        TEXT,
  user_id     TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- Index pour requêtes analytics fréquentes
CREATE INDEX IF NOT EXISTS idx_offer_logs_session    ON offer_logs (session_id);
CREATE INDEX IF NOT EXISTS idx_offer_logs_event_type ON offer_logs (event_type);
CREATE INDEX IF NOT EXISTS idx_offer_logs_product_id ON offer_logs (product_id);
CREATE INDEX IF NOT EXISTS idx_offer_logs_created_at ON offer_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_offer_logs_user_id    ON offer_logs (user_id) WHERE user_id IS NOT NULL;

COMMENT ON TABLE  offer_logs              IS 'Logs détaillés des sessions de négociation client (analytics LIDA/roue/bonus)';
COMMENT ON COLUMN offer_logs.session_id   IS 'ID unique généré côté client : NEGO-{ts}-{rand}';
COMMENT ON COLUMN offer_logs.event_type   IS 'Type : modal_opened, etat_selected, zone_change, preset_applied, bonus_toggled, lida_msg, wheel_proposed, wheel_spun, decision_accepted, final_scenario_shown, accept_final_max, advisor_form_opened, sent_to_advisors';
COMMENT ON COLUMN offer_logs.payload      IS 'Détails de l''event (zone, prix, bonus, etc.) en JSON';

-- ═══════════════════════════════════════════════════════════════════════
-- Vérifications utiles
-- ═══════════════════════════════════════════════════════════════════════
-- SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_name = 'offer_logs' ORDER BY ordinal_position;
--
-- -- Top des events
-- SELECT event_type, COUNT(*) FROM offer_logs GROUP BY event_type ORDER BY 2 DESC;
--
-- -- Sessions complètes (du modal_opened à la décision)
-- SELECT session_id, MIN(created_at) AS start, MAX(created_at) AS end,
--        COUNT(*) AS events, ARRAY_AGG(event_type ORDER BY created_at) AS journey
-- FROM offer_logs
-- GROUP BY session_id
-- ORDER BY start DESC LIMIT 50;
-- ═══════════════════════════════════════════════════════════════════════
