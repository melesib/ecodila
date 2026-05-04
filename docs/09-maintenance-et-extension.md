# 09 — Maintenance & Extension

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Setup local (développement sur ton ordi)

### 1.1 Prérequis

| Outil | Version | Pour quoi faire |
|---|---|---|
| **Git** | n'importe | Cloner le repo, commit, push |
| **Navigateur moderne** | Chrome/Firefox/Edge récent | Tester en local |
| **Éditeur de code** | VSCode (recommandé) | Éditer les fichiers |
| **Node.js** (optionnel) | 18+ | Tester les Netlify Functions en local |
| **Netlify CLI** (optionnel) | latest | Tester Edge Functions + Functions ensemble |

**Note** : pas besoin de Node pour modifier le HTML/CSS/JS — le site fonctionne en ouvrant simplement les fichiers dans un navigateur.

### 1.2 Cloner le repo

```bash
cd ~/Documents
git clone https://github.com/melesib/ecodila.git ecodila-refactor
cd ecodila-refactor
```

### 1.3 Servir en local (3 options)

#### Option A — Simple (juste ouvrir le HTML)

Inconvénient : `fetch()` ne marche pas (CORS), Edge Functions ne tournent pas, mais OK pour debug visuel.

```bash
open index.html  # macOS
xdg-open index.html  # Linux
start index.html  # Windows
```

#### Option B — Serveur HTTP simple (recommandé pour debug visuel)

```bash
# Avec Python (préinstallé sur la plupart des systèmes)
python3 -m http.server 8080
# → http://localhost:8080/

# Ou avec Node (si installé)
npx http-server -p 8080
```

Dans ce cas, **Supabase fonctionne** (CORS OK), mais pas les Edge Functions.

#### Option C — Netlify Dev (idéal — simule la prod)

```bash
# Installation
npm install -g netlify-cli

# Login
netlify login

# Lien avec ton site (1ère fois uniquement)
netlify link

# Lancer le serveur de dev
netlify dev
# → http://localhost:8888/
```

Avantages :
- Edge Functions tournent en local
- Functions Lambda tournent en local
- Variables d'environnement chargées depuis le dashboard Netlify
- Headers + redirects appliqués

### 1.4 Vérifier que tout marche

1. Ouvre `http://localhost:8080/` (ou 8888 si Netlify dev)
2. F12 → Console → vérifie qu'il n'y a pas d'erreur Supabase
3. Catalogue produits affiché → ✅
4. Test login utilisateur → ✅
5. Test bot LIDA → ✅

---

## 2. Workflow de déploiement

### 2.1 Pattern actuel (utilisé par toi)

```bash
# 1. Tu reçois un zip d'une mise à jour (typiquement /mnt/user-data/outputs/ecodila-vXX.zip)
unzip ~/Downloads/ecodila-vXX.zip -d /tmp/ecodila-new

# 2. Tu vérifies le contenu
ls /tmp/ecodila-new

# 3. Tu écrases ton dossier local
rm -rf ~/Documents/ecodila-refactor
mv /tmp/ecodila-new ~/Documents/ecodila-refactor
cd ~/Documents/ecodila-refactor

# 4. Tu init un repo git temporaire et tu push en force
git init
git remote add origin https://github.com/melesib/ecodila.git
git checkout -b master
git add -A
git commit -m "Update: vXX — description"
git push origin master:main --force

# 5. Netlify détecte le push, déploie automatiquement
# → Vérifier sur https://app.netlify.com/sites/ecodila/deploys
```

### 2.2 Pattern alternatif (recommandé — plus propre)

Au lieu de réinit le repo à chaque fois, tu peux :

```bash
cd ~/Documents/ecodila-refactor

# 1. Backup ton état actuel
git checkout -b backup-$(date +%Y%m%d-%H%M)

# 2. Récupère la nouvelle version
unzip ~/Downloads/ecodila-vXX.zip -d /tmp/ecodila-new
# Copie tous les fichiers (sauf .git !)
cp -r /tmp/ecodila-new/* /tmp/ecodila-new/.* . 2>/dev/null

# 3. Voir ce qui a changé
git status
git diff index.html | head -100  # exemple

# 4. Commit et push
git checkout main
git add -A
git commit -m "vXX: description claire des changements"
git push origin main
```

