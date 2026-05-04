# 06 — AUDITAZ (`auditaz.html`)

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Vue d'ensemble

`auditaz.html` est l'**outil interne de sécurité, audit et assistance IA** : 22 949 lignes, 2,9 Mo monolithique, **566 fonctions JS classiques**.

**Concept** : c'est un BO **séparé du BO admin standard**, dédié aux missions de :
- Audit sécurité (vulnérabilités, attaques, intrusions)
- Détection de fraude (comportements suspects)
- Monitoring (logs, transferts, performances)
- **Assistant IA pour patcher le code** (génère et applique des modifications via un système de patches)
- Conformité RGPD (rapport ARTCI)

**Accès** : `https://ecodila.com/auditaz.html` ou `/auditaz`

**Authentification** : 2 couches identiques à admin :
1. **HTTP Basic Auth Edge Function** (env vars `AUDITAZ_AUTH_USER` / `AUDITAZ_AUTH_PASS` — distincts de admin !)
2. **Login auditaz custom** (table `auditaz_users`)

## 2. Sections / Modules (27 sections via sidebar)

Navigation via `nav(sectionId)`. Toutes les sections sont des `<div>` avec un `id="sb-..."`.

### 2.1 Dashboard & Monitoring

| Section ID | nav() | Description |
|---|---|---|
| `sb-dash` | `dashboard` | Vue d'ensemble : KPIs sécurité, état général |
| `sb-logs` | `logs` | Logs d'erreurs (`error_logs`) — filtrer par sévérité |
| `sb-notifs` | `notifs` | Notifications internes auditaz |
| `sb-apis` | `apis` | Diagnostic des APIs (Supabase, Anthropic, etc.) |
| `sb-sync` | `sync` | État de synchronisation des données |
| `sb-wh` | `webhooks` | Monitoring webhooks Netlify |
| `sb-perf` | `perf` | Performances (Lighthouse, Web Vitals) |

### 2.2 Sécurité & Détection

| Section ID | nav() | Description |
|---|---|---|
| `sb-transfers` | `transfers` | Monitoring transferts de données (table `auditaz_transfers`) |
| `sb-suspects` | `suspects` | Comportements suspects détectés |
| `sb-blocked` | `blocked` | Utilisateurs bloqués (`auditaz_blocked_users`) |
| `sb-atk` | `attaques` | Tentatives d'attaque détectées |
| `sb-vuln` | `vulns` | Vulnérabilités identifiées |
| `sb-fw` | `firewall` | Configuration firewall (IPs bannies — `auditaz_banned_ips`) |
| `sb-net` | `reseau` | Diagnostic réseau |

### 2.3 Audit fonctionnel

| Section ID | nav() | Description |
|---|---|---|
| `sb-pages` | `pages` | Audit des pages (47/47 pages OK selon code) |
| `sb-btn` | `boutons` | Audit boutons (cliquabilité, accessibilité) |
| `sb-login` | `logins` | Audit logins (tentatives, fails) |
| `sb-sim` | `sims` | Simulations (test scenarios) |
| `sb-comm` | `commissions` | Audit calculs commissions (cas limites, fraude) |
| `sb-data` | `data` | Diagnostic intégrité des données |

### 2.4 IA & Code Patching

| Section ID | nav() | Description |
|---|---|---|
| `sb-analyst` | `analyst` | **Local AI Analyst** — analyse du code en local (sans envoi externe) |
| `sb-builder` | `builder` | **Code Builder** — génère du code via IA |
| `sb-resolve` | `resolve` | Résolution d'incidents (table `auditaz_resolved`) |

### 2.5 Conformité & Rapports

| Section ID | nav() | Description |
|---|---|---|
| `sb-rgpd` | `rgpd-rapport` | **Rapport RGPD/ARTCI** — preuves conformité |
| `sb-rpt` | `rapports` | Rapports génériques |

### 2.6 Configuration & Maintenance

| Section ID | nav() | Description |
|---|---|---|
| `sb-sched` | `scheduler` | Planificateur de tâches (cron-like) |
| `sb-cfg` | `config` | Configuration auditaz (table `auditaz_config`) |

## 3. Modules majeurs

