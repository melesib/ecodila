# 03 — Site Public (`index.html`)

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Vue d'ensemble

`index.html` est la **marketplace publique d'EcoDila** : 40 573 lignes, 2,0 Mo monolithique, 542 fonctions JS classiques + 290 helpers `window._*`.

C'est l'unique point d'entrée des clients (acheteurs particuliers en Côte d'Ivoire). Toutes les pages "métier" sont contenues dans ce fichier et s'affichent via routing par query string.

## 2. Pages disponibles (routing client-side)

| URL | data-page | Description |
|---|---|---|
| `https://ecodila.com/` | `catalogue` | Page d'accueil + liste produits |
| `https://ecodila.com/?p=PROD123` | (fiche produit) | Détail d'un produit + négociation |
| `https://ecodila.com/?page=catalogue` | `catalogue` | Catalogue produits (filtres marque/prix/etat) |
| `https://ecodila.com/?page=acheter` | `acheter` | Formulaire d'achat (sans produit précis) |
| `https://ecodila.com/?page=troquer` | `troquer` | Formulaire de troc (proposer son ancien appareil) |
| `https://ecodila.com/?page=negocier` | `negocier` | Formulaire de négociation libre |
| `https://ecodila.com/?page=parrainage` | `parrainage` | Page d'inscription au programme parrain |
| `https://ecodila.com/?ref=CODE` | (catalogue + tracking) | Visiteur arrivé via lien parrain |

Le routeur côté client gère les transitions sans rechargement de page (équivalent SPA).

## 3. Modules majeurs

### 3.1 Couches d'infrastructure

