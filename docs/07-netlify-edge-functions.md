# 07 — Netlify Edge Functions & Serverless Functions

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Vue d'ensemble

Netlify offre 2 types de fonctions serveur :

| Type | Runtime | Latence | Cas d'usage |
|---|---|---|---|
| **Edge Functions** | Deno (V8 isolates) | ~50ms (CDN edge) | Modification de réponse, auth gate, AB testing |
| **Functions** (serverless) | Node.js (AWS Lambda) | ~200ms-2s | Traitement long, intégration tierce, API |

EcoDila utilise **3 Edge Functions** + **2 Functions**.

## 2. Edge Functions

### 2.1 `back-office-gate.js` (10 171 bytes, 241 lignes)

**Rôle** : Gate sécurité pour `/admin*`, `/auditaz*`, `/parrain*`. Premier rempart serveur.

**Routes gérées** (voir `export const config`) :
```javascript
path: [
  "/admin", "/admin/", "/admin.html",
  "/auditaz", "/auditaz/", "/auditaz.html",
  "/parrain", "/parrain/", "/parrain.html"
]
```

**Logique** :

| Route | Comportement |
|---|---|
| `/admin*` | Basic Auth requis (env `ADMIN_AUTH_USER`/`PASS`) |
| `/auditaz*` | Basic Auth requis (env `AUDITAZ_AUTH_USER`/`PASS`) |
| `/parrain*` | Filtrage User-Agent (bots IA + scrapers + curl bloqués) |

**Configuration env vars Netlify** (à faire au déploiement) :

```
ADMIN_AUTH_USER       = melesib_admin   (ou autre)
ADMIN_AUTH_PASS       = mot_de_passe_fort_16+_chars
AUDITAZ_AUTH_USER     = melesib_auditaz (peut être différent)
AUDITAZ_AUTH_PASS     = mot_de_passe_distinct
```

**Fail-closed** : si les variables ne sont pas configurées, retourne une **page 503 "Configuration requise"** au lieu de laisser passer.

**Comparaison de mots de passe** : utilise `safeEquals()` (temps constant) pour résister aux **timing attacks** :
```javascript
function safeEquals(a, b) {
  if (typeof a !== "string" || typeof b !== "string") return false;
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}
```

**Filtre User-Agent (parrain)** : liste de 50+ patterns à bloquer :
- IA crawlers : GPTBot, ClaudeBot, anthropic-ai, Google-Extended, PerplexityBot, CCBot, Bytespider, Applebot-Extended, FacebookBot, Meta-ExternalAgent, cohere-ai, AI2Bot, Diffbot, Amazonbot, DuckAssistBot, Omgilibot, Timpibot, ImagesiftBot, etc.
- SEO/data-mining : AhrefsBot, SemrushBot, MJ12bot, DotBot, BLEXBot, etc.
- Outils scraping : scrapy, magpie-crawler, python-requests, curl/, wget/, Java/, OkHttp, node-fetch, axios/, headlesschrome, phantomjs, puppeteer, playwright, selenium, webdriver

**UA permissifs (passent)** :
- Mozilla/Chrome/Safari/Edge/Firefox (navigateurs réels)
- WhatsApp, facebookexternalhit, Twitterbot, LinkedInBot (previews social)
- Tout UA non-listé qui n'est pas un substring connu

**Réponses HTTP** :

| Cas | Code | Headers spéciaux |
|---|---|---|
| Auth manquante (admin/auditaz) | `401` | `WWW-Authenticate: Basic realm="..."` |
| Bot bloqué (parrain) | `403` | `X-Robots-Tag: noindex, noai, ...` |
| Config env manquante | `503` | (page HTML "Configuration requise") |
| Tout OK | (code original du HTML) | `Cache-Control: no-store` (admin/auditaz seulement) |

**Tests** :
```bash
# Doit retourner 401
curl -I https://ecodila.com/admin.html

# Doit retourner 200
curl -I -u "USER:PASS" https://ecodila.com/admin.html

# Doit retourner 403 (curl bloqué)
curl -I https://ecodila.com/parrain.html

# Doit retourner 200 (Mozilla autorisé)
curl -I -A "Mozilla/5.0 ..." https://ecodila.com/parrain.html

# Doit retourner 403 (GPTBot bloqué)
curl -I -A "Mozilla/5.0 (compatible; GPTBot/1.0)" https://ecodila.com/parrain.html
```

### 2.2 `og-product.js` (370 lignes)

**Rôle** : Réécrit dynamiquement les meta tags Open Graph pour les bots de scraping de previews (WhatsApp, Facebook, Twitter, LinkedIn, Telegram, Slack, Discord, iMessage, Skype, Pinterest, etc.).

