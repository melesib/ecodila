# 01 — Architecture Globale

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Vue d'ensemble

EcoDila est un **monolithe HTML par page** déployé en SPA-hybride sur Netlify, alimenté par Supabase pour la persistance et adressant le marché de Côte d'Ivoire (Abidjan principalement).

### 1.1 Choix d'architecture clés

| Choix | Justification | Compromis |
|---|---|---|
| **Pas de framework JS** (vanilla) | Démarrage rapide, taille réduite, contrôle total, débogage facile | Plus de code boilerplate, gestion manuelle du DOM |
| **HTML monolithique** (CSS + JS inline) | 1 seul fichier à déployer, pas de cache miss, idéal connexions 2G/3G CI | Fichiers volumineux (2-3 Mo), parser HTML chargé |
| **Pas de build step** | Édition = déploiement, debug = code source lisible | Pas de minification, pas de tree-shaking, pas de TypeScript |
| **Supabase pour DB+Auth** | Postgres managé + RLS + Realtime + Auth natifs, généreux free tier | Lock-in Supabase, dépendance API tierce |
| **Routing par query string** (`?p=PROD123`, `?page=parrainage`) | Simple, partageable, compatible WhatsApp previews | Pas de routing imbriqué, gestion manuelle |
| **Netlify hosting** | Edge functions, deploys auto via Git, CDN mondial gratuit | Lock-in Netlify pour les Edge Functions |

### 1.2 Schéma haut niveau

```
                           ┌────────────────┐
                           │   ecodila.com  │
                           └────────┬───────┘
                                    │
         ┌──────────────────────────┼──────────────────────────┐
         │                          │                          │
         ▼                          ▼                          ▼
   ┌──────────┐             ┌────────────┐             ┌──────────┐
   │ Public   │             │ Back-office│             │ Édge Fn  │
   │ /        │             │ /admin     │             │ /og-image│
   │ ?p=...   │             │ /parrain   │             │ /og-prod │
   │ ?page=...│             │ /auditaz   │             │ /admin*  │
   └────┬─────┘             └─────┬──────┘             └─────┬────┘
        │                         │                          │
        │ JS client               │ JS client                │ Deno
        │ Supabase client         │ Supabase client          │ runtime
        │                         │                          │
        └─────────┬───────────────┴──────────────────────────┘
                  │
                  ▼
         ┌────────────────┐
         │   Supabase     │
         │  (Postgres)    │
         │  • Auth        │
         │  • Storage     │
         │  • RLS         │
         │  • Realtime    │
         └────────┬───────┘
                  │
        Données : users, products, orders, parrains, propositions,
                  conversations, tickets, offers, settings, ...
```

## 2. Composants principaux

### 2.1 Front-end (client)

**Fichiers HTML** :
- `index.html` — site public client (catalogue, achat, troc, négociation, parrainage)
- `admin.html` — back-office équipe (gestion complète des opérations)
- `parrain.html` — espace parrains "Djassa" (commissions, classement, retraits)
- `auditaz.html` — outil audit/sécurité + assistant IA pour patcher le code

**Pattern commun** : chaque HTML est autonome, charge `@supabase/supabase-js@2` via CDN, initialise un client Supabase avec l'URL + la clé anonyme (publiques), et tout fonctionne en pur client-side.

**Couches communes répliquées dans chaque fichier** :

```
┌─────────────────────────────────────────────────────┐
│  PROTECTION CONSOLE & DEVTOOLS (signal d'intention) │ ← anti-copie léger
├─────────────────────────────────────────────────────┤
│  SUPABASE INIT (client + cache mémoire)             │ ← _sb global
├─────────────────────────────────────────────────────┤
│  PERFORMANCE / DEVICE DETECT (2G/3G, low-end)       │ ← _perfDevice
├─────────────────────────────────────────────────────┤
│  RETRY WRAPPER (network resilience)                 │ ← _withRetry
├─────────────────────────────────────────────────────┤
│  HELPERS NETWORK (sync queue, diagnostic)           │ ← _syncDiag
├─────────────────────────────────────────────────────┤
│  ECOSEC (crypto SHA-256, PBKDF2, AES-GCM, HMAC)     │ ← partagé site/BO
├─────────────────────────────────────────────────────┤
│  AUTH SYSTEM (login + session + remember-me)        │
├─────────────────────────────────────────────────────┤
│  TOAST/NOTIFICATIONS centralisé                     │ ← showToast()
├─────────────────────────────────────────────────────┤
│  RGPD HELPERS (consentement, droit à l'oubli)       │
├─────────────────────────────────────────────────────┤
│  MODULES MÉTIER spécifiques (catalogue, négociation, │
│  chat, BO, etc.)                                    │
└─────────────────────────────────────────────────────┘
```

