# 04 — Back-Office Admin (`admin.html`)

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Vue d'ensemble

`admin.html` est le **back-office équipe EcoDila** : 59 012 lignes, 3,4 Mo monolithique, **1 084 fonctions JS classiques** + 462 helpers `window._*`. C'est le plus gros fichier du projet et le plus riche en fonctionnalités.

**Accès** : `https://ecodila.com/admin.html` ou `/admin`

**Authentification 3 couches** :
1. **HTTP Basic Auth Edge Function** (env vars `ADMIN_AUTH_USER` / `ADMIN_AUTH_PASS`) — bloque tout avant même de servir le HTML
2. **Login admin custom** (table `admins`, hash via EcoSec v2 PBKDF2 + AES-GCM + HMAC)
3. **RBAC** (Role-Based Access Control) avec 10 rôles définis

## 2. Modules / Pages disponibles

`ALL_MODULES` (L11240) définit **31 modules** organisés en pages.

### 2.1 Modules principaux

| Module | Icône | Description |
|---|---|---|
| `dashboard` | 📊 | Vue d'ensemble : KPIs, ventes du jour, commandes en attente |
| `produits` | 📦 | CRUD produits (catalogue) |
| `categories` | 🗂 | Gestion des catégories de produits |
| `commandes` | 🛒 | Liste des commandes + statuts + tracking |
| `clients` | 👤 | Gestion clients (PII, historique commandes) |
| `chat-clients` | 💬 | Interface support — répondre aux conversations LIDA |
| `trocs` | 🔄 | Trocs en cours / validés |
| `coupons` | 🏷 | Codes promo |
| `blog` | 📝 | Blog / Pages CMS |
| `avis` | ⭐ | Modération des avis |
| `messages` | 💬 | Messages éditables (synchronisés avec le site) |
| `settings` | ⚙️ | Configuration globale |
| `stats` | 📈 | Statistiques détaillées |
| `pnl` | 📈 | P&L / Rentabilité |
| `admins` | 🔐 | Gestion des comptes admin |
| `errors` | 🚨 | Erreurs & Bugs (logs `error_logs`) |
| `fournisseurs` | 🏭 | Gestion fournisseurs (achats appareils) |
| `negotiations` | 💰 | Suivi des négociations |
| `nego-abandoned` | 💔 | Abandons en cours de négociation (relance) |
| `pagebuilder` | 🎨 | Builder visuel pour pages personnalisées |
| `legal` | 📄 | Gestionnaire CGU/CGV/Mentions légales |
| `backups` | 💾 | Sauvegardes (export DB) |
| `retours` | ↩️ | Gestion retours produits |
| `achats` | 🛒 | Achat d'appareils auprès de particuliers |
| `livraison` | 🚚 | Frais de livraison par zone |
| `reviews` | ⭐ | Modération avis (alias `avis`) |
| `customers` | 👤 | Alias `clients` |
| `orders` | 🛒 | Alias `commandes` |
| `products` | 📦 | Alias `produits` |
| `rgpd-inactifs` | 🔒 | Liste utilisateurs inactifs (purge RGPD) |
| `rgpd-rapport` | 📄 | Rapport RGPD/ARTCI (preuves de conformité) |

### 2.2 Module Parrainage (split en 9 sous-modules)

Le module Parrainage est **éclaté en 9 sous-modules** pour permettre une attribution granulaire des accès.

```javascript
PARRAINAGE_MODULES = [
  'parrainage_dashboard',    // 🤝 Vue d'ensemble
  'parrainage_demandes',     // 📥 Demandes d'inscription parrains
  'parrainage_parrains',     // 👥 Comptes parrains
  'parrainage_commissions',  // 💰 Commissions générées
  'parrainage_paiements',    // 💳 Paiements aux parrains
  'parrainage_fraude',       // 🚨 Détection fraude / abus
  'parrainage_deals',        // 🤝 Deals spéciaux
  'parrainage_challenges',   // 🎯 Challenges parrains
  'parrainage_config',       // ⚙️ Config (taux, palier, règles)
];
```

## 3. Système RBAC (10 rôles)

`ROLES` (L11296) définit les rôles disponibles. Chaque rôle a une couleur, une icône, et une liste de modules accessibles.