### 3.1 MOTEUR D'ANALYSE IA (L8244)

**Objectif** : permet à l'utilisateur auditaz de **poser des questions en langage naturel** ("Analyse ce code", "Trouve les vulnérabilités XSS dans /admin", "Optimise cette fonction") et obtenir une réponse IA.

**Architecture** :
```
Question utilisateur
   │
   ▼
generateResponse(query)  (L8318)
   │
   ├─→ Si question simple/code → générateurs locaux (pas d'API externe)
   │   ├─ generateCode(topic) (L10512)
   │   ├─ generateAuthCode() (L10597)
   │   ├─ generateProductCode() (L10689)
   │   ├─ generatePaymentCode() (L10847)
   │   ├─ generateXSSCode() (L11261)
   │   └─ ... (~30 générateurs spécialisés)
   │
   └─→ Si question complexe → MOTEUR IA UNIVERSEL (L15081)
       └─→ Appel proxy Anthropic /.netlify/functions/claude-proxy
           (rate-limit 10 req/min/IP)
```

### 3.2 GÉNÉRATEURS DE CODE (~30 fonctions)

Chaque générateur produit du code prêt-à-coller pour un sujet spécifique :

| Générateur | Ligne | Sujet |
|---|---|---|
| `generateAuthCode()` | L10597 | Login, signup, hash password |
| `generateProductCode()` | L10689 | CRUD produits |
| `generateParrainCode()` | L10760 | Logique parrainage |
| `generatePaymentCode()` | L10847 | Paiements (Mobile Money) |
| `generateWhatsAppCode()` | L10919 | Intégration WhatsApp |
| `generateSQLCode()` | L10991 | Requêtes SQL Supabase |
| `generateJWTCode()` | L11045 | JWT auth |
| `generateBOAdminCode()` | L11117 | Code BO admin |
| `generateRateLimitCode()` | L11192 | Rate limiting |
| `generateXSSCode()` | L11261 | Protection XSS |
| `generateUploadCode()` | L11319 | Upload fichiers |
| `generateAPICode()` | L11361 | Appels API |
| `generateAPISecCode()` | L11409 | Sécurité API |
| `generateLocalStorageCode()` | L11456 | LocalStorage |
| `generateImportCode()` | L11505 | Import de données |
| `generateLivraisonCode()` | L11899 | Frais de livraison |
| `generatePromoCode()` | L12187 | Codes promo |
| `generateSearchCode()` | L12256 | Recherche & filtres |
| `generateDashboardStatsCode()` | L12341 | Stats dashboard |
| `generateCustomFeature(topic)` | L12410 | Fallback intelligent |
| `generateAnyFeature(query)` | L15255 | Fallback ULTIME |
| `explainTopic(query)` | L15491 | Explications techniques |
| `debugCode(query)` | L15139 | Debugger |

### 3.3 MOTEUR DONNÉES RÉELLES (L9411)

**Concept** : auditaz peut **lire les données réelles** du site, BO admin et BO parrain pour les analyser.

Tables consultées :
- Toutes les tables Supabase (products, orders, users, parrains, etc.)
- Toutes les tables auditaz_* (logs, transferts, etc.)

**Cas d'usage** :
- "Combien de commandes ont eu lieu ces 7 derniers jours ?"
- "Quel parrain a le plus de filleuls ?"
- "Y a-t-il des doublons dans la table users ?"

### 3.4 APPLY MODAL ENGINE — Code Patcher (L16495+)

**Le module le plus distinctif d'AUDITAZ.**

**Concept** : auditaz peut générer un patch de code (changement à appliquer dans `index.html`, `admin.html`, ou `parrain.html`), le **prévisualiser**, puis **l'appliquer en un clic**.

**Flux** :
```
1. User : "Ajoute un bouton 'Mes données' dans le BO parrain"
   ▼
2. AUDITAZ génère un patch :
   {
     target: 'parrain',
     code: '<button onclick="...">Mes données</button>',
     mode: 'append-before',  // ou 'replace', 'insert-after', etc.
     anchor: '<!-- ANCHOR: nav-end -->',
     description: 'Ajoute bouton RGPD'
   }
   ▼
3. Modal de preview s'ouvre :
   - Affiche le code à appliquer
   - Affiche le diff (avant/après)
   - Vérifications de sécurité :
     • Pas d'eval()
     • Pas de innerHTML avec données externes
     • Pas de href javascript:
   ▼
4. User clique "Appliquer"
   ▼
5. Le patch est appliqué LOCALEMENT (en mémoire navigateur)
   → MAIS le fichier sur le serveur n'est PAS modifié !
   ▼
6. User exporte le code patché et le commit manuellement
```