### 2.2 Edge Functions (Netlify, runtime Deno)

| Fichier | Routes | Rôle |
|---|---|---|
| `netlify/edge-functions/back-office-gate.js` | `/admin*`, `/auditaz*`, `/parrain*` | **Gate sécurité** : Basic Auth pour admin/auditaz, filtrage UA pour parrain |
| `netlify/edge-functions/og-product.js` | `/`, `/index.html` | **Preview dynamique** : si bot WhatsApp/FB et `?p=PRODID`, réécrit les meta og:* avec les vraies infos produit |
| `netlify/edge-functions/og-image.js` | `/og-image/*` | **Sert les images** : décode les images base64 stockées en DB et retourne du binaire HTTP (pour les bots qui ne supportent pas data:image) |

**Caractéristiques** :
- Runtime **Deno** (pas Node — utiliser `Netlify.env.get()` au lieu de `process.env`)
- **Latence très faible** (~50ms, exécution sur edge mondial)
- Pas de cold start
- Accès en lecture à Supabase via fetch direct (URL + anon key)

### 2.3 Serverless Functions (Netlify, runtime Node.js)

| Fichier | Endpoint | Rôle |
|---|---|---|
| `netlify/functions/claude-proxy.js` | `/.netlify/functions/claude-proxy` | **Proxy CORS-friendly** vers `api.anthropic.com`, utilisé par auditaz pour ses fonctions IA. Rate-limit 10 req/min/IP |
| `netlify/functions/get-ip.js` | `/.netlify/functions/get-ip` | Retourne l'IP du client (lit `x-forwarded-for`). Utilisé par le tracking visiteurs |

**Caractéristiques** :
- Runtime **Node.js** (Lambda AWS)
- **Cold start** ~1-3s, latence requête chaude ~100-200ms
- Variables d'environnement Netlify accessibles via `process.env`

### 2.4 Base de données (Supabase Postgres)

Voir [02-base-de-donnees-supabase.md](02-base-de-donnees-supabase.md) pour le détail.

**~40 tables** organisées en domaines :

| Domaine | Tables principales |
|---|---|
| **Utilisateurs** | `users`, `parrains`, `admins`, `auditaz_users` |
| **Catalogue** | `products`, `settings` (config marges, frais) |
| **Commerce** | `orders`, `propositions`, `trocs`, `coupons`, `cart_history` |
| **Négociation** | `offers`, `offer_logs`, `nego_abandoned` |
| **Parrainage** | `parrain_commissions`, `parrain_paiements`, `parrain_concours`, `parrain_statuts` |
| **Chat support** | `chat_conversations`, `chat_tickets`, `chat_kpis_*`, `conversations` |
| **Avis & Reviews** | `avis` |
| **Analytics** | `visitors`, `product_views`, `notifications` |
| **Challenges/Concours** | `challenges`, `concours_paiements` |
| **Audit/Sécurité** | `auditaz_activity`, `auditaz_transfers`, `auditaz_resolved`, `auditaz_banned_ips`, `auditaz_blocked_users`, `error_logs`, `rgpd_audit_log` |

### 2.5 Hébergement & déploiement

```
GitHub (melesib/ecodila)
        │
        │ git push origin master:main
        ▼
   Netlify webhook
        │
        │ Build: "echo 'Static site'" (pas de build, fichiers servis tels quels)
        ▼
   Netlify CDN mondial
        │
        ├─ Cache headers (via _headers + netlify.toml)
        ├─ Edge Functions automatiquement déployées
        └─ HTTPS via certificat Let's Encrypt automatique
```

**Configuration** :
- `netlify.toml` — déclare les Edge Functions, redirects, headers
- `_headers` — headers HTTP par chemin (X-Robots-Tag noai, CSP, etc.)
- `robots.txt` — bloque 35+ bots IA et scrapers
- `ai.txt` — déclaration Spawning AI (no-training)
- `LICENSE.txt` — licence propriétaire bilingue

## 3. Flux de données critiques

### 3.1 Flux d'un achat client (cas nominal)