Avantages :
- Historique git propre (pas de force-push qui efface l'historique)
- Branches de backup avant chaque mise à jour
- Diff visible avant commit

### 2.3 Vérifier le déploiement

1. **Netlify Dashboard** : https://app.netlify.com/sites/ecodila/deploys
   - Status : "Published" ✓
   - Logs : pas d'erreurs

2. **Tests prod** :
   ```bash
   # Site public
   curl -I https://ecodila.com/
   # → HTTP/2 200, headers OK
   
   # BO admin (sans auth)
   curl -I https://ecodila.com/admin.html
   # → HTTP/2 401 (Basic Auth requis)
   
   # BO admin (avec auth)
   curl -I -u "USER:PASS" https://ecodila.com/admin.html
   # → HTTP/2 200
   
   # BO parrain (curl bloqué)
   curl -I https://ecodila.com/parrain.html
   # → HTTP/2 403
   
   # BO parrain (Mozilla OK)
   curl -I -A "Mozilla/5.0 ..." https://ecodila.com/parrain.html
   # → HTTP/2 200
   ```

3. **Tests dans le navigateur** :
   - Site charge en moins de 5s
   - Login user fonctionne
   - Bot LIDA répond
   - BO admin login fonctionne (Basic Auth + login custom)

### 2.4 Rollback en cas de problème

#### Rollback rapide via Netlify

1. Netlify Dashboard → Site → **Deploys**
2. Trouver le dernier deploy qui marchait → **Publish deploy**
3. → Le site revient à cet état en ~30s

#### Rollback via Git

```bash
cd ~/Documents/ecodila-refactor

# Trouver le commit OK
git log --oneline | head -10

# Revenir à ce commit (sans perdre l'historique)
git revert HEAD  # annule le dernier commit en créant un nouveau

# OU (plus brutal)
git reset --hard COMMIT_HASH
git push origin main --force
```

---

## 3. Variables d'environnement Netlify

### 3.1 Liste actuelle

| Variable | Usage | Obligatoire ? |
|---|---|---|
| `ADMIN_AUTH_USER` | Login Basic Auth pour `/admin*` | OUI |
| `ADMIN_AUTH_PASS` | Password Basic Auth pour `/admin*` | OUI |
| `AUDITAZ_AUTH_USER` | Login Basic Auth pour `/auditaz*` | OUI |
| `AUDITAZ_AUTH_PASS` | Password Basic Auth pour `/auditaz*` | OUI |
| `ANTHROPIC_API_KEY` | Pour `claude-proxy.js` (AUDITAZ IA) | OUI si AUDITAZ IA utilisée |

### 3.2 Comment configurer

1. Aller sur https://app.netlify.com → site EcoDila
2. **Site Configuration** (ou **Project Configuration** dans certaines UI)
3. **Environment variables**
4. **Add a variable**
5. Saisir nom + valeur
6. **Sauvegarder**
7. **Très important** : **Trigger deploy → Clear cache and deploy site**
   - Sans ça, les Edge Functions ne verront pas les nouvelles env vars

### 3.3 Vérifier qu'une env var est bien chargée

```bash
# Test : si non chargée, /admin.html retourne 503
curl -I https://ecodila.com/admin.html
# Si 503 → env vars manquantes
# Si 401 → env vars OK, Basic Auth demandée
```

### 3.4 Rotation des credentials

Recommandé tous les **90 jours** :

1. Générer un nouveau password fort (16+ chars, gestionnaire de password)
2. Mettre à jour dans Netlify env vars
3. **Trigger deploy**
4. Tester avec curl
5. Communiquer le nouveau password à l'équipe (si plusieurs personnes)

---

## 4. Comment débugger

### 4.1 Côté client (navigateur)

#### Activer la console malgré la "Protection Console & DevTools"

Le code désactive la console en prod par anti-copie. Pour debugger :

**Option 1** : ouvrir la console **AVANT** que la page charge (Ctrl+Shift+I avant d'aller sur l'URL).

**Option 2** : ajouter `?dev=1` à l'URL et adapter le code pour ne pas désactiver la console si ce paramètre est présent.

#### Inspecter Supabase

```javascript
// Dans la console du navigateur
_sb.from('users').select('*').limit(5).then(console.log);
```

#### Voir l'état localStorage

```javascript
// Dans la console
Object.keys(localStorage).forEach(k => console.log(k, '=', localStorage.getItem(k)));
```

#### Vider le cache pour tester un fix

```javascript
localStorage.clear();
sessionStorage.clear();
location.reload(true);
```

### 4.2 Côté serveur (Netlify)

1. **Netlify Dashboard** → Site → **Functions** → cliquer sur la function
2. **Logs** → voir les invocations en temps réel
3. **Console** → tester en mode interactif

### 4.3 Côté DB (Supabase)

1. **SQL Editor** : exécuter des requêtes
2. **Logs** → API Edge Logs : voir les requêtes entrantes
3. **Logs** → Database Logs : voir les erreurs Postgres

### 4.4 Tracer un bug spécifique

#### Cas type : "Le client X dit que sa commande n'est pas passée"

```sql
-- 1. Chercher le user
SELECT * FROM users WHERE telephone = '+225XXXXXXXX';

-- 2. Chercher ses commandes récentes
SELECT * FROM orders 
WHERE user_id = (SELECT id FROM users WHERE telephone = '+225XXXXXXXX')
ORDER BY created_at DESC LIMIT 10;

-- 3. Chercher dans les abandonnées
SELECT * FROM nego_abandoned 
WHERE telephone = '+225XXXXXXXX'
ORDER BY created_at DESC LIMIT 5;

-- 4. Chercher dans les logs d'offres
SELECT * FROM offer_logs 
WHERE client_id = '+225XXXXXXXX'
ORDER BY created_at DESC LIMIT 20;

-- 5. Chercher dans error_logs
SELECT * FROM error_logs 
WHERE meta->>'user_phone' = '+225XXXXXXXX'
ORDER BY created_at DESC LIMIT 10;
```

---

## 5. Comment étendre le projet

### 5.1 Ajouter une nouvelle table Supabase

Voir [02-base-de-donnees-supabase.md#7-comment-ajouter-une-nouvelle-table](02-base-de-donnees-supabase.md).

**Workflow complet** :

```bash
# 1. Créer la migration
cat > sql/add_ma_table.sql << 'EOF'
CREATE TABLE IF NOT EXISTS public.ma_table (
  id BIGSERIAL PRIMARY KEY,
  nom TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.ma_table ENABLE ROW LEVEL SECURITY;
-- ⚠️ AJOUTER UNE POLICY APPROPRIÉE (pas USING (TRUE) sur données sensibles)
CREATE POLICY ma_table_select ON public.ma_table 
  FOR SELECT USING (TRUE);  -- adapter selon le besoin
EOF

# 2. Exécuter dans Supabase
# → Dashboard → SQL Editor → Coller le contenu → Run

# 3. Documenter dans /docs/02-base-de-donnees-supabase.md (ajouter dans l'inventaire)

# 4. Utiliser dans le code
# var { data, error } = await _sb.from('ma_table').select('*');

# 5. Commit
git add sql/add_ma_table.sql docs/02-base-de-donnees-supabase.md
git commit -m "Add table ma_table for [feature]"
```

### 5.2 Ajouter une nouvelle page admin

Voir [04-bo-admin.md#10-comment-ajouter-un-nouveau-module-admin](04-bo-admin.md).

**TL;DR** :
1. Ajouter dans `ALL_MODULES` (L11240)
2. Ajouter dans les rôles voulus (`ROLES`, L11296)
3. Créer le HTML `<section data-page="...">`
4. Créer la fonction `renderXxx()` avec `_esc()` partout
5. Câbler dans le routing

### 5.3 Ajouter une nouvelle page parrain

Voir [05-bo-parrain.md#11-comment-ajouter-une-nouvelle-page](05-bo-parrain.md).

### 5.4 Ajouter une nouvelle Edge Function

Voir [07-netlify-edge-functions.md#8-comment-ajouter-une-nouvelle-edge-function](07-netlify-edge-functions.md).

### 5.5 Ajouter une nouvelle phrase / un nouveau scénario à LIDA

Les phrases sont dans `settings.lida_phrases` (configurables depuis BO admin → page `messages`). Pas besoin de toucher au code pour ajouter du contenu.

Pour ajouter une **nouvelle logique métier** dans LIDA :
1. Trouver `_lidaConv` ou `_chatProcess` dans `index.html`
2. Ajouter ton cas dans le switch / les conditions
3. Tester avec `localStorage.clear()` puis interaction

### 5.6 Ajouter un nouveau type de notification

Tables impliquées : `notifications` (DB).

```javascript
// Côté code (admin.html ou parrain.html)
async function _sendNotif(userType, userId, title, message, action_url) {
  return _sb.from('notifications').insert({
    user_type: userType,    // 'user', 'parrain', 'admin'
    user_id: userId,
    title: title,
    message: message,
    action_url: action_url,
    read: false,
    created_at: new Date().toISOString()
  });
}
```

### 5.7 Ajouter un nouveau Concours / Challenge parrain

**100% configurable** depuis BO admin → `parrainage_challenges` (pas besoin de toucher au code) :

1. Aller dans BO admin → Parrainage → Challenges
2. Créer un nouveau challenge avec :
   - Nom
   - Description
   - Type (`ventes`, `filleuls`, `commission_total`, etc.)
   - Objectif (chiffre)
   - Récompense (texte ou montant)
   - Dates début/fin
3. Sauvegarder
4. Le challenge apparaît automatiquement chez les parrains (page Challenges)

---

## 6. Maintenance préventive — checklist mensuelle

### 6.1 Premier lundi du mois

- [ ] **Backups** : faire un `pg_dump` complet et le stocker offline
- [ ] **Logs Netlify** : parcourir 1 mois, repérer pics d'erreurs
- [ ] **Logs Supabase** : pareil, repérer requêtes lentes
- [ ] **`error_logs` (DB)** : analyser le top 10 par fréquence
- [ ] **`auditaz_activity`** : repérer comportements anormaux
- [ ] **Mises à jour CDN** : vérifier qu'aucune dépendance n'a une CVE (https://snyk.io/advisor/)
- [ ] **Quota Netlify** : vérifier que tu ne brûles pas tes invocations
- [ ] **Quota Supabase** : vérifier DB size, bandwidth, auth users
- [ ] **Quota Anthropic** (si AUDITAZ IA actif) : vérifier consommation API

### 6.2 Tous les 3 mois

- [ ] **Rotation passwords** Netlify env vars
- [ ] **Audit RLS** Supabase (1 table par jour suffit, en boucle)
- [ ] **Test de restoration** : faire restorer un backup sur un projet de staging
- [ ] **Test pénétration light** : essayer toi-même de brute-forcer un login, scraper une page, etc.

### 6.3 Tous les 6 mois

- [ ] **Audit dependencies** : revue complète des CDN
- [ ] **Tests fonctionnels** : parcourir le site comme un client (achat E2E, troc, parrain)
- [ ] **Mise à jour LICENSE.txt + ai.txt** si nouveau standard apparu
- [ ] **Revue des bots IA bloqués** : ajouter les nouveaux dans `back-office-gate.js`

---

## 7. Que faire quand tu reçois un nouveau zip de mise à jour

### 7.1 Workflow vérification

```bash
# 1. Examiner le contenu avant de déployer
mkdir /tmp/check-update
cd /tmp/check-update
unzip ~/Downloads/ecodila-vXX.zip
ls -la

# 2. Vérifier les fichiers HTML (taille raisonnable)
ls -lh *.html
# index.html doit être ~2 Mo
# admin.html doit être ~3-3.5 Mo
# parrain.html doit être ~600-700 Ko
# auditaz.html doit être ~2.5-3 Mo

# 3. Vérifier qu'il n'y a pas de regression sur les fichiers Netlify
ls netlify/edge-functions/
# Doit contenir : back-office-gate.js, og-product.js, og-image.js
ls netlify/functions/
# Doit contenir : claude-proxy.js, get-ip.js

# 4. Vérifier le netlify.toml + _headers
cat netlify.toml
cat _headers

# 5. Diff avec ta version actuelle (si tu as un repo local)
diff -q /tmp/check-update ~/Documents/ecodila-refactor | head -20
```

### 7.2 Tests avant deploy en prod

Si tu peux : déploie d'abord sur un site **Netlify de staging** (créer un site secondaire `ecodila-staging.netlify.app`) :

```bash
# Avec netlify CLI
netlify deploy --dir=. --site=ID_STAGING
# → URL temporaire pour tester

# Si tout OK
netlify deploy --dir=. --site=ID_STAGING --prod
```

### 7.3 Tests post-deploy

Voir section 2.3 — checklist standard.

### 7.4 Documentation des changements

Tenir un fichier `CHANGELOG.md` à la racine :

```markdown
# Changelog

## v82 — 4 mai 2026
- 🔒 [SEC] Audit pre-deploy : fix bug JS string newlines
- 🔒 [SEC] Fix anti-copie inséré au mauvais </body>
- 🛡️ [SEC] Soft anti-copie (retire dragstart, contextmenu pour préserver UX)

## v81 — 3 mai 2026
- 🛡️ [SEC] Server-side Basic Auth via Edge Function pour /admin et /auditaz
- 🛡️ [SEC] User-Agent filtering pour /parrain
- 📚 README-SECURITY.md créé

## v80 — 2 mai 2026
- 🛡️ [SEC] Anti-IA / anti-scraping multi-niveaux
- 📜 LICENSE.txt + ai.txt + meta tags
- 📜 robots.txt mis à jour avec 35+ bots IA

## v79 — 1 mai 2026
- 🐛 [FIX] Bot LIDA : fix reconnaissance vocale "LIDA" (Linda/Lisa/Nina)
```

---

## 8. Ressources externes utiles

### 8.1 Documentation des outils

| Outil | URL |
|---|---|
| Supabase | https://supabase.com/docs |
| Netlify | https://docs.netlify.com/ |
| Netlify Edge Functions | https://docs.netlify.com/edge-functions/overview/ |
| Web Crypto API | https://developer.mozilla.org/en-US/docs/Web/API/Web_Crypto_API |
| Anthropic API | https://docs.anthropic.com/ |

### 8.2 Outils utiles

| Outil | URL | Pour quoi |
|---|---|---|
| Facebook Sharing Debugger | https://developers.facebook.com/tools/debug/ | Tester preview Facebook/WhatsApp |
| Twitter Card Validator | https://cards-dev.twitter.com/validator | Tester preview Twitter |
| Google Rich Results | https://search.google.com/test/rich-results | Tester JSON-LD |
| SRI Hash Generator | https://www.srihash.org/ | Générer hash SRI |
| Snyk Advisor | https://snyk.io/advisor/ | Audit vulnérabilités CDN |
| Lighthouse | Chrome DevTools | Performance audit |
| Wappalyzer | Extension Chrome | Voir le stack d'un site |

### 8.3 Standards & lois à connaître

| Document | URL | Pertinence |
|---|---|---|
| RGPD (UE) | https://gdpr.eu/ | Si clients UE |
| Loi 2013-450 (CI) | ARTCI | Loi data CI |
| WCAG 2.1 | https://www.w3.org/WAI/WCAG21/quickref/ | Accessibilité |
| Schema.org | https://schema.org/ | JSON-LD SEO |
| Spawning AI | https://spawning.ai/ | Anti-IA training |

---

## 9. Contacts utiles à garder

À remplir et conserver dans 1Password :

```
SUPABASE
- Dashboard : https://supabase.com/dashboard/project/ftvowlmrsgcaienvhojj
- Email support : support@supabase.com
- Status : https://status.supabase.com/

NETLIFY
- Dashboard : https://app.netlify.com/sites/ecodila
- Email support : support@netlify.com
- Status : https://www.netlifystatus.com/

ANTHROPIC (pour claude-proxy)
- Console : https://console.anthropic.com/
- Status : https://status.anthropic.com/

DOMAIN REGISTRAR (qui possède ecodila.com)
- À documenter

EMAIL PROVIDER
- À documenter (probable : Google Workspace ou similaire)

ARTCI (autorité CI)
- https://www.artci.ci/
- Pour déclaration de traitement données personnelles

ÉQUIPE
- Toi (Mainteneur principal) : [tes coordonnées]
- Devs externes (si missions ponctuelles) : [coordonnées]
- Comptable / juriste : [coordonnées]
```

---

## 10. FAQ — questions fréquentes

### "J'ai changé une chose dans admin.html mais le site ne se met pas à jour"

1. Vérifier que tu as bien push sur GitHub
2. Vérifier sur Netlify que le deploy s'est lancé et a réussi
3. **Forcer le rafraîchissement** : Ctrl+Shift+R (Windows) / Cmd+Shift+R (Mac)
4. **Vider le cache CDN** Netlify : Site → Deploys → "Clear cache and retry deploy"

### "Je ne vois plus mes données dans le BO admin"

1. Vérifier la console (F12) pour erreurs Supabase
2. Si erreur 401 : ta clé `anon` est invalide → vérifier dans Supabase Dashboard → Settings → API
3. Si erreur 500 : Supabase est down → vérifier https://status.supabase.com/
4. Si tableau vide : vérifier que les RLS ne sont pas trop strictes (récemment durcies ?)

### "AUDITAZ IA ne répond plus"

1. Vérifier que `ANTHROPIC_API_KEY` est dans Netlify env vars
2. Vérifier le quota sur https://console.anthropic.com/
3. Tester directement : `curl -X POST https://ecodila.com/.netlify/functions/claude-proxy -H "Content-Type: application/json" -d '{...}'`

### "Un parrain me dit qu'il ne reçoit pas ses commissions"

1. Vérifier `parrain_commissions` pour ce parrain → status
2. Vérifier que les `orders` ont bien `parrain_code` rempli
3. Vérifier `users.parrain_code` du client qui a passé commande
4. Si tracking attribution KO : vérifier `visitors.parrain_code`

### "J'ai une grosse panne en prod, je dois rollback rapidement"

1. **Netlify Dashboard** → Deploys → trouver le dernier OK → "Publish deploy"
2. Le site revient à cet état en 30s
3. Diagnostiquer le problème ensuite à tête reposée

### "Comment je donne accès à mon code à un dev externe ponctuel ?"

1. **NE PAS** lui donner les credentials Netlify
2. **NE PAS** lui donner la `service_role` key Supabase
3. **NE PAS** lui donner les Basic Auth `ADMIN_AUTH_*`
4. **DONNER** : accès au repo GitHub en lecture (collaborator avec Read access)
5. **DONNER** : un environnement Supabase de staging séparé (créer un nouveau projet Supabase pour ce dev)
6. **APRÈS LA MISSION** : retirer son accès, rotation des credentials par précaution

### "Je veux migrer vers un autre stack (React, Vue, etc.)"

C'est un gros chantier. Reco :
1. **Commencer par auditaz.html** (le plus stable, le moins de users)
2. Garder Supabase comme DB (migration progressive sinon, c'est l'enfer)
3. Refacto par module, pas big-bang
4. Garder une période de coexistence (ancien + nouveau en parallèle)
5. Migration finale après 2-3 mois de stabilité

---

## 11. Quand demander de l'aide

| Situation | Qui appeler |
|---|---|
| Bug bloquant en prod | Toi (premier) → puis dev externe si pas résolu en 1h |
| Suspicion d'intrusion | ARTCI (sous 72h) si données compromises |
| Question légale RGPD | Juriste / DPO si tu en as un |
| Question stack technique | Stack Overflow, communauté Supabase Discord, Netlify support |
| Décision business | C'est à toi de trancher |

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