⚠️ **Limite importante** : AUDITAZ **NE PEUT PAS modifier directement les fichiers du serveur**. Il génère du code à appliquer manuellement par un dev.

**Vérifications de sécurité** (cf. L17569) :
```javascript
if ((ext === 'js' || ext === 'jsx') && /eval\s*\(/.test(patch.code)) {
  errors.push('Utilisation de eval() — risque XSS');
}
```

### 3.5 SYNC HTML RÉELS (L19219)

Charge dynamiquement les fichiers HTML (`index.html`, `admin.html`, `parrain.html`) pour les analyser depuis auditaz.

```javascript
// Approximation
async function _loadRealHTML(target) {
  var url = '/' + target + '.html';  // /index.html, /admin.html, /parrain.html
  var resp = await fetch(url);
  if (!resp.ok) throw new Error('HTTP ' + resp.status);
  return await resp.text();
}
```

⚠️ **Régression possible v82** : depuis l'ajout de la Basic Auth Edge Function, `/admin.html` retourne 401 si AUDITAZ tente de le fetch sans credentials. **À tester**.

**Solution probable** :
- AUDITAZ s'authentifie via Basic Auth en arrière-plan (passe les credentials de l'admin connecté)
- OU récupère le HTML d'une autre manière (via Supabase function?)

### 3.6 Permissions & Multi-utilisateurs

Auditaz supporte plusieurs utilisateurs avec des **permissions granulaires**.

Tables :
- `auditaz_users` : comptes
- `auditaz_permissions` : permissions par user
- `auditaz_activity` : log d'activité

UI de gestion (`umgmtTab`) :
- 👥 Utilisateurs : liste
- ➕ Créer un accès : créer compte
- 🔑 Permissions : gérer permissions
- 📋 Journal d'accès : log d'activité

Presets de permissions :
- `view` : tout en lecture
- `viewer` : tout en lecture (alias)

## 4. Système anti-fraude & sécurité

### 4.1 Détection comportementale

Module qui analyse les patterns suspects :
- Connexions à des heures inhabituelles
- Connexions depuis IPs nouvelles / pays différents
- Clics anormalement rapides (bot ?)
- Création multiple comptes même IP

### 4.2 Bannissement IPs

Table `auditaz_banned_ips` :
- IP bannie temporairement ou définitivement
- Raison du ban
- Date d'expiration