**Routes gérées** :
```javascript
path: ["/", "/index.html"]
```

**Logique** :
1. Détecte le User-Agent (BOT_USER_AGENTS list ~30 entrées : `WhatsApp`, `facebookexternalhit`, `Twitterbot`, `LinkedInBot`, `TelegramBot`, `Slackbot`, `Discordbot`, `iMessageBot`, etc.)
2. Si bot ET URL contient `?p=PRODID` :
   - Fetch le produit depuis Supabase
   - Réécrit `<title>`, `og:title`, `og:description`, `og:image`, `og:url`, `twitter:*`
   - Cache 1h navigateur, 1j CDN
3. Si humain : laisse passer normalement (le router JS côté client met à jour les meta tags après chargement)
4. Idem pour `?page=parrainage` etc.

**Pourquoi cette function ?**
Les bots ne supportent pas le routing client-side. Sans cette function, les previews WhatsApp afficheraient toujours le même HTML statique (page d'accueil). Avec, chaque produit a son propre preview riche.

**Performance** :
- Bots : `Cache-Control: public, max-age=3600, s-maxage=86400` (1h navigateur, 1j CDN)
- Humains : `public, max-age=300, stale-while-revalidate=600` (5 min)

**Headers de debug** ajoutés :
- `x-edge-og: product` ou `x-edge-og: page`
- `x-edge-og-bot: yes` ou `no`

### 2.3 `og-image.js` (206 lignes)

**Rôle** : Sert les images de produits sous une URL stable et publique, pour les bots qui ne supportent pas `data:image/...;base64,...` (TOUS les bots de preview).

**Routes gérées** :
```javascript
path: ["/og-image/*"]
```

**Logique** :
1. URL : `/og-image/PROD1234567890` (extension `.jpg` optionnelle)
2. Lit `products.image_principale` depuis Supabase (chaîne base64)
3. Décode le base64 → binaire
4. Retourne le binaire avec `Content-Type: image/jpeg` (ou png/webp selon les magic bytes)
5. Cache 1 jour CDN

**Pourquoi cette function ?**
Sans elle, `og:image` aurait une URL `data:image/jpeg;base64,...` que les bots WhatsApp/Facebook **ne peuvent pas afficher**. Les previews seraient sans image.

**Limites** :
- Image stockée en DB → latence de fetch (atténuée par cache CDN)
- Si l'image > 5 Mo en base64 (~3,75 Mo binaire), problème de mémoire dans la function
- Pas de redimensionnement (toujours servie à la taille upload)

**Améliorations possibles** :
- Migrer les images vers Supabase Storage (URL natives) → pas besoin de cette function
- Ajouter resize côté Edge Function (sharp ou wasm-image)

## 3. Serverless Functions (Node.js)

### 3.1 `claude-proxy.js` (92 lignes)

**Rôle** : Proxy CORS-friendly vers `api.anthropic.com`, utilisé par AUDITAZ pour ses fonctions IA.

**Endpoint** : `/.netlify/functions/claude-proxy`

**Méthode** : `POST` (avec `OPTIONS` pour CORS preflight)

**Headers acceptés** : `Content-Type, x-api-key, anthropic-version`

**Rate limiting** :
```javascript
var RATE_WINDOW = 60000; // 1 minute
var RATE_MAX = 10;       // 10 req/min/IP
var _rateStore = {};     // in-memory
```

**Limite** : `_rateStore` est en mémoire de l'instance Lambda. Sur multi-instance (auto-scaling), le compteur n'est pas partagé. Pour rate-limit fiable cross-instance : utiliser Redis ou Supabase.

**Variables d'environnement requises** :
- `ANTHROPIC_API_KEY` (clé API Anthropic, à NE JAMAIS committer)

⚠️ Si la clé n'est pas configurée, AUDITAZ IA tombera en erreur.

**Format requête typique** :
```javascript
fetch('/.netlify/functions/claude-proxy', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    model: 'claude-3-5-sonnet-latest',
    max_tokens: 1024,
    messages: [{ role: 'user', content: 'Audit ce code...' }]
  })
});
```

**Sécurité** :
- ✓ API key serveur-side uniquement
- ✓ Rate-limit par IP
- ✗ Pas d'auth utilisateur (n'importe qui peut appeler le proxy si trouve l'URL)
- ✗ Pas de filtrage de contenu (un user pourrait abuser pour générer du spam)

**Améliorations possibles** :
- Ajouter une auth (token signé requis)
- Filtre de contenu (regex anti-prompt-injection basique)
- Logs des requêtes en DB

### 3.2 `get-ip.js` (12 lignes)

**Rôle** : Retourne l'IP du client.

**Endpoint** : `/.netlify/functions/get-ip`

**Logique** :
```javascript
var ip = (
  event.headers['x-forwarded-for'] ||
  event.headers['client-ip'] ||
  event.headers['x-real-ip'] ||
  ''
).split(',')[0].trim();

return { 
  statusCode: 200, 
  headers: { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' },
  body: JSON.stringify({ ip: ip || 'unknown' })
};
```

**Usage** : tracking visiteurs anonymes (module Capture IP dans index.html).

**Pourquoi pas en client direct ?** : pour récupérer l'IP, il faut une requête serveur. Cette function évite la dépendance à un service externe (`api.ipify.org`, etc.) qui peut être down ou rate-limit.

## 4. Configuration Netlify

### 4.1 `netlify.toml`

```toml
[build]
  publish = "."
  command = "echo 'Static site'"
  functions = "netlify/functions"
  edge_functions = "netlify/edge-functions"

[functions]
  node_bundler = "esbuild"

# Edge Functions
[[edge_functions]]
  function = "og-product"
  path = "/"

[[edge_functions]]
  function = "og-product"
  path = "/index.html"

[[edge_functions]]
  function = "og-image"
  path = "/og-image/*"

# Back-office gate (6 routes)
[[edge_functions]]
  function = "back-office-gate"
  path = "/admin"

# ... etc pour les 5 autres routes
```

### 4.2 Redirects

```toml
[[redirects]]
  from = "/admin"
  to = "/admin.html"
  status = 200  # rewrite (URL ne change pas)

[[redirects]]
  from = "/parrain"
  to = "/parrain.html"
  status = 200

[[redirects]]
  from = "/auditaz"
  to = "/auditaz.html"
  status = 200

[[redirects]]
  from = "/djassa"
  to = "/parrain"
  status = 301  # redirection permanente
```

**Note** : les redirects s'exécutent APRÈS les Edge Functions. Donc :
- `/admin` → Edge Function fire (auth) → si OK, rewrite vers `/admin.html` → serve

### 4.3 Headers globaux (cf. `_headers` v82)

Voir [_headers](../_headers) — applique sur tout le site :
- Security headers (HSTS, X-Frame-Options, X-Content-Type-Options, CSP, etc.)
- `X-Robots-Tag: noai, noimageai`
- `X-Copyright`
- `Link: rel="ai-policy", rel="license"`

Pour back-offices : `noindex, nofollow, noarchive, nosnippet, nocache, noai, noimageai`.

## 5. Cycle de vie d'une requête

### 5.1 Requête `GET /admin.html` avec Basic Auth correct

```
Client (Chrome)
  ↓ GET /admin.html (Authorization: Basic ...)
[Netlify CDN — region la plus proche]
  ↓
[Edge Function back-office-gate.js fires]
  ↓ Match "/admin.html" — vérifier Basic Auth
  ↓ env vars chargées (ADMIN_AUTH_USER/PASS)
  ↓ Header Authorization parsed et comparé (safeEquals)
  ↓ Match → context.next() pour récupérer la réponse normale
[CDN sert le HTML statique admin.html]
  ↓ Mais Cache-Control = "no-store" (ajouté par addNoCache)
  ↓
[Edge Function ajoute headers : X-Robots-Tag, etc.]
  ↓
Client reçoit HTML 200 + headers de sécurité
  ↓ HTML s'exécute, Supabase init, login custom apparaît
```

### 5.2 Requête `GET /?p=PROD123` depuis WhatsApp

```
WhatsApp bot
  ↓ GET /?p=PROD123 (User-Agent: WhatsApp/2.21)
[CDN]
  ↓
[Edge Function og-product.js fires]
  ↓ Match "/" — détecter UA bot
  ↓ User-Agent "WhatsApp" → match BOT_USER_AGENTS
  ↓ URL contient ?p=PROD123 → fetch produit Supabase
  ↓ Récupère nom, prix, image_principale
  ↓ Récupère le HTML index.html original
  ↓ Réécrit <title>, <meta og:title>, og:description, og:image, og:url
  ↓
WhatsApp reçoit HTML 200 avec meta tags du produit
  ↓ Génère le preview avec image + nom + prix
```

### 5.3 Requête `POST /.netlify/functions/claude-proxy` (AUDITAZ IA)

```
AUDITAZ (browser, user authentifié)
  ↓ POST /.netlify/functions/claude-proxy
  ↓ Body: { model, messages, ... }
[Netlify Lambda spawn ou réutilise instance]
  ↓
[claude-proxy.js exécute]
  ↓ Récupère IP client via _getClientIp(event)
  ↓ Check rate-limit (10/min/IP)
  ↓ Si OK : forward à api.anthropic.com avec API key serveur
  ↓ Si KO : 429 Too Many Requests
  ↓
Anthropic répond → forward au client
  ↓
AUDITAZ reçoit la réponse IA → l'affiche dans l'UI
```

## 6. Logs & monitoring

### 6.1 Logs Netlify

Accès : Netlify Dashboard → Site → **Functions** → choisir une function → **Logs**.

Pour les Edge Functions : Dashboard → **Edge Functions** → Logs.

**Limites du plan gratuit** :
- 125 000 invocations/mois pour les Functions
- 1M invocations/mois pour les Edge Functions

### 6.2 Audit log

Toutes les invocations sont visibles dans le dashboard avec :
- Timestamp
- Status code
- Latence
- Logs `console.log()` (préserver pour debug)

### 6.3 Alerting

Pas configuré par défaut. À configurer si critique :
- Webhook sur erreur 5xx
- Email si quota atteint
- Slack notif sur deploy

## 7. Pièges connus

| Piège | Symptôme | Cause | Fix |
|---|---|---|---|
| **Edge Function ne fire pas** | Route bypass la function | Mauvais path dans config ou conflit avec redirect status 301 | Vérifier `path` exact + status 200 (rewrite, pas redirect) |
| **`Netlify.env.get()` retourne undefined** | Edge Function 503 | Env var pas configurée ou pas redéployée après ajout | Trigger deploy après ajout env vars |
| **`process.env` undefined dans Edge Function** | Erreur runtime | Edge Functions = Deno, pas Node | Utiliser `Netlify.env.get()` |
| **Cold start Lambda > 3s** | Latence claude-proxy première requête | Premier appel après inactivité | Acceptable, 1 user à la fois |
| **Rate limit claude-proxy compté faux en multi-instance** | 11ème requête passe | `_rateStore` in-memory non partagé | Migrer vers Redis ou Supabase rate_limits |
| **Edge Function timeout 50s atteint** | 504 Gateway Timeout | Boucle infinie ou call API lent | Mettre des timeouts explicites sur fetch |
| **CORS error sur claude-proxy** | Browser bloque la requête | Headers CORS pas bons | Vérifier `Access-Control-Allow-*` headers |

## 8. Comment ajouter une nouvelle Edge Function

1. **Créer le fichier** `netlify/edge-functions/ma-fonction.js` :
   ```javascript
   export default async function handler(req, context) {
     // Logique
     return new Response('Hello from edge', {
       status: 200,
       headers: { 'Content-Type': 'text/plain' }
     });
   }
   
   export const config = {
     path: ["/ma-route"]
   };
   ```

2. **Enregistrer dans `netlify.toml`** (optionnel — `export const config` suffit) :
   ```toml
   [[edge_functions]]
     function = "ma-fonction"
     path = "/ma-route"
   ```

3. **Déployer** (git push)

4. **Tester** :
   ```bash
   curl https://ecodila.com/ma-route
   ```

## 9. Comment ajouter une nouvelle Serverless Function

1. **Créer le fichier** `netlify/functions/ma-fonction.js` :
   ```javascript
   exports.handler = async (event) => {
     return {
       statusCode: 200,
       headers: { 'Content-Type': 'application/json' },
       body: JSON.stringify({ ok: true })
     };
   };
   ```

2. **Pas besoin de config netlify.toml** — détection automatique.

3. **Endpoint disponible** : `/.netlify/functions/ma-fonction`

4. **Variables d'environnement** : configurer dans Netlify Dashboard → Site Configuration → Environment Variables.

5. **Tester** :
   ```bash
   curl -X POST https://ecodila.com/.netlify/functions/ma-fonction
   ```

## 10. Tests à faire avant déploiement

- [ ] `back-office-gate.js` : syntaxe OK (`node --check`)
- [ ] `og-product.js` : OG tags réécrits correctement (test via debugger.facebook.com)
- [ ] `og-image.js` : image servie en binaire (pas data:)
- [ ] `claude-proxy.js` : rate-limit fonctionne (>10 req/min → 429)
- [ ] `get-ip.js` : retourne bien l'IP via `x-forwarded-for`
- [ ] Toutes les variables d'environnement configurées dans Netlify
- [ ] Logs Netlify ne contiennent pas d'erreurs récentes

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