| Rôle | Modules accessibles | Cas d'usage |
|---|---|---|
| `super_admin` ⭐ | **TOUS** (`ALL_MODULES`) | Toi, le fondateur. Accès total. |
| `admin_catalogue` 📦 | produits, catégories, stats, achats | Personne dédiée à la gestion produits |
| `admin_commandes` 🛒 | commandes, trocs, clients, chat, stats, pnl, retours, achats | Responsable opérations / livraisons |
| `admin_finance` 💹 | commandes, trocs, négos, clients, stats, pnl, fournisseurs, retours, achats, livraison | Responsable financier / comptable |
| `support_client` 💬 | clients, chat-clients, messages, avis | Agent SAV |
| `marketing` 📣 | blog, coupons, stats, parrainage_challenges, parrainage_deals | Responsable marketing |
| `admin_parrainage` 🤝 | TOUS les modules parrainage | Responsable du programme parrain |
| `parrainage_lecture` 👁️ | dashboard, parrains, commissions (lecture seule) | Auditeur / consultant |
| `parrainage_tresorerie` 💳 | dashboard, commissions, paiements | Trésorier (vire les commissions) |
| `parrainage_modo` 🛡️ | dashboard, demandes, parrains, fraude | Modérateur (anti-fraude) |

**Ajout d'un rôle** : éditer l'objet `ROLES` (L11296) et la table `admins` doit avoir une colonne `role`.

**Vérification d'accès** dans le code :
```javascript
function _hasAccess(moduleId) {
  var currentAdmin = window._currentAdmin;
  if (!currentAdmin || !currentAdmin.role) return false;
  var role = ROLES[currentAdmin.role];
  return role && role.modules.indexOf(moduleId) >= 0;
}
```

## 4. EcoSec v2 (crypto admin)

Module crypto renforcé pour le BO admin (L13187).

**Différences vs site public** :
- Site public : SHA-256 simple
- Admin : **PBKDF2 + AES-GCM + HMAC**

**Algorithmes** :
- **PBKDF2** : dérivation de clé à partir du mot de passe (résistant brute-force)
- **AES-GCM 256** : chiffrement authentifié (intégrité + confidentialité)
- **HMAC-SHA256** : tokens d'intégrité (sessions, etc.)

**Constante critique** :
```javascript
var HMAC_KEY_SALT = new Uint8Array([0x5F,0x2C,0xA8,0x7E,0x31,0xD4,0x96,0xBB,0xE2,0x0F,0x71,0xC3,0x4A,0x85,0x1D,0x60]);
```

⚠️ Si tu changes ce salt, **TOUS les hashes existants deviennent invalides** (les admins ne pourront plus se connecter).

## 5. Système de récupération d'accès BO (L13738)

Si un admin perd son mot de passe, il y a un système de récupération via :
1. Code de récupération généré au moment de la création du compte
2. Stocké côté admin (à imprimer/sauver)
3. À l'usage : confirme via le code → reset password

## 6. Modules métier détaillés

### 6.1 Gestion Produits (`produits` / `products`)

CRUD complet :
- **Créer** : nom, description, catégorie, prix, prix_min, IMEI, image (base64), labels, état
- **Lire** : liste paginée + filtres (catégorie, état, stock, prix)
- **Modifier** : édition inline ou modal
- **Supprimer** : soft delete (flag `_softDeleted`) ou hard delete

**Spécificités** :
- Image stockée en **base64 directement dans `products.image_principale`** (pas de Supabase Storage)
- Limite Postgres : **rows ~1Go max** mais en pratique reste sous 1Mo par image
- Optimisation : compression côté client avant upload (canvas → toDataURL avec quality)

**Attention** : le BO permet d'uploader des images très grandes. Surveiller la taille de `products` avec :
```sql
SELECT pg_size_pretty(pg_total_relation_size('public.products'));
```

### 6.2 Gestion Clients (`clients` / `customers`)

Vue complète d'un client :
- Profil + PII
- Historique commandes
- Historique avis
- Préférences RGPD
- **Activité détaillée** : ventes générées, revenu total, dernière visite
- Actions : reset password, supprimer compte (RGPD), voir conversations chat

**Calcul revenu total** (L21824) :
```javascript
function _custRevenuAct(c) {
  // Formule EXACTE de "💰 Revenu total" dans l'Activité détaillée
  // Somme des montants des orders.statut IN ('livree', 'paiement_recu')
  // moins coupons.montant_appliqué
}
```

### 6.3 Module Chat Clients (`chat-clients`) (L22024-23125)

Interface de support pour répondre aux conversations LIDA.