```
Visiteur
   │ 1. Arrive sur ecodila.com
   ▼
[index.html]
   │ 2. Browse catalogue (charge products via Supabase)
   │ 3. Clique sur un produit → ?p=PRODID
   │ 4. og-product.js réécrit meta tags si bot social
   │ 5. Affiche fiche produit
   │ 6. Lance négociation (modal LIDA + roue chance)
   │
   │ 7. offer_logs : log chaque interaction
   │ 8. offers : sauvegarde l'offre acceptée
   ▼
[Validation panier]
   │ 9. Demande inscription / login
   │ 10. Crée order dans Supabase
   ▼
[Notification équipe]
   │ 11. notifications : crée notif "Nouvelle commande"
   │ 12. WhatsApp via _safeOpenWhatsApp() → équipe livraison
   ▼
[admin.html prend le relais]
   │ 13. Équipe valide la commande
   │ 14. Met à jour statut → "livrée"
   │ 15. Si parrain : crée parrain_commissions
   ▼
[parrain.html notifie]
   │ 16. Parrain voit sa commission dans son espace
```

### 3.2 Flux du chat support (LIDA → équipe)

```
Client tape un message dans le chat flottant
   ▼
index.html : _lidaConv.save(sender='user', message)
   ▼
Supabase : INSERT INTO chat_conversations (client_id, sender, message, ticket_id)
   ▼
   │ Si pas de ticket actif récent → CREATE chat_tickets (statut='ouvert')
   │ Si message contient mots-clés → fallback "envoyer aux conseillers"
   ▼
Polling depuis admin.html (Module Chat Clients)
   ▼
Admin voit la conversation, répond
   ▼
Supabase : INSERT INTO chat_conversations (sender='bot', message, ticket_id)
   ▼
Polling depuis index.html → message s'affiche au client
   ▼
   │ Auto-fermeture après 48h sans activité (ticket → 'ferme')
   │ KPIs calculés par chat_ticket_kpis (vue SQL)
```

### 3.3 Flux d'authentification

| Scope | Mécanisme | Lieu |
|---|---|---|
| **Site public** (clients) | Login custom (téléphone + mot de passe SHA-256 via EcoSec) → `users` | index.html |
| **BO Admin** | 1) **Basic Auth Edge Function** (server-side, env vars Netlify) → 2) Login admin custom → `admins` | back-office-gate.js + admin.html |
| **BO AUDITAZ** | 1) **Basic Auth Edge Function** (env vars distincts) → 2) Login auditaz → `auditaz_users` | back-office-gate.js + auditaz.html |
| **BO Parrain** | Filtrage UA bot → Login parrain custom → `parrains` (la table parrains est protégée par RLS) | back-office-gate.js + parrain.html |
| **Supabase** | Anon key publique + RLS sur les tables | Toutes les pages |

## 4. Patterns de code récurrents

### 4.1 Le client Supabase global

```javascript
// Initialisation typique (présente dans les 4 HTML)
var SUPABASE_URL = "https://ftvowlmrsgcaienvhojj.supabase.co";
var SUPABASE_ANON_KEY = "eyJhbGc...";  // clé publique (safe pour client)
var _sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);

// Usage
async function fetchProducts() {
  var { data, error } = await _sb.from('products')
                                   .select('*')
                                   .eq('actif', true);
  if (error) console.warn('[fetch]', error.message);
  return data || [];
}
```

### 4.2 Le wrapper de retry réseau

```javascript
// Présent dans index.html, parrain.html (RETRY WRAPPER)
function _withRetry(fn, opts) {
  opts = opts || {};
  var max = opts.max || 3;
  var delay = opts.delay || 500;
  return new Promise(async function(resolve, reject) {
    var lastErr;
    for (var i = 0; i < max; i++) {
      try {
        var result = await fn();
        return resolve(result);
      } catch (e) {
        lastErr = e;
        await new Promise(r => setTimeout(r, delay * (i+1)));
      }
    }
    reject(lastErr);
  });
}
```

### 4.3 Toast/Notification

```javascript
// Présent dans les 4 HTML — interface unifiée
showToast('✓ Produit ajouté au panier', 'success');
showToast('❌ Erreur de connexion', 'error');
showToast('⚠️ Vérifiez votre saisie', 'warning');
```

### 4.4 Stockage local sécurisé

```javascript
// admin.html — _lsSet wrapper
function _lsSet(key, value) {
  try {
    localStorage.setItem(key, JSON.stringify(value));
    return true;
  } catch (e) {
    if (e.name === 'QuotaExceededError') {
      // Purge intelligente : supprime les vieux logs/caches d'abord
      _purgeOldLocalStorage();
      try { localStorage.setItem(key, JSON.stringify(value)); return true; }
      catch (e2) { console.warn('LocalStorage full après purge'); return false; }
    }
    return false;
  }
}
```