À chaque visite, le code peut consulter cette table (en supplément de l'Edge Function `back-office-gate`).

### 4.3 Blocage utilisateurs

Table `auditaz_blocked_users` :
- user_id bloqué
- Raison
- Bloqué par (auditaz_user_id)
- Date

À chaque login user, on vérifie qu'il n'est pas dans cette table.

## 5. Module IA — claude-proxy.js

Le moteur IA d'AUDITAZ utilise **Claude (Anthropic)** via une fonction proxy Netlify.

**Fichier** : `netlify/functions/claude-proxy.js` (92 lignes)

**Pourquoi un proxy ?** :
- L'API key Anthropic ne doit JAMAIS être exposée côté client
- Le proxy ajoute la clé serveur-side (via env vars Netlify)
- Rate-limiting in-memory (10 req/min/IP)
- Headers CORS contrôlés

**Variables d'environnement requises** :
- `ANTHROPIC_API_KEY` (à configurer dans Netlify env vars)

**Modèle utilisé** : configurable, probablement `claude-sonnet-*` ou `claude-haiku-*` selon le besoin.

⚠️ Si AUDITAZ ne fonctionne plus pour les questions IA :
1. Vérifier que `ANTHROPIC_API_KEY` est configurée dans Netlify env vars
2. Vérifier le quota Anthropic
3. Tester `curl /.netlify/functions/claude-proxy` directement

## 6. Pièges connus & risques

| Piège | Symptôme | Cause | Fix |
|---|---|---|---|
| **AUDITAZ ne charge pas /admin.html** | Erreur 401 dans la console | Basic Auth Edge Function v82 | Authentifier auditaz côté serveur OU charger via Supabase |
| **2 occurrences `eval(` détectées** | Faux positif sécurité | Ce sont des regex `/eval\s*\(/` qui CHECKENT eval() (anti-XSS) | Aucun fix nécessaire — c'est volontaire |
| **`document.write` 3 occurrences** | Templates HTML générés | Templates qui font `w.document.write('<html>...</html>')` (popups) | Pas de risque XSS car contenu contrôlé |
| **`unsafe` 4 occurrences** | À auditer | Probablement noms de variables descriptifs | Vérifier au cas par cas |
| **alert() 50 occurrences** | UX dégradée | Modaux non uniformisés | Remplacer progressivement |
| **Rate limit claude-proxy depasse** | Bloqué par auditaz IA | 10 req/min/IP atteint | Augmenter `RATE_MAX` ou attendre 1 min |

## 7. Bibliothèques externes utilisées

`auditaz.html` est le seul fichier qui charge :
- **xlsx@0.18.5** (export Excel pour les rapports)
- **DOMPurify@3.1.6** (sanitization HTML — sécurité XSS pour le code generator)
- **@supabase/supabase-js@2** (commun)

DOMPurify est utilisé pour sanitizer les patches de code avant affichage dans l'UI :
```javascript
var safe = DOMPurify.sanitize(patch.html);
elem.innerHTML = safe;
```

## 8. Comment ajouter une nouvelle section AUDITAZ

1. **Ajouter dans la sidebar** :
   ```html
   <div class="sb-it" id="sb-mon_audit" onclick="nav('mon_audit');sbActive('sb-mon_audit')">
     🎯 Mon audit <span class="sbb sbb-o">✓</span>
   </div>
   ```

2. **Créer le HTML de la section** :
   ```html
   <div class="content-section" id="section-mon_audit" style="display:none">
     <h2>Mon audit</h2>
     <div id="mon-audit-results"></div>
   </div>
   ```

3. **Câbler dans `nav(id)`** :
   ```javascript
   function nav(id) {
     // ... cacher toutes les sections
     // afficher la section demandée
     if (id === 'mon_audit') {
       document.getElementById('section-mon_audit').style.display = 'block';
       _loadMonAudit();
     }
   }
   ```

4. **Implémenter `_loadMonAudit`** :
   ```javascript
   async function _loadMonAudit() {
     // Logique d'analyse
     var { data } = await _sb.from('ma_table').select('*');
     // Affichage
     document.getElementById('mon-audit-results').innerHTML = ...;
   }
   ```

## 9. Comment ajouter un nouveau générateur de code IA

Tous les générateurs suivent ce pattern :
```javascript
function generateMonGenerateur() {
  return `
// ════════════════════════════════════════════
// MON GÉNÉRATEUR
// ════════════════════════════════════════════
function maNouvelleFct() {
  // ... code généré
}
  `;
}
```

Puis dans `generateResponse(query)` (L8318) ou `generateCode(topic)` (L10512), ajouter le routing :
```javascript
if (query.includes('mon sujet')) return generateMonGenerateur();
```

## 10. Tests à faire avant déploiement

- [ ] Login Basic Auth (Edge Function avec `AUDITAZ_AUTH_USER`/`PASS`)
- [ ] Login auditaz custom — table `auditaz_users` accessible
- [ ] Dashboard : KPIs sécurité affichés
- [ ] Section Logs : `error_logs` lue OK
- [ ] Section Pages : test des 47/47 pages
- [ ] Section APIs : test connectivité Supabase
- [ ] Module IA : test d'une question simple → réponse OK
- [ ] Apply Modal : test génération + preview d'un patch
- [ ] Vérifications anti-eval / anti-XSS bloquent les mauvais patches
- [ ] Module Permissions : créer un utilisateur de test, lui donner des permissions limitées, vérifier
- [ ] Rapport RGPD/ARTCI : génération PDF fonctionne
- [ ] Aucun warning console au load

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
