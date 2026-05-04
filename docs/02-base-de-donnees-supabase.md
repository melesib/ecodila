# 02 — Base de Données Supabase

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Configuration Supabase

| Élément | Valeur |
|---|---|
| **Project ID** | `ftvowlmrsgcaienvhojj` |
| **URL** | `https://ftvowlmrsgcaienvhojj.supabase.co` |
| **Anon key** | publique, exposée dans les 4 HTML (safe avec RLS) |
| **Service role key** | **JAMAIS exposée** côté client (n'apparaît dans aucun fichier publié) |
| **Région** | configurée à la création (probablement EU pour latence acceptable depuis CI) |

### 1.1 Comment accéder au dashboard Supabase

1. Aller sur https://supabase.com/dashboard
2. Sélectionner le projet **ftvowlmrsgcaienvhojj** (ou le nom donné au projet)
3. Onglets utiles :
   - **Table Editor** : voir et éditer les tables
   - **SQL Editor** : exécuter du SQL (les migrations dans `/sql/` doivent être lancées ici)
   - **Authentication** → Users : voir les comptes auth Supabase (pas utilisé pour l'auth métier qui est custom)
   - **Storage** : si des images sont stockées (pour l'instant elles sont base64 dans `products`)
   - **Database → Roles** : `anon`, `authenticated`, `service_role`
   - **Database → Policies (RLS)** : configurer les politiques d'accès

## 2. Vue d'ensemble du schéma

### 2.1 Inventaire complet des tables (~40)

```
Domaine UTILISATEURS (4 tables)
  ├─ users                    → clients du site
  ├─ parrains                 → membres du programme parrainage Djassa
  ├─ admins                   → équipe back-office (login admin.html)
  └─ auditaz_users            → équipe auditaz (login auditaz.html)

Domaine CATALOGUE (2 tables)
  ├─ products                 → produits en vente (smartphones, TV, PC...)
  └─ settings                 → config globale (marges, frais livraison, etc.)

Domaine COMMERCE (5 tables)
  ├─ orders                   → commandes validées
  ├─ propositions             → propositions de troc/vente d'un client
  ├─ trocs                    → trocs validés (ou ?)
  ├─ coupons                  → codes promo
  └─ cart_history             → historique paniers (recouvrement abandon)

Domaine NÉGOCIATION (3 tables)
  ├─ offers                   → offres de négociation finalisées
  ├─ offer_logs               → log granulaire de chaque interaction
  └─ nego_abandoned           → cas d'abandon en cours de négociation

Domaine PARRAINAGE (5 tables)
  ├─ parrain_commissions      → commissions générées (5-10%)
  ├─ parrain_paiements        → paiements effectués aux parrains
  ├─ parrain_concours         → participations aux concours
  ├─ parrain_statuts          → statuts/grades parrains (Bronze, Silver, Gold...)
  └─ concours_paiements       → paiements de concours

Domaine CHAT (5 tables + vues)
  ├─ chat_conversations       → tous les messages (client/admin/bot)
  ├─ chat_tickets             → tickets de support (un ticket = un fil)
  ├─ chat_ticket_kpis (vue)   → KPIs par ticket (FRT, ART, résolution)
  ├─ chat_kpis_global (vue)   → résumé global pour dashboard
  ├─ chat_kpis_daily (vue)    → volume par jour
  ├─ chat_conversations_summary (vue) → conversations groupées par client
  └─ conversations            → table héritée (ancien système ?)

Domaine REVIEWS & SOCIAL (1 table)
  └─ avis                     → avis clients sur produits/expérience

Domaine ANALYTICS (3 tables)
  ├─ visitors                 → tracking visiteurs anonymes
  ├─ product_views            → consultations produits
  └─ notifications            → notifications push internes

Domaine GAMIFICATION (2 tables)
  ├─ challenges               → défis pour parrains/clients
  └─ v_concours_publics (vue) → vue publique des concours actifs

Domaine SÉCURITÉ & AUDIT (6 tables)
  ├─ auditaz_activity         → log d'activité dans auditaz
  ├─ auditaz_transfers        → transferts de données monitorés
  ├─ auditaz_resolved         → incidents résolus
  ├─ auditaz_banned_ips       → IPs bannies
  ├─ auditaz_blocked_users    → users bloqués
  ├─ auditaz_config           → config auditaz
  ├─ auditaz_permissions      → permissions par user auditaz
  ├─ error_logs               → logs d'erreurs runtime
  └─ rgpd_audit_log           → audit des actions RGPD (droit d'accès, oubli)
```

## 3. Tables détaillées

### 3.1 Domaine UTILISATEURS

#### `users` (clients)

Table principale des clients du site public.

```sql
-- Schéma reconstruit (basé sur l'usage observé dans le code)
CREATE TABLE public.users (
  id BIGSERIAL PRIMARY KEY,
  telephone TEXT UNIQUE NOT NULL,    -- normalisé +225XXXXXXXX
  password_hash TEXT,                 -- SHA-256 via EcoSec.hashPassword
  prenom TEXT,
  nom TEXT,
  email TEXT,
  date_naissance DATE,
  ville TEXT,
  quartier TEXT,
  rgpd_prefs JSONB DEFAULT '{}',      -- consentements RGPD (cf. migration_rgpd_clients_prefs.sql)
  rgpd_consent_at TIMESTAMPTZ,
  remember_token TEXT,                -- token "remember me"
  notif_prefs JSONB DEFAULT '{}',     -- préférences canaux (whatsapp, email, sms)
  parrain_code TEXT,                  -- code du parrain qui a parrainé ce user
  total_orders INT DEFAULT 0,
  total_revenu NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_login_at TIMESTAMPTZ,
  -- ... autres champs métier
);

CREATE INDEX idx_users_telephone ON users(telephone);
CREATE INDEX idx_users_parrain_code ON users(parrain_code);
```

**Auth** : login custom (téléphone + password SHA-256). Pas d'utilisation de Supabase Auth pour cette table.

#### `parrains`

Membres du programme de parrainage "Djassa".

Champs probables (à confirmer via SQL Editor) :
- `id`, `code` (code parrain unique partageable), `telephone`, `password_hash`
- `prenom`, `nom`, `email`, `avatar`, `niveau` (Bronze/Silver/Gold/Platinum)
- `commissions_total`, `commissions_payees`, `commissions_en_attente`
- `total_filleuls`, `score_classement`
- `rgpd_prefs JSONB`

#### `admins`

Compte de l'équipe back-office. Login séparé sur `admin.html`.

**Note importante** : avec la v82, l'accès à `/admin.html` est **doublement protégé** :
1. **Couche 1** : HTTP Basic Auth via Edge Function (env vars `ADMIN_AUTH_USER/PASS`)
2. **Couche 2** : Login custom contre la table `admins`

#### `auditaz_users`

Équipe sécurité/audit. Login séparé sur `auditaz.html`. Même schéma 2-couches.

---

### 3.2 Domaine CATALOGUE

#### `products`

Produits en vente. Image stockée en **base64 dans la DB** (pas de Supabase Storage actuellement).

Champs probables :
- `id` (TEXT, format `PROD1234567890`)
- `nom`, `description`, `marque`, `modele`
- `categorie` (smartphone, tv, pc, drone, ...)
- `etat` (neuf, comme_neuf, bon, acceptable)
- `prix`, `prix_initial`, `prix_min` (pour négociation)
- `image_principale TEXT` (data:image/jpeg;base64,...)
- `images_additionnelles JSONB`
- `stock INT`, `actif BOOLEAN`
- `imei TEXT` (pour smartphones)
- `specs JSONB` (RAM, stockage, batterie, etc.)
- `created_at`, `updated_at`
- `nego_zone` (vert/jaune/orange/rouge selon état)
- `labels TEXT[]` (ex: `['imei_v', 'allum', 'ecran']` — vérifications passées)

#### `settings`

Config globale du site (clé/valeur). Probablement structure :

```sql
-- Schéma probable
CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value JSONB,
  updated_at TIMESTAMPTZ
);
```

Clés observées dans le code :
- `marges_profit_cfg` (config marges + tranches négociation)
- `frais_livraison_*` (frais de livraison par zone)
- `concours_actifs` (concours parrains en cours)
- `messages_clients` (messages éditables BO → site)
- `lida_phrases` (phrases du bot LIDA configurables)

---

### 3.3 Domaine CHAT (système support)

C'est le domaine le mieux documenté avec 4 fichiers SQL dédiés.

#### `chat_conversations` (cf. `chat_conversations.sql`)

Stocke chaque message individuel.

```sql
CREATE TABLE public.chat_conversations (
  id BIGSERIAL PRIMARY KEY,
  client_id TEXT NOT NULL,                -- téléphone normalisé OU user_id
  client_name TEXT,
  client_phone TEXT,
  client_email TEXT,
  is_logged_in BOOLEAN DEFAULT FALSE,
  sender TEXT NOT NULL CHECK (sender IN ('client', 'admin', 'bot')),
  message TEXT NOT NULL,
  message_type TEXT DEFAULT 'text',       -- 'text', 'whatsapp_redirect', 'admin_reply', 'voice'
  read_by_client BOOLEAN DEFAULT FALSE,
  read_by_admin BOOLEAN DEFAULT FALSE,
  ticket_id BIGINT,                       -- (ajouté plus tard, cf. chat_tickets.sql)
  auto_close_warning_shown BOOLEAN DEFAULT FALSE,
  priorite TEXT,                          -- (ajouté ensuite, cf. add_chat_priorite.sql)
  created_at TIMESTAMPTZ DEFAULT NOW(),
  meta JSONB DEFAULT '{}'::jsonb
);

-- Index
CREATE INDEX idx_chat_client_id ON chat_conversations(client_id);
CREATE INDEX idx_chat_created_at ON chat_conversations(created_at DESC);
CREATE INDEX idx_chat_unread_client ON chat_conversations(client_id, read_by_client) 
  WHERE read_by_client = FALSE;
```

**RLS Policy** : permissive (insert/select/update à tous). La sécurité est faite côté app (filtrage par `client_id`).

⚠️ **Risque RLS** : un client malveillant pourrait techniquement lire tous les messages de tous les clients via l'anon key + une requête SQL Supabase. À mitiger via une policy plus stricte (`client_id = current_user_id`).

#### `chat_tickets` (cf. `chat_tickets.sql`)

Un ticket = un fil de conversation autonome. Permet le tracking de KPIs support.

```sql
CREATE TABLE public.chat_tickets (
  id BIGSERIAL PRIMARY KEY,
  client_id TEXT NOT NULL,
  client_name TEXT,
  client_phone TEXT,
  client_email TEXT,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN (
    'open',         -- nouveau, attend réponse admin
    'in_progress',  -- admin a répondu, attend retour client
    'resolved',     -- résolu manuellement (générique)
    'order_made',   -- résolu en commande
    'info_given',   -- résolu en simple info
    'auto_closed'   -- auto-fermé après 48h
  )),
  subject TEXT,                            -- auto-déduit du 1er message
  created_at TIMESTAMPTZ DEFAULT NOW(),
  last_client_message_at TIMESTAMPTZ DEFAULT NOW(),
  last_admin_message_at TIMESTAMPTZ,
  closed_at TIMESTAMPTZ,
  admin_note TEXT,                         -- note interne, invisible client
  priorite TEXT,                           -- (ajouté ensuite)
  meta JSONB DEFAULT '{}'
);
```

#### Vues KPI chat (cf. `chat_kpis.sql`)

3 vues SQL pour le dashboard analytics du chat :

| Vue | Description | Métriques |
|---|---|---|
| `chat_ticket_kpis` | KPIs par ticket | FRT (First Response Time), ART (Avg Response Time), Resolution Time, total messages |
| `chat_kpis_global` | Résumé global | total tickets, taux d'auto-fermeture, médiane FRT, volume 24h/7j/30j |
| `chat_kpis_daily` | Volume par jour | tickets créés, tickets répondus, FRT moyen — sur 60 jours |

**Définition métiers** :
- **FRT (First Response Time)** : délai entre 1er message client et 1ère réponse admin
- **ART (Avg Response Time)** : moyenne des délais de réponse sur le ticket
- **Resolution Time** : délai entre création et fermeture

#### Trigger auto-fermeture

Probablement présent dans `chat_tickets.sql` (à vérifier) : un cron/trigger qui passe les tickets en `auto_closed` après 48h sans `last_client_message_at`.

---

### 3.4 Domaine NÉGOCIATION

#### `offer_logs` (cf. `offer_logs.sql`)

Capture chaque interaction du client durant la négociation.

**Objectifs analytiques** :
- Où les clients abandonnent
- Taux de conversion par zone (vert/jaune/orange/rouge)
- Efficacité de la roue chance
- Bonus les plus utilisés
- % scénario "envoyer aux conseillers"
- Prix moyen accepté par catégorie

Champs probables :
- `id`, `session_id` (groupe les events d'une même session)
- `client_id`, `produit_id`
- `event_type` (`zone_entered`, `wheel_spin`, `bonus_used`, `accepted`, `abandoned`, `escalated`)
- `event_data JSONB`
- `prix_propose`, `prix_accepte`
- `created_at`

#### `nego_abandoned` (cf. `sql/nego_abandoned.sql`)

Cas d'abandon en cours de négociation (avec contact client pour relance).

#### `offers`

Offres finalisées suite à négociation.

---

### 3.5 Domaine ANALYTICS

#### `visitors` (cf. `sql/add_visitors_parrain_cols.sql`)

Tracking visiteurs anonymes. Récente migration : ajout de colonnes parrain (sans doute pour tracker les visiteurs venus via un lien parrain `?ref=CODE`).

#### `product_views`

Vues des fiches produits (analytics + recouvrement panier).

---

### 3.6 Migrations passées (dossier `/sql/`)

Migrations à exécuter manuellement dans Supabase SQL Editor lors du setup ou de mises à jour :

| Fichier | But |
|---|---|
| `add_chat_priorite.sql` | Ajoute colonne `priorite` à `chat_conversations` |
| `add_conversations_priorite.sql` | Ajoute `priorite` à `conversations` |
| `add_visitors_parrain_cols.sql` | Ajoute colonnes parrain à `visitors` (tracking attribution) |
| `cleanup_transactional_conversations.sql` | Nettoie les vieilles `conversations` transactionnelles |
| `fix_chat_sender_system.sql` | Fix : ajout du sender 'system' dans la contrainte CHECK |
| `fix_nego_abandoned_rls.sql` | Corrige RLS sur `nego_abandoned` |
| `nego_abandoned.sql` | Création initiale de `nego_abandoned` |
| `chat_conversations.sql` | Création initiale `chat_conversations` |
| `chat_tickets.sql` | Création de `chat_tickets` + ajout `ticket_id` à `chat_conversations` |
| `chat_kpis.sql` | Création des 3 vues KPI chat |
| `fix_admin_purge_chat_before.sql` | Fix d'une fonction stored procedure `admin_purge_chat_before` |
| `migration_rgpd_clients_prefs.sql` | Ajout `rgpd_prefs JSONB` à `users` |
| `offer_logs.sql` | Création de `offer_logs` |

**À chaque déploiement nouveau** : vérifier que toutes ces migrations ont été appliquées au moins une fois (chacune contient des `IF NOT EXISTS` donc idempotente).

## 4. Politiques RLS — État des lieux

⚠️ **Section critique pour la sécurité.**

### 4.1 Bilan RLS observé

| Table | RLS activée ? | Politique observée | Risque |
|---|---|---|---|
| `chat_conversations` | ✓ ENABLE | INSERT/SELECT/UPDATE = TRUE pour tous | **🟡 Modéré** : un client peut lire tous les messages s'il connaît le SQL |
| `nego_abandoned` | ✓ ENABLE (cf. `fix_nego_abandoned_rls.sql`) | À vérifier après le fix | À auditer |
| Autres tables | À auditer dans Supabase Dashboard | — | — |

### 4.2 Recommandations RLS prioritaires

À implémenter en priorité :

```sql
-- Exemple : restreindre la lecture de chat_conversations à son propre client_id
DROP POLICY IF EXISTS chat_select_all ON public.chat_conversations;
CREATE POLICY chat_select_own ON public.chat_conversations
  FOR SELECT USING (
    client_id = current_setting('app.current_client_id', TRUE)
    OR auth.role() = 'service_role'
  );
```

⚠️ **Attention** : avant de durcir RLS, **tester en staging** car le code actuel est conçu pour le mode permissif. Un durcissement brutal peut casser l'app.

### 4.3 Pour auditer les RLS

Aller dans Supabase Dashboard → **Database → Policies**. Pour chaque table :
- Vérifier que RLS est **enabled**
- Lire les politiques actuelles
- Vérifier qu'il n'y a pas de politique `USING (TRUE)` sur des données sensibles (messages, commandes, paiements)

**Liste des tables à RLS-auditer en priorité** :
- `chat_conversations` (PII clients)
- `chat_tickets` (PII)
- `orders` (commandes — montants, infos clients)
- `users` (PII complets)
- `parrains` (PII + commissions)
- `parrain_commissions` (montants financiers)
- `parrain_paiements` (montants financiers)
- `notifications` (peuvent contenir PII)
- `rgpd_audit_log` (sensible légalement)
- `error_logs` (peuvent contenir des données app)

## 5. Backups & sécurité

### 5.1 Backups Supabase

Supabase fait des backups automatiques en plan Pro+. **À vérifier dans le dashboard** :
- Database → Backups
- Si plan gratuit : backups limités à 7 jours, **PAS de point-in-time recovery**

**Recommandation** : 
- Passer en plan Pro pour backups quotidiens + PITR
- OU faire un export manuel hebdomadaire :

```bash
# Via pg_dump (depuis Supabase Dashboard → Database → Connection string)
pg_dump "postgres://postgres:[PWD]@db.ftvowlmrsgcaienvhojj.supabase.co:5432/postgres" \
  --schema=public --no-owner > backup-$(date +%Y%m%d).sql
```

### 5.2 Données sensibles à protéger spécialement

- Mots de passe (déjà hashés SHA-256/PBKDF2)
- Téléphones + nom + prénom + adresse (PII clients/parrains)
- IMEI des téléphones (donnée sensible — devrait être chiffré au repos)
- Coordonnées bancaires (Mobile Money pour paiements parrains)
- Logs d'audit RGPD (légalement sensibles)

## 6. Conventions de schéma

| Convention | Détail |
|---|---|
| **PK** | `BIGSERIAL` (auto-incrément 64 bits) sauf `products.id` qui est TEXT |
| **Timestamps** | `TIMESTAMPTZ` (UTC), `created_at DEFAULT NOW()`, `updated_at` parfois |
| **Soft delete** | Pas de pattern uniforme. Certaines tables ont `_softDeleted` (flag JS, pas SQL — cf. `migration_rgpd_clients_prefs.sql`) |
| **JSONB** | Utilisé pour `meta`, `rgpd_prefs`, `notif_prefs`, `event_data` (extensibilité) |
| **Booléens** | `BOOLEAN DEFAULT FALSE` |
| **Texte libre** | `TEXT` (PostgreSQL n'a pas d'avantage à utiliser VARCHAR) |
| **Enums** | Implémentés via `CHECK (col IN (...))` (pas de type ENUM PostgreSQL) |

## 7. Comment ajouter une nouvelle table

1. **Écrire la migration** dans `/sql/add_NOUVELLE_TABLE.sql`
   ```sql
   CREATE TABLE IF NOT EXISTS public.ma_nouvelle_table (
     id BIGSERIAL PRIMARY KEY,
     ...
     created_at TIMESTAMPTZ DEFAULT NOW()
   );
   
   -- Index nécessaires
   CREATE INDEX IF NOT EXISTS idx_xxx ON public.ma_nouvelle_table(...);
   
   -- RLS
   ALTER TABLE public.ma_nouvelle_table ENABLE ROW LEVEL SECURITY;
   
   CREATE POLICY ... ON public.ma_nouvelle_table
     FOR SELECT USING (...)
     FOR INSERT WITH CHECK (...);
   ```

2. **Exécuter la migration** dans Supabase SQL Editor

3. **Tester côté client** :
   ```javascript
   var { data, error } = await _sb.from('ma_nouvelle_table').select('*').limit(1);
   console.log(data, error);
   ```

4. **Documenter ici** : ajouter la table dans la section appropriée de ce fichier

5. **Commit + push** la migration dans le repo (versioning du schéma)

## 8. Schéma graphique (relations principales)

```
                      ┌──────────┐
                      │  users   │
                      └────┬─────┘
                           │ user_id
            ┌──────────────┼──────────────┬──────────────┐
            ▼              ▼              ▼              ▼
       ┌────────┐    ┌──────────┐   ┌─────────┐   ┌───────────┐
       │ orders │    │  avis    │   │ trocs   │   │product_   │
       └───┬────┘    └──────────┘   └─────────┘   │  views    │
           │                                      └───────────┘
           │ produit_id
           ▼
       ┌──────────┐
       │ products │
       └──────────┘
       
       
       ┌──────────┐    parrain_code     ┌────────┐
       │ parrains │ ◄──────────────────│ users  │
       └────┬─────┘                     └────────┘
            │ parrain_id
            ├──────────────┬──────────────┐
            ▼              ▼              ▼
       ┌──────────────┐ ┌─────────────┐ ┌──────────────┐
       │ commissions  │ │ paiements   │ │ concours     │
       └──────────────┘ └─────────────┘ └──────────────┘
       
       
       ┌────────────┐      ticket_id     ┌──────────────┐
       │chat_       │ ◄──────────────────│chat_         │
       │conversations│                    │tickets       │
       └────────────┘                    └──────────────┘
              │
              │ KPIs SQL views
              ▼
       ┌────────────────┐
       │chat_ticket_kpis│
       │chat_kpis_global│
       │chat_kpis_daily │
       └────────────────┘
```

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