### 4.5 RGPD-aware tracking

```javascript
// Toujours vérifier le consentement avant de tracker
function _trackAction(type, data) {
  var consent = window._getConsent && window._getConsent();
  if (!consent || !consent.analytics) return;  // pas de consentement → no-op
  // ... logique de tracking
}
```

## 5. Conventions de nommage

| Pattern | Signification | Exemple |
|---|---|---|
| `_xxx` (préfixe underscore) | Helper interne, "privé" par convention | `_safeOpenWhatsApp`, `_withRetry`, `_lsSet` |
| `window._xxx` | Helper exposé globalement (cross-module) | `window._lidaConv`, `window._consentStats` |
| `_sb` | Client Supabase (raccourci) | `_sb.from('users').select()` |
| `_RET_*` | Constantes de rétention/durée | `_RET_JOURS = 0` (filtre désactivé) |
| `EcoSec.xxx` | Module crypto (SHA-256, PBKDF2, AES-GCM) | `EcoSec.hashPassword(pwd)` |
| `LIDA_*` | Configuration du bot conversationnel | `LIDA_AVATAR` |
| `UPPER_CASE` | Constantes JS | `SUPABASE_URL`, `RATE_MAX` |
| `kebab-case` | Classes CSS | `.lida-avatar`, `.voice-transcript` |

## 6. Modules transverses partagés

### 6.1 EcoSec (crypto)

Module crypto présent dans `index.html`, `admin.html`, `parrain.html`. Utilise Web Crypto API native.

| Fonction | Algorithme | Usage |
|---|---|---|
| `EcoSec.hashPassword(pwd)` | SHA-256 (site) ou PBKDF2 (admin v2) | Hash mot de passe avant envoi DB |
| `EcoSec.encrypt(data, key)` | AES-GCM 256 | Chiffrement local sensible |
| `EcoSec.hmac(data, key)` | HMAC-SHA256 | Intégrité de tokens |

**Important** : le mot de passe n'est JAMAIS envoyé en clair à Supabase. Le hash est calculé côté client puis stocké côté DB.

### 6.2 LIDA (bot conversationnel)

Voir [03-site-public-index.md#bot-lida](03-site-public-index.md) pour le détail.

Présent uniquement dans `index.html`. Système de chat persistant avec :
- Polling Supabase pour les messages
- Sauvegarde dans `chat_conversations`
- Système de tickets auto-fermants
- Reconnaissance vocale (SpeechRecognition API + post-traitement `_chatFixLidaName` pour corriger les variantes mal entendues)
- Synthèse vocale (SpeechSynthesis API)

### 6.3 Module RGPD (consentement)

Présent dans les 4 HTML. Helpers :

```javascript
window._getConsent()           // → { analytics, marketing, essential }
window._setConsent(prefs)      // → met à jour cookies + DB users.rgpd_prefs
window._consentStats()         // → stats de consentement (admin only)
```

Banner de consentement affiché au 1er load. Stockage : `localStorage.ecodila_consent` + `users.rgpd_prefs` (JSONB) si user connecté.

## 7. Limites & risques de l'architecture actuelle

| Limite | Impact | Mitigation possible |
|---|---|---|
| **Fichiers HTML monolithiques 2-3 Mo** | Temps de chargement long sur 2G | Code-split conditionnel, lazy-load des modules non critiques |
| **Pas de TypeScript** | Erreurs runtime non détectées à l'avance | Migrer vers JSDoc-typed JS (sans build), ou TS avec esbuild léger |
| **Pas de tests automatisés** | Régression possible à chaque modif | Tests unitaires Vitest sur fonctions pures, tests E2E Playwright |
| **Logique métier dupliquée** entre les 4 HTML (toast, retry, EcoSec, RGPD) | Maintenance lourde — 1 fix = 4 endroits | Extraire en `assets/common.js` chargé par les 4 |
| **Pas de monitoring runtime** | Bugs prod invisibles | Sentry browser SDK ou alternative légère |
| **innerHTML omniprésent** (838 occurrences) | Risque XSS si données externes | Audit ligne par ligne ou usage systématique de `textContent` / `DOMPurify` |
| **alert()` natif** utilisé (~178 occurrences cumulées) | UX mauvaise sur mobile | Remplacer par un modal custom uniformisé |

Voir [08-securite-et-risques.md](08-securite-et-risques.md) pour l'audit complet.

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
