-- ════════════════════════════════════════════════════════════════════
-- Vues analytiques pour dashboard support
-- ════════════════════════════════════════════════════════════════════

-- 1. Vue : KPIs par ticket (calcule FRT, ART, resolution time)
CREATE OR REPLACE VIEW public.chat_ticket_kpis AS
WITH first_msgs AS (
  -- 1er message client par ticket
  SELECT DISTINCT ON (ticket_id)
    ticket_id,
    created_at AS first_client_msg_at
  FROM public.chat_conversations
  WHERE sender = 'client' AND ticket_id IS NOT NULL
  ORDER BY ticket_id, created_at ASC
),
first_admin_replies AS (
  -- 1ère réponse admin par ticket (seulement après le 1er message client)
  SELECT DISTINCT ON (c.ticket_id)
    c.ticket_id,
    c.created_at AS first_admin_reply_at
  FROM public.chat_conversations c
  JOIN first_msgs fm ON fm.ticket_id = c.ticket_id
  WHERE c.sender = 'admin' AND c.created_at > fm.first_client_msg_at
  ORDER BY c.ticket_id, c.created_at ASC
),
all_admin_replies AS (
  -- Tous les couples (msg client → réponse admin suivante) pour calculer le temps de réponse moyen
  SELECT
    c1.ticket_id,
    c1.created_at AS client_msg_at,
    (SELECT MIN(c2.created_at) 
     FROM public.chat_conversations c2 
     WHERE c2.ticket_id = c1.ticket_id 
       AND c2.sender = 'admin' 
       AND c2.created_at > c1.created_at) AS admin_reply_at
  FROM public.chat_conversations c1
  WHERE c1.sender = 'client' AND c1.ticket_id IS NOT NULL
),
avg_response AS (
  SELECT
    ticket_id,
    AVG(EXTRACT(EPOCH FROM (admin_reply_at - client_msg_at))) AS avg_response_seconds
  FROM all_admin_replies
  WHERE admin_reply_at IS NOT NULL
  GROUP BY ticket_id
)
SELECT
  t.id AS ticket_id,
  t.client_id,
  t.client_name,
  t.client_phone,
  t.status,
  t.subject,
  t.created_at,
  t.last_client_message_at,
  t.last_admin_message_at,
  t.closed_at,
  fm.first_client_msg_at,
  far.first_admin_reply_at,
  -- First Response Time en secondes
  CASE 
    WHEN far.first_admin_reply_at IS NOT NULL THEN
      EXTRACT(EPOCH FROM (far.first_admin_reply_at - fm.first_client_msg_at))
    ELSE NULL
  END AS first_response_seconds,
  -- Temps de réponse moyen
  ar.avg_response_seconds,
  -- Resolution time : entre création et fermeture
  CASE
    WHEN t.closed_at IS NOT NULL THEN
      EXTRACT(EPOCH FROM (t.closed_at - t.created_at))
    ELSE NULL
  END AS resolution_seconds,
  -- Nombre total de messages
  (SELECT COUNT(*) FROM public.chat_conversations WHERE ticket_id = t.id) AS total_messages,
  (SELECT COUNT(*) FROM public.chat_conversations WHERE ticket_id = t.id AND sender = 'client') AS client_messages,
  (SELECT COUNT(*) FROM public.chat_conversations WHERE ticket_id = t.id AND sender = 'admin') AS admin_messages
FROM public.chat_tickets t
LEFT JOIN first_msgs fm ON fm.ticket_id = t.id
LEFT JOIN first_admin_replies far ON far.ticket_id = t.id
LEFT JOIN avg_response ar ON ar.ticket_id = t.id;

-- 2. Vue : KPIs globaux (résumé général)
CREATE OR REPLACE VIEW public.chat_kpis_global AS
SELECT
  COUNT(*) AS total_tickets,
  COUNT(*) FILTER (WHERE status IN ('open', 'in_progress')) AS active_tickets,
  COUNT(*) FILTER (WHERE status = 'open') AS open_tickets,
  COUNT(*) FILTER (WHERE status = 'in_progress') AS in_progress_tickets,
  COUNT(*) FILTER (WHERE status = 'resolved') AS resolved_tickets,
  COUNT(*) FILTER (WHERE status = 'order_made') AS order_tickets,
  COUNT(*) FILTER (WHERE status = 'info_given') AS info_tickets,
  COUNT(*) FILTER (WHERE status = 'auto_closed') AS auto_closed_tickets,
  -- KPIs temps (en secondes)
  AVG(first_response_seconds) FILTER (WHERE first_response_seconds IS NOT NULL) AS avg_first_response_seconds,
  -- Médiane FRT
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY first_response_seconds) FILTER (WHERE first_response_seconds IS NOT NULL) AS median_first_response_seconds,
  AVG(avg_response_seconds) FILTER (WHERE avg_response_seconds IS NOT NULL) AS avg_response_seconds,
  AVG(resolution_seconds) FILTER (WHERE resolution_seconds IS NOT NULL) AS avg_resolution_seconds,
  -- Taux d'auto-fermeture (signe d'abandon)
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE status = 'auto_closed') 
    / NULLIF(COUNT(*) FILTER (WHERE status IN ('resolved', 'order_made', 'info_given', 'auto_closed')), 0),
    1
  ) AS auto_close_rate_percent,
  -- Volume période
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '24 hours') AS tickets_last_24h,
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '7 days') AS tickets_last_7d,
  COUNT(*) FILTER (WHERE created_at > NOW() - INTERVAL '30 days') AS tickets_last_30d
FROM public.chat_ticket_kpis;

-- 3. Vue : Volume par jour (pour graphique)
CREATE OR REPLACE VIEW public.chat_kpis_daily AS
SELECT
  DATE(created_at) AS day,
  COUNT(*) AS tickets_created,
  COUNT(*) FILTER (WHERE first_response_seconds IS NOT NULL) AS tickets_responded,
  AVG(first_response_seconds) FILTER (WHERE first_response_seconds IS NOT NULL) AS avg_first_response_seconds,
  COUNT(*) FILTER (WHERE status IN ('resolved', 'order_made', 'info_given')) AS tickets_resolved,
  COUNT(*) FILTER (WHERE status = 'auto_closed') AS tickets_auto_closed
FROM public.chat_ticket_kpis
WHERE created_at > NOW() - INTERVAL '60 days'
GROUP BY DATE(created_at)
ORDER BY DATE(created_at) DESC;

GRANT SELECT ON public.chat_ticket_kpis TO anon, authenticated;
GRANT SELECT ON public.chat_kpis_global TO anon, authenticated;
GRANT SELECT ON public.chat_kpis_daily TO anon, authenticated;
