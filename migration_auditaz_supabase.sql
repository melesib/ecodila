-- ============================================================
-- AUDITAZ — Migration Supabase
-- Exécuter dans Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- ── 1. Table utilisateurs Auditaz ──
CREATE TABLE IF NOT EXISTS auditaz_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  login TEXT UNIQUE NOT NULL,
  password_hash TEXT NOT NULL DEFAULT '',
  nom TEXT NOT NULL,
  role TEXT NOT NULL CHECK (role IN ('Super Admin','Auditeur','Analyste','Lecture seule')),
  color TEXT DEFAULT '#00ff88',
  emoji TEXT DEFAULT '👤',
  active BOOLEAN DEFAULT true,
  totp_secret TEXT,
  totp_enabled BOOLEAN DEFAULT false,
  recovery_key TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Données par défaut
INSERT INTO auditaz_users (login, password_hash, nom, role, color, emoji, active, recovery_key) VALUES
  ('admin',     '', 'Administrateur',    'Super Admin',   '#00ff88', '👑', true, 'AUDITAZ-RECOVERY-2024'),
  ('auditeur1', '', 'Auditeur Principal', 'Auditeur',      '#4488ff', '🔍', true, NULL),
  ('auditeur2', '', 'Analyste Sécurité',  'Analyste',      '#9b59ff', '🛡️', true, NULL),
  ('viewer',    '', 'Observateur',        'Lecture seule', '#ffaa00', '👁️', true, NULL)
ON CONFLICT (login) DO NOTHING;

-- ── 2. Table permissions par page ──
CREATE TABLE IF NOT EXISTS auditaz_permissions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_login TEXT NOT NULL REFERENCES auditaz_users(login) ON DELETE CASCADE,
  page_id TEXT NOT NULL,
  level TEXT NOT NULL CHECK (level IN ('none','view','comment','edit','full')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_login, page_id)
);

-- ── 3. Table résolutions (vulnérabilités/issues résolues) ──
CREATE TABLE IF NOT EXISTS auditaz_resolved (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  issue_key TEXT UNIQUE NOT NULL,
  resolved_at TIMESTAMPTZ DEFAULT now(),
  resolved_by TEXT,
  notes TEXT
);

-- ── 4. Table journal d'activité ──
CREATE TABLE IF NOT EXISTS auditaz_activity (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ts TIMESTAMPTZ DEFAULT now(),
  type TEXT NOT NULL,
  msg TEXT NOT NULL,
  user_login TEXT
);

CREATE INDEX IF NOT EXISTS idx_auditaz_activity_ts ON auditaz_activity(ts DESC);

-- Nettoyage auto : garder max 500 entrées
CREATE OR REPLACE FUNCTION auditaz_trim_activity()
RETURNS TRIGGER AS $$
BEGIN
  DELETE FROM auditaz_activity
  WHERE id NOT IN (
    SELECT id FROM auditaz_activity ORDER BY ts DESC LIMIT 500
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_auditaz_trim_activity ON auditaz_activity;
CREATE TRIGGER trg_auditaz_trim_activity
  AFTER INSERT ON auditaz_activity
  FOR EACH STATEMENT
  EXECUTE FUNCTION auditaz_trim_activity();

-- ── 5. Table configuration clé-valeur ──
CREATE TABLE IF NOT EXISTS auditaz_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ── 6. Row Level Security ──
ALTER TABLE auditaz_users ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditaz_permissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditaz_resolved ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditaz_activity ENABLE ROW LEVEL SECURITY;
ALTER TABLE auditaz_config ENABLE ROW LEVEL SECURITY;

-- Politique : accès public via clé anon (auditaz est un outil interne)
CREATE POLICY "auditaz_users_all" ON auditaz_users FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "auditaz_permissions_all" ON auditaz_permissions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "auditaz_resolved_all" ON auditaz_resolved FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "auditaz_activity_all" ON auditaz_activity FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "auditaz_config_all" ON auditaz_config FOR ALL USING (true) WITH CHECK (true);

-- ── 7. Vérification ──
SELECT 'auditaz_users' AS table_name, count(*) AS rows FROM auditaz_users
UNION ALL
SELECT 'auditaz_permissions', count(*) FROM auditaz_permissions
UNION ALL
SELECT 'auditaz_resolved', count(*) FROM auditaz_resolved
UNION ALL
SELECT 'auditaz_activity', count(*) FROM auditaz_activity
UNION ALL
SELECT 'auditaz_config', count(*) FROM auditaz_config;

-- ── 8. Table transferts/activités trackées par le BO Admin ──
CREATE TABLE IF NOT EXISTS auditaz_transfers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  type TEXT NOT NULL DEFAULT 'upload',
  file TEXT NOT NULL DEFAULT '',
  detail TEXT DEFAULT '',
  size TEXT DEFAULT '-',
  risk TEXT DEFAULT 'safe',
  user_id TEXT DEFAULT 'admin',
  user_name TEXT DEFAULT 'Admin',
  user_role TEXT DEFAULT 'Admin',
  source TEXT DEFAULT 'bo_admin',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auditaz_transfers_ts ON auditaz_transfers(created_at DESC);

ALTER TABLE auditaz_transfers ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auditaz_transfers_all" ON auditaz_transfers FOR ALL USING (true) WITH CHECK (true);

SELECT 'auditaz_transfers' AS table_name, count(*) AS rows FROM auditaz_transfers;

-- ── 9. Table utilisateurs bloqués (remplace localStorage ecodila_audit_blocked_users) ──
CREATE TABLE IF NOT EXISTS auditaz_blocked_users (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL UNIQUE,
  name TEXT DEFAULT '',
  email TEXT DEFAULT '',
  role TEXT DEFAULT 'Utilisateur',
  reason TEXT DEFAULT '',
  blocked_at TEXT DEFAULT '',
  expires TEXT DEFAULT '',
  blocked_by TEXT DEFAULT '',
  risk_score INT DEFAULT 0,
  ip TEXT DEFAULT '',
  permanent BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auditaz_blocked_users_uid ON auditaz_blocked_users(user_id);
ALTER TABLE auditaz_blocked_users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auditaz_blocked_users_all" ON auditaz_blocked_users FOR ALL USING (true) WITH CHECK (true);

-- ── 10. Table IPs bannies (remplace localStorage ecodila_audit_banned_ips) ──
CREATE TABLE IF NOT EXISTS auditaz_banned_ips (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ip TEXT NOT NULL UNIQUE,
  country TEXT DEFAULT '?',
  reason TEXT DEFAULT '',
  attempts INT DEFAULT 1,
  banned_at TEXT DEFAULT '',
  expires TEXT DEFAULT '',
  auto BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_auditaz_banned_ips_ip ON auditaz_banned_ips(ip);
ALTER TABLE auditaz_banned_ips ENABLE ROW LEVEL SECURITY;
CREATE POLICY "auditaz_banned_ips_all" ON auditaz_banned_ips FOR ALL USING (true) WITH CHECK (true);

SELECT 'auditaz_blocked_users' AS table_name, count(*) AS rows FROM auditaz_blocked_users
UNION ALL
SELECT 'auditaz_banned_ips', count(*) FROM auditaz_banned_ips;