**Fonctionnalités** :
- Liste des conversations actives (depuis `chat_conversations_summary`)
- Tri par : non-lus, dernière activité, priorité
- Vue par ticket avec historique complet
- Réponse en texte ou avec pièces jointes
- **Pièces jointes BO admin** (L22832) : images personnelles + sélection produits du catalogue
- **Onglets** : Conversations / Dashboard KPIs (L23128)

**Polling** : toutes les 5-10s, met à jour le badge "non lus".

**KPIs Chat Dashboard** :
- FRT (First Response Time) moyen + médian
- Taux de résolution
- Volume tickets sur 7j / 30j
- Auto-fermetures (signe d'abandon)

Sources de données :
- `chat_kpis_global` (vue SQL agrégée)
- `chat_kpis_daily` (vue SQL — graphiques temporels)
- `chat_ticket_kpis` (vue SQL — détail par ticket)

### 6.4 Module Fournisseurs (L18031)

Stockage hybride : `localStorage` + Supabase.

```javascript
var _FOURN_KEY = 'ecodila_fournisseurs';
```

CRUD fournisseurs avec :
- Coordonnées + spécialité
- Historique achats
- Score fiabilité

### 6.5 Moteur Origine Produit (L20796)

**Concept** : tracer l'origine de chaque produit (achat fournisseur, troc client, ...). Permet le P&L précis.

### 6.6 Page Builder (`pagebuilder`)

Outil visuel pour créer des pages CMS sans coder. CSS dédié à L3266.

**Cas d'usage** :
- Page promotion saisonnière
- Landing page campagne marketing
- Page partenaire

### 6.7 Module Coupons (L29230+)

```javascript
const COUP_LS_KEY  = 'ecodila_coupons';
const COUP_HIST_KEY = 'ecodila_coupon_history';
```

CRUD coupons avec :
- Code unique
- Type : pourcentage / montant fixe / livraison gratuite
- Conditions : montant min, produits éligibles, dates de validité
- Limite d'usage (total et par client)
- Historique d'utilisation

### 6.8 Module Marges & Profit (L21181)

```javascript
var CFG_MARGES_KEY = 'ecodila_marges_profit_cfg';
```

Configuration des **tranches de marge ET de négociation**. Sauvegardé dans `settings.marges_profit_cfg`.

Schéma :
```json
{
  "tranches_profit": [
    {"min": 0, "max": 50000, "marge_pct": 30},
    {"min": 50001, "max": 200000, "marge_pct": 25}
  ],
  "tranches_negociation": [
    {"min": 0, "max": 50000, "negociable_pct": 15}
  ]
}
```

### 6.9 Système Alerte Prix d'Achat (L21553)

```javascript
function _getPrixAchat(produitId, nomProduit, etat) { ... }
```

**Concept** : à la saisie d'une commande, système alerte automatiquement si le prix de vente est trop bas par rapport au prix d'achat (perte). Évite les erreurs humaines.

### 6.10 Page RGPD Inactifs (`rgpd-inactifs`)

Conformité RGPD article 5(1)(e) — limitation de la conservation.

**Logique** :
- Liste les utilisateurs inactifs depuis > X mois (configurable)
- Permet anonymisation/suppression en masse
- Trace dans `rgpd_audit_log`

### 6.11 Rapport RGPD/ARTCI (`rgpd-rapport`)

Génération automatique d'un rapport téléchargeable pour audit ARTCI (autorité ivoirienne) ou CNIL (UE).

**Contenu typique** :
- Nombre d'utilisateurs avec consentement
- Statistiques traitements (analytics, marketing, etc.)
- Logs de demandes RGPD (Art 15-22) traitées
- Délai moyen de réponse
- Mesures de sécurité techniques

## 7. Helpers admin spécifiques

### 7.1 `_esc(s)` — échappement HTML

⚠️ **CRITIQUE pour la sécurité XSS**. À utiliser pour toute donnée client injectée via `innerHTML`.

```javascript
function _esc(s){
  if(s==null||s===undefined) return '';
  return String(s)
    .replace(/&/g,'&amp;')
    .replace(/</g,'&lt;')
    .replace(/>/g,'&gt;')
    .replace(/"/g,'&quot;')
    .replace(/'/g,'&#39;')
    .replace(/\//g,'&#x2F;');
}
```

**Usage obligatoire** :
```javascript
// MAUVAIS (XSS si client_name contient <script>)
el.innerHTML = '<div>' + client.nom + '</div>';

// BON
el.innerHTML = '<div>' + _esc(client.nom) + '</div>';
```

### 7.2 `_lsSet` / `_lsGet` — wrappers localStorage avec retry

Gère automatiquement le `QuotaExceededError` en purgeant les vieilles clés.

### 7.3 `_sbRead` / `_sbWrite` — wrapper localStorage simple

Wrapper plus léger (différent de `_lsSet`).

### 7.4 `now()` / `fmtDate(iso)` — helpers dates

```javascript
function now(){ return new Date().toISOString(); }
function fmtDate(iso){ /* format DD/MM/YYYY HH:mm */ }
```

### 7.5 Export CSV / Excel (L4418+)

Module d'export :
- CSV natif
- Excel via SheetJS (pas chargé par défaut, lazy-load au clic)

**Garde-fous exports** (L4418) : empêche les exports de données massifs sans confirmation (RGPD compliance).

## 8. Tracking d'activité admin

### 8.1 Journal des actions

Tout ce que fait un admin est loggé localement dans :
```javascript
var ADM_HIST_KEY = 'ecodila_admin_history_v1';
```

Et synchronisé en DB dans `auditaz_activity` (visible depuis AUDITAZ).

### 8.2 Système de contrôle d'accès (L40252)

Vérifie en permanence que l'admin connecté a le droit d'accéder au module en cours. Si non → redirige vers dashboard avec message d'erreur.

## 9. Pièges connus & risques

| Piège | Symptôme | Fix |
|---|---|---|
| **Image produit > 5 Mo** | Échec INSERT Supabase (limite ligne) | Compression canvas avant upload |
| **`HMAC_KEY_SALT` modifié** | Tous les admins perdent l'accès | NE JAMAIS modifier après prod |
| **Rôle inconnu pour un admin** | Erreur silencieuse → 403 partout | Vérifier `admins.role IN ROLES.keys()` |
| **`localStorage` plein** | Échec sauvegarde panier admin | `_lsSet` purge auto |
| **Migrations SQL non appliquées** | Colonnes manquantes (ex: `priorite`) | Lancer toutes les migrations `/sql/*.sql` |
| **397 `innerHTML`** | Risques XSS si données non échappées | Auditer chaque usage : `_esc()` ou DOMPurify |
| **112 `alert()` natifs** | UX dégradée mobile | À remplacer par modal custom uniformisé |

## 10. Comment ajouter un nouveau module admin

1. **Ajouter dans `ALL_MODULES`** (L11240) :
   ```javascript
   {id:'mon_module', label:'Mon module', icon:'🎯'},
   ```

2. **Ajouter dans les rôles concernés** (L11296) :
   ```javascript
   admin_finance: { ..., modules:['commandes', 'mon_module', ...] }
   ```

3. **Créer le HTML de la page** (chercher `data-page="dashboard"` pour modèle) :
   ```html
   <section data-page="mon_module" class="page" style="display:none">
     <h2>Mon module</h2>
     <div id="mon-module-content"></div>
   </section>
   ```

4. **Créer la fonction de rendu** :
   ```javascript
   async function renderMonModule() {
     var el = document.getElementById('mon-module-content');
     var { data, error } = await _sb.from('ma_table').select('*');
     if (error) { showToast('Erreur: ' + error.message, 'error'); return; }
     el.innerHTML = data.map(item => 
       '<div>' + _esc(item.nom) + '</div>'
     ).join('');
   }
   ```

5. **Câbler dans le routing** (chercher `case 'dashboard':`) :
   ```javascript
   case 'mon_module':
     renderMonModule();
     break;
   ```

6. **Tester** :
   - Login en super_admin
   - Cliquer sur le menu "Mon module"
   - Vérifier que ça affiche bien
   - Login en role limité → vérifier que l'accès est bloqué

## 11. Tests à faire avant déploiement

- [ ] Login Basic Auth (Edge Function) — 401 sans creds, 200 avec
- [ ] Login admin custom — table `admins` accessible
- [ ] Dashboard charge tous les KPIs sans erreur
- [ ] Liste produits paginée OK
- [ ] Création produit (avec image) sauvée en DB
- [ ] Édition produit reflétée sur le site public
- [ ] Liste commandes filtre par statut OK
- [ ] Chat clients : lecture conversations OK, réponse fonctionne
- [ ] Module RGPD : génération rapport OK, droits demandes traités
- [ ] Module marges : sauvegarde `settings.marges_profit_cfg` impacte la nego sur le site
- [ ] Module RBAC : un admin avec rôle limité ne voit que ses modules
- [ ] Export CSV fonctionne
- [ ] Aucun warning console

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