| Module | Lignes (approx.) | Rôle |
|---|---|---|
| Protection console & DevTools | L5084-5116 | Anti-copie léger (warning console + signal d'intention) |
| Module Capture IP | L5201-6118 | Tracking visiteurs avec gestion 2G/3G dégradée |
| Helpers Network-Résilience | L6119-6130 | Wrappers retry, queue de sync |
| Messages clients centralisés | L6131-6695 | Système de messages éditables depuis BO admin |
| Panneau diagnostic sync | L6696-9257 | UI de diagnostic réseau (caché, accessible via raccourci) |
| Gestionnaire de toasts | L9258-9386 | `showToast()` synchronisé avec BO |
| `_safeOpenWhatsApp` | L9387-9814 | Helper centralisé pour ouvrir WhatsApp avec encodage sécurisé |
| RGPD helpers | L9815-9836 | `_consentStats()`, `_getConsent()`, `_setConsent()` |
| Tracking actions | L9837-9993 | `_trackAction(type, data)` (RGPD-aware) |
| Module RememberMe v2 | L9994-10157 | Token persistant pour auto-login |
| EcoSec (crypto) | L10216-10295 | SHA-256 partagé site + backoffice |

### 3.2 Modules métier

| Module | Lignes (approx.) | Rôle |
|---|---|---|
| **Auth** (login, register, auto-login) | L10003-10215 | Connexion clients via téléphone + password hashé |
| **Droits RGPD** (onglet "Mes données") | L11297-12292 | Export, droit d'accès, droit à l'oubli (Art. 15-22 RGPD) |
| **Mes avis** | L12293-13114 | Affichage et gestion des avis du client |
| **Filtres rétention** | L13115+ | Filtrage temporel (`_RET_JOURS`) |
| **Labels produits** | L14488-14662 | Configuration labels (icônes + tooltips) |
| **Module COUPONS** | L34758-35550 | Codes promo : achat, offre, troc |
| **Module Parrainage** | L37804+ | Inscription comme parrain depuis le site |
| **Module Produit Introuvable** | L39244+ | Modal quand un `?p=PRODID` n'existe plus |

### 3.3 Le bot LIDA (chat support)

#### 3.3.1 Architecture

LIDA est un **chat persistant** intégré au site, accessible via un bouton flottant. Le client communique avec l'équipe support via :
1. Une UI de chat en bas à droite (collapsible)
2. Saisie clavier OU **vocale** (Web Speech API)
3. **Synthèse vocale** (Speech Synthesis API) pour lire les réponses

#### 3.3.2 Backend : `chat_conversations` + `chat_tickets`

Voir [02-base-de-donnees-supabase.md#34-domaine-chat](02-base-de-donnees-supabase.md) pour le détail des tables.

#### 3.3.3 Module `_lidaConv`

Le coeur du système de chat. Ligne ~5376 dans index.html.

**API publique** :

```javascript
window._lidaConv.save(sender, message, messageType)
  // Sauvegarde un message dans Supabase
  // sender = 'client' | 'admin' | 'bot'
  // messageType = 'text' | 'voice' | 'whatsapp_redirect'

window._lidaConv.startPolling()
  // Démarre le polling pour récupérer les nouveaux messages
  // (toutes les 5-10s selon connexion)

window._lidaConv.stopPolling()
  // Arrête le polling

window._lidaConv.migrate(anonId, accountId)
  // Migration anon → compte connecté quand le client se logue
```

**Stockage local** :
- `localStorage.lida_client_id` : ID anonyme persistant (UUID auto-généré au 1er chat)
- À la connexion utilisateur : migration automatique vers le `user_id`

**Système de tickets** :
- Si dernier message > 48h ou ticket précédent fermé → crée nouveau ticket
- Sinon réutilise `_lidaLastTicketId`
- Auto-close après 48h sans activité (tracé dans `chat_tickets.status = 'auto_closed'`)

#### 3.3.4 Reconnaissance vocale

Configuration : `fr-FR`, `continuous: true`, `interimResults: true`, `maxAlternatives: 1`.

**Pipeline de post-traitement** (corrige les erreurs Google Speech) :
```
texte_brut
  → _pickBestAlternative()    (filtre confidence < 10-20%)
  → _appendUnique()           (anti-doublons)
  → _chatDedupeWords()        (déduplication mots)
  → _filterNoiseWords()       (retire euh/hum/ah/etc.)
  → _chatNormalizeEnglishTerms() (iPhone, Galaxy, GB, USB, etc.)
  → _chatFixLidaName()        (Linda/Lisa/Nina → LIDA — fix v79)
  → texte_propre
```

**Fonction `_chatFixLidaName`** ajoutée en v79 (ligne ~31012) :
```javascript
function _chatFixLidaName(text){
  if(!text) return '';
  var variants = /\b(?:lida|lyda|léda|leda|lidha|liddha|linda|lynda|linde|lindl|lindel|lindle|linsa|linza|lynsa|lynza|lisa|liza|lyza|nina|nyna|nida|nyda|nidha)\b/gi;
  return text.replace(variants, 'LIDA');
}
```

#### 3.3.5 Synthèse vocale

Voix française (`fr-FR`) sélectionnée via `speechSynthesis.getVoices().find(v => v.lang === 'fr-FR')`. Lecture des messages bot avec mise en surbrillance des produits cités.

### 3.4 Le moteur de négociation (négociation gamifiée)

**Concept** : quand le client veut acheter, au lieu d'un prix fixe, il rentre dans une "négociation" avec :
- Un **prix initial** affiché (prix max)
- Un **prix minimum** caché côté serveur
- 4 **zones** (vert/jaune/orange/rouge) selon la position du prix proposé
- Une **roue de la chance** (bonus aléatoires : -5%, -10%, livraison gratuite, etc.)
- Des **cartes d'état** (compactes avec prix visible)
- Un système d'**escalation** : si rejet > N fois → "envoyer aux conseillers" via WhatsApp

**Logique métier** dans `settings.marges_profit_cfg` (configurable via BO admin).

**Tracking** : chaque interaction est loggée dans `offer_logs` (zone, spin de roue, bonus accepté, etc.) pour analyses BO.

**Abandon** : si le client quitte sans valider, l'offre + son contexte sont sauvés dans `nego_abandoned` pour relance manuelle équipe support.

### 3.5 Le module RGPD (CRITIQUE)

Le site implémente la **conformité RGPD complète** (le RGPD européen s'applique aux entreprises CI ayant des clients UE, et CI a sa propre loi 2013-450 qui s'en inspire).

**Onglet "Mes données" (L11297+)** : interface utilisateur pour exercer les droits.

| Droit RGPD | Article | Implémenté ? | Comment |
|---|---|---|---|
| Droit d'accès | Art. 15 | ✓ | Export JSON de toutes les données du compte |
| Droit de rectification | Art. 16 | ✓ | Édition directe profil + onglet rectif (parrain) |
| Droit à l'oubli | Art. 17 | ✓ | Suppression compte (avec confirmation) |
| Droit à la portabilité | Art. 20 | ✓ | Export JSON structuré |
| Droit d'opposition | Art. 21 | ✓ | Toggle marketing/analytics dans préférences |
| Consentement granulaire | Art. 7 | ✓ | Banner avec checkboxes (essential, analytics, marketing) |

**Stockage du consentement** :
- `localStorage.ecodila_consent` (JSON : `{essential, analytics, marketing, timestamp}`)
- `users.rgpd_prefs` (JSONB en DB pour utilisateurs connectés)

**Audit log** : `rgpd_audit_log` enregistre chaque demande RGPD (date, type, user_id, traitée par, etc.) — pour preuves en cas d'audit ARTCI / CNIL.

### 3.6 Tracking visiteurs & attribution parrain

**Problématique** : tracker les visiteurs anonymes pour attribuer les ventes au bon parrain, en respectant le RGPD.

**Flux** :
1. Visiteur arrive avec `?ref=PARRAIN_CODE`
2. Module Capture IP (asynchrone, non-bloquant) :
   - Récupère IP via `/.netlify/functions/get-ip`
   - Tente géoloc inverse via `get.geojs.io` (fallback `freeipapi.com`, `ipapi.co`...)
   - Crée/MAJ row dans `visitors` (avec `parrain_code` cf. `add_visitors_parrain_cols.sql`)
3. Si visiteur fait une commande → on associe `users.parrain_code = visitors.parrain_code`
4. Si commande validée → crée `parrain_commissions` pour le parrain

**Performance critique** : tout le module est asynchrone et **non-bloquant**. Les connexions 2G/3G ivoiriennes peuvent être lentes — le site DOIT charger même si ces APIs externes échouent.

### 3.7 Sync queue & résilience réseau

Pattern fréquent pour les actions critiques (commande, paiement, etc.) :

```
Action utilisateur
   │
   ▼
Tentative directe Supabase
   │
   ├─ Succès → OK
   │
   └─ Échec réseau → Mise en queue locale
                       │
                       │ (localStorage.ecodila_sync_queue)
                       │
                       ▼
              Retry automatique en arrière-plan
                       │
                       └─ Succès → Vide la queue
```

Le **panneau diagnostic sync** (caché par défaut, accessible via combo de touches) permet de visualiser l'état de la queue, forcer un retry manuel, etc. Très utile pour le support quand un client signale "ma commande n'est pas passée".

## 4. Sections clés à connaître

### 4.1 Le `<head>` (L1-300 environ)

Contient :
- Favicons (toutes plateformes)
- Meta SEO + Open Graph + Twitter Card
- **Meta anti-IA** (ajoutées en v80 — `GPTBot`, `ClaudeBot`, etc. en `noindex, nofollow`)
- Verification Google Search Console
- Geo meta (CI, Abidjan, lat/lng)
- JSON-LD structured data (Schema.org : `WebSite`, `Organization`, `Store`, `BreadcrumbList`)
- Canonical URL
- Preconnect/preload pour fonts Google

### 4.2 CSS (L100-5050 environ)

CSS custom (pas de Tailwind/Bootstrap). Variables CSS (`--primary`, `--success`, etc.) au début, puis sections par composant.

**Responsive** très travaillé :
- ≥ 769px : Desktop / Fold déplié / Tablette paysage
- 481-768px : Tablette portrait / Fold ouvert
- ≤ 480px : Mobile / Fold replié
- ≤ 360px : Très petits mobiles
- ≤ 280px : **Galaxy Fold fermé** (cas extrême testé)

### 4.3 Constantes globales utiles

| Constante | Ligne approx. | Usage |
|---|---|---|
| `SUPABASE_URL` | dans init Supabase | URL projet |
| `SUPABASE_ANON_KEY` | dans init Supabase | Clé anonyme publique |
| `_sb` | global après init | Client Supabase |
| `LABELS_DEF` | L14490 | Définition des labels produit (source de vérité partagée site + admin) |
| `_RET_JOURS` | L13115 | Filtre rétention en jours (0 = pas de filtre) |
| `_CL_LABELS` | L13469 | Labels checklist par catégorie |

## 5. Points d'extension fréquents

### 5.1 Ajouter une nouvelle page

```javascript
// 1. Dans la fonction de routing (cherche la fonction qui lit ?page=)
case 'ma_nouvelle_page':
  showPage('ma_nouvelle_page');
  break;

// 2. Créer le HTML correspondant (data-page="ma_nouvelle_page")
<section data-page="ma_nouvelle_page" style="display:none">
  <h2>Ma nouvelle page</h2>
  ...
</section>

// 3. (Optionnel) Ajouter au sitemap.xml et menu nav
```

### 5.2 Ajouter une nouvelle phrase à LIDA

Les phrases du bot sont configurables dans `settings.lida_phrases` (BO admin). Pas besoin de toucher au code.

### 5.3 Modifier les marges/zones de négociation

Via BO admin → page "Marges & Profit". Sauvegardé dans `settings.marges_profit_cfg` (JSONB).

Schema attendu :
```json
{
  "tranches_profit": [
    {"min": 0, "max": 50000, "marge_pct": 30},
    {"min": 50001, "max": 200000, "marge_pct": 25},
    {"min": 200001, "max": null, "marge_pct": 20}
  ],
  "tranches_negociation": [
    {"min": 0, "max": 50000, "negociable_pct": 15},
    ...
  ]
}
```

### 5.4 Ajouter un nouveau label produit

1. Modifier `LABELS_DEF` dans `index.html` (L14490)
2. Modifier `ADMIN_LABELS_DEF` dans `admin.html` (L20728) pour synchro
3. Ajouter dans `_CL_LABELS` (L13469) si checklist

## 6. Pièges connus

| Piège | Symptôme | Cause | Fix |
|---|---|---|---|
| **`</body>` apparaît plusieurs fois** dans le HTML | Régression v82 corrigée | Templates JS contiennent `'</body></html>'` | Toujours utiliser `\Z` anchor pour matcher le vrai `</body>` final |
| **Reconnaissance vocale "LIDA" → "Linda/Lisa/Nina"** | Fix v79 | Web Speech API ne connaît pas le mot LIDA | `_chatFixLidaName()` dans pipeline de post-traitement |
| **`localStorage.QuotaExceededError`** | Échec silencieux d'écriture | Quota 5-10Mo dépassé | Wrapper `_lsSet` purge automatiquement |
| **Connexion 2G échoue** sur API externes | UI bloquée | Timeout API tierce non géré | Toujours `_withRetry()` + fallback non-bloquant |
| **Bot LIDA répond aux messages déjà lus** | Doublons | Migration anon → connecté duplique les messages | `_lidaConv.migrate()` gère via dedup par hash |
| **Negotiation prix admin = prix public** | Pas d'écart visible | `prix_min` non configuré sur le produit | Vérifier dans BO admin que tous les produits ont `prix_min` |

## 7. Performance & optimisations

| Optimisation | Détail |
|---|---|
| **Code-splitting via condition** | Modules secondaires (RGPD, parrainage) chargés à la demande quand l'onglet est ouvert |
| **Lazy-load images** | `loading="lazy"` sur toutes les `<img>` |
| **Détection device low-end** | `_perfDevice` détecte si CPU/RAM faibles → désactive certaines animations CSS |
| **2G/3G fallback** | Polls plus longs, retry plus patients, message UI explicite si latence > 5s |
| **CDN Netlify** | Cache HTML 10 min + stale-while-revalidate 1h sur la home |
| **Preload fonts** | Google Fonts préchargées en `crossorigin` |

## 8. Tests à faire avant chaque déploiement

- [ ] Site ouvre en moins de 5s sur 3G simulée (Chrome DevTools → Network throttling Slow 3G)
- [ ] Catalogue affiche les produits depuis Supabase
- [ ] Une fiche produit `?p=PRODID` charge correctement
- [ ] Le bot LIDA accepte un message + répond (poll Supabase OK)
- [ ] La reconnaissance vocale détecte "Bonjour LIDA" (pas Linda)
- [ ] Banner consentement RGPD apparaît au 1er load
- [ ] Login utilisateur fonctionne (téléphone + password)
- [ ] Création compte → SMS/email envoyé (selon config)
- [ ] Préview WhatsApp d'un lien `?p=PRODID` affiche image + nom + prix (test via debugger.facebook.com ou direct WhatsApp)
- [ ] Aucune erreur console au load (F12 → Console)
- [ ] Aucun warning React/Vue (n/a, on est en vanilla)
- [ ] Page /admin.html demande Basic Auth (test régression Edge Function)

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
