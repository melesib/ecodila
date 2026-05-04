# 08 — Sécurité & Risques

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## ⚠️ Avant-propos

Ce document est un **audit de sécurité honnête**, sans complaisance. Il identifie les risques connus, classifie leur sévérité, et propose des mitigations.

Tous les risques sont classés selon une matrice **Probabilité × Impact** :

| Sévérité | Action recommandée |
|---|---|
| 🔴 **CRITIQUE** | À fixer dans la semaine |
| 🟠 **ÉLEVÉ** | À fixer dans le mois |
| 🟡 **MODÉRÉ** | À fixer dans le trimestre |
| 🟢 **FAIBLE** | Monitorer, fixer si l'occasion |
| ⚪ **INFO** | Pas un problème, mais à connaître |

---

## 1. État actuel des protections

### 1.1 ✅ Ce qui est BIEN protégé

| Couche | Protection | Niveau |
|---|---|---|
| **Réseau** | HTTPS forcé, HSTS preload, TLS 1.3 | Excellent |
| **CDN** | CSP stricte, X-Frame-Options, X-Content-Type-Options | Bon |
| **BO Admin/AUDITAZ** | Basic Auth Edge Function (env vars) — première barrière | Bon |
| **BO Parrain** | Filtrage UA bots — bloque scrapers automatiques | Bon |
| **Mots de passe** | Hashés (SHA-256 / PBKDF2 + AES-GCM + HMAC), jamais en clair | Bon |
| **Anti-IA** | robots.txt + ai.txt + meta tags + headers | Bon |
| **Anti-scraping** | UA filtering + signaling copyright | Bon |
| **RGPD/ARTCI** | Banner consentement + droits implémentés + audit log | Bon |
| **Rate limiting** | claude-proxy (10 req/min/IP) | Correct (single instance) |
| **Crypto** | Web Crypto API native (pas de lib JS douteuse) | Excellent |
| **Backups Supabase** | Auto via plan Supabase | À VÉRIFIER selon plan |
| **Erreurs réseau** | 1 704 try/catch — gestion d'erreurs très complète | Excellent |

### 1.2 ⚠️ Ce qui présente des risques

Voir détails ci-dessous.

---

## 2. Risques par sévérité

## 🔴 CRITIQUE

### 2.1 Mot de passe bootstrap "admin123" en dur

**Localisation** : `admin.html` ligne 13659
```javascript
if (password !== 'admin123') { alert('❌ Identifiants incorrects'); return; }
```

**Contexte** : ce code n'exécute que lors du **premier accès** quand `storedHash` est `null` (compte super_admin pas encore configuré). Une fois le mot de passe initial saisi, le système le hashe via `EcoSec.hash()` puis le stocke. Les connexions suivantes utilisent le hash.

**Risque actuel** : 
- ✅ **Probablement déjà mitigé en pratique** : si tu as déjà connecté ton compte super_admin une fois, `storedHash` n'est plus null → le code `'admin123'` n'est plus atteignable
- ✅ **Mitigé par la couche v82** : la Basic Auth Edge Function bloque l'accès à `/admin.html` avant même d'atteindre ce code → un attaquant doit déjà connaître `ADMIN_AUTH_USER/PASS`

**Risque résiduel** :
- ⚠️ Si un dev externe a accès au repo (via mission ponctuelle) et passe la Basic Auth, il pourrait théoriquement exploiter le code en réinitialisant `storedHash` (via console).
- ⚠️ Si tu déploies un nouveau site EcoDila avec un nouveau compte admin et que tu oublies le premier accès → `admin123` est valable.

**Mitigation** :
1. **Vérifier que tu as déjà fait le premier accès super_admin** (si non : connecte-toi avec `admin123` puis change immédiatement)
2. **Idéalement** : remplacer `admin123` par une variable d'environnement injectée au build OU rendre obligatoire un setup wizard à l'inscription
3. **Court terme** : changer `admin123` pour quelque chose d'imprévisible (ex: `BootstrapEcoDila_2026!`)

```javascript
// Exemple de fix
var BOOTSTRAP_PASSWORD = 'À_REMPLACER_PAR_QUELQUE_CHOSE_DE_LONG_ET_IMPRÉVISIBLE';
if (!storedHash) {
  if (password !== BOOTSTRAP_PASSWORD) { alert('❌ Identifiants incorrects'); return; }
  // ...
}
```

### 2.2 Politiques RLS Supabase trop permissives

**Localisation** : `chat_conversations.sql`
```sql
CREATE POLICY chat_select_all ON public.chat_conversations
  FOR SELECT USING (TRUE);
```

**Risque** : avec la clé `anon` (publique), un attaquant peut faire :
```javascript
// Depuis n'importe quel navigateur, sans login
var sb = supabase.createClient('https://ftvowlmrsgcaienvhojj.supabase.co', 'eyJ...anon...');
var { data } = await sb.from('chat_conversations').select('*');
// → reçoit TOUS les messages de TOUS les clients
```

**Données exposées potentiellement** :
- `chat_conversations` : tous les messages support (PII : noms, téléphones, emails)
- `users` : si la policy est aussi `USING (TRUE)` → toutes les données clients
- `parrains` : idem
- `orders` : tous les détails de commandes
- Etc.

**Action immédiate** :
1. **Audit complet RLS** dans Supabase Dashboard → Database → Policies
2. Lister chaque table et vérifier les policies
3. Pour chaque table, durcir :

```sql
-- Exemple chat_conversations
DROP POLICY IF EXISTS chat_select_all ON public.chat_conversations;

-- Pour users authentifiés Supabase Auth
CREATE POLICY chat_select_own ON public.chat_conversations
  FOR SELECT USING (
    client_id = auth.uid()::text
  );

-- OU si auth custom (téléphone), passer le client_id en setting :
CREATE POLICY chat_select_own_custom ON public.chat_conversations
  FOR SELECT USING (
    client_id = current_setting('app.current_client_id', TRUE)
  );
```

⚠️ **ATTENTION** : tester en staging avant de durcir, car ton code actuel suppose un mode permissif.

**Tables à auditer EN PRIORITÉ** :
- `chat_conversations` (PII clients)
- `chat_tickets`
- `users` (PII complets)
- `parrains` (PII + finances)
- `parrain_commissions` (montants financiers)
- `parrain_paiements` (Mobile Money)
- `orders` (PII + montants)
- `propositions`
- `error_logs` (peut contenir des données app)

### 2.3 Pas de monitoring / alerting prod

**Risque** : un bug crash / une attaque en cours / une fraude active → **tu ne le sauras pas** tant que quelqu'un ne te le signale pas.

**Évidence** : pas de Sentry, pas de Datadog, pas d'alerting Slack visible dans le code.

**Mitigation** :
1. **Sentry browser SDK** (gratuit jusqu'à 5k événements/mois) :
   ```html
   <script src="https://browser.sentry-cdn.com/7.x.x/bundle.min.js" crossorigin="anonymous"></script>
   <script>Sentry.init({ dsn: 'TON_DSN' });</script>
   ```
2. **Netlify webhook** sur deploy fail → envoie sur Slack
3. **Supabase webhooks** sur insertion `error_logs` → email/SMS

---

## 🟠 ÉLEVÉ

### 2.4 838 occurrences de `innerHTML` (~77 avec concaténation)

**Localisation** : tous les fichiers HTML

**Stats détaillées** :
| Fichier | Total `innerHTML` | Avec concaténation (à auditer) |
|---|---|---|
| `index.html` | 195 | ~18 |
| `admin.html` | 397 | ~30 |
| `parrain.html` | 73 | ~7 |
| `auditaz.html` | 173 | ~22 |

**Risque** : si une donnée vient d'une source non maîtrisée (input client, message chat, nom produit, etc.) et est injectée via `innerHTML` sans échappement → **XSS**.

**Bonne pratique déjà en place** : `_esc()` dans admin.html (L11321) — mais il faut l'utiliser PARTOUT.

**Action** :
1. **Audit ligne par ligne** des ~77 occurrences avec concaténation
2. Pour chaque, vérifier la source de la donnée
3. Si donnée externe → wrapper avec `_esc()` ou utiliser `DOMPurify.sanitize()`
4. Idéalement : migrer vers `textContent` quand possible (pas de HTML)

**Exemple type** :
```javascript
// ❌ DANGEREUX
el.innerHTML = '<div>' + client.nom + '</div>';

// ✅ SAFE
el.innerHTML = '<div>' + _esc(client.nom) + '</div>';

// ✅ ENCORE PLUS SAFE (pas de HTML)
el.textContent = client.nom;

// ✅ POUR HTML COMPLEXE
el.innerHTML = DOMPurify.sanitize('<div>' + client.nom + '</div>');
```

### 2.5 Clé Supabase `anon` publiquement exposée (avec RLS faible)

**Localisation** : 4 HTML, hardcodée

**Contexte** : la clé `anon` Supabase **EST conçue pour être publique**. C'est OK **SI ET SEULEMENT SI** les RLS sont strictes.

Vu que les RLS sont faibles (cf. 2.2), cette exposition devient un vecteur d'attaque.

**Mitigation** : durcir les RLS (cf. 2.2). C'est en réalité la **même action** que 2.2.

⚠️ **Confirmation** : la clé `service_role` (admin) **n'est PAS exposée** côté client (vérifié par grep). C'est CRITIQUE qu'elle ne le soit jamais.

### 2.6 Rate-limiting `claude-proxy` non distribué

**Localisation** : `netlify/functions/claude-proxy.js`
```javascript
var _rateStore = {};  // in-memory
```

**Risque** : Netlify peut spawn plusieurs instances Lambda en parallèle. Le compteur n'est pas partagé → un attaquant pourrait envoyer 10 req sur instance A, 10 sur instance B = 20 req/min effectivement.

**Mitigation** :
- **Court terme** : c'est OK pour un usage interne (AUDITAZ utilisé par 1-2 personnes max)
- **Long terme** : migrer vers une rate-limit DB-backed :
  ```javascript
  var { data, error } = await sb.from('rate_limits').upsert({
    ip: clientIp,
    bucket: Math.floor(Date.now() / 60000),
    count: 1
  }, { onConflict: 'ip,bucket' });
  ```

### 2.7 Migrations SQL non versionnées en CI

**Risque** : tu fais une nouvelle migration `add_xxx.sql`, tu la commits, mais tu **oublies de l'exécuter** dans Supabase SQL Editor → la prod n'a pas la nouvelle colonne → bugs.

**Évidence** : 13 migrations SQL dans le repo, mais pas de mécanisme automatisé pour confirmer leur application en prod.

**Mitigation** :
1. **Court terme** : tenir une checklist `MIGRATIONS-APPLIED.md` dans le repo, à mettre à jour manuellement
2. **Mieux** : utiliser **Supabase CLI** pour gérer les migrations :
   ```bash
   npm install -g supabase
   supabase login
   supabase link --project-ref ftvowlmrsgcaienvhojj
   supabase db push
   ```
3. **Idéal** : intégrer en CI (GitHub Actions) — auto-exécute les migrations à chaque push

### 2.8 Images stockées en base64 dans `products`

**Localisation** : table `products.image_principale TEXT`

**Risques** :
1. **Performance** : une row de 5 Mo (image base64) ralentit toutes les requêtes SELECT
2. **Coût** : ~33% de surcoût stockage (base64 vs binaire)
3. **Limite Postgres** : 1Go par row max, mais en pratique problèmes >10 Mo
4. **Backup lent** : `pg_dump` du `products` sera énorme

**Mitigation** :
1. **Migrer vers Supabase Storage** (gratuit jusqu'à 1Go) :
   ```javascript
   // Upload
   var { data } = await sb.storage.from('products').upload('PROD123.jpg', blob);
   // URL publique
   var url = sb.storage.from('products').getPublicUrl('PROD123.jpg').data.publicUrl;
   ```
2. **Réduire `image_principale` à un URL** au lieu du base64
3. **Migration progressive** : nouveaux produits → Storage, anciens → migrés en batch

---

## 🟡 MODÉRÉ

### 2.9 178 occurrences de `alert()` natif

**Localisation** : 13 (index) + 112 (admin) + 3 (parrain) + 50 (auditaz) = 178 total

**Problèmes** :
- UX dégradée sur mobile (alert bloque la page)
- Pas de styling cohérent
- Pas accessible (screen readers)
- Bloque parfois la JS execution

**Mitigation** :
- Remplacer progressivement par un modal custom uniformisé (`showToast()` existe déjà, bon candidat à étendre en `showModal()`)
- Priorité aux flux critiques : login admin (10+ alert dans le flow), erreurs paiement, etc.

### 2.10 ~796 `console.log/warn/error` oubliés

**Localisation** : 348 (index) + 397 (admin) + 81 (parrain) + 51 (auditaz) = **877** total

**Problèmes** :
- Fuite d'info technique (structure DB, IDs internes, etc.)
- Bruit en console (un dev externe ne peut pas distinguer ses logs des nôtres)
- Possibilité de fuiter des PII si un objet user est `console.log`-é

**Mitigation** :
- **Court terme** : laisser tel quel (utile pour debug, et la console est déjà désactivée par "PROTECTION CONSOLE & DEVTOOLS")
- **Long terme** : wrapper `_log()` qui n'execute qu'en mode dev :
  ```javascript
  var _DEV = window.location.hostname === 'localhost';
  function _log() { if (_DEV) console.log.apply(console, arguments); }
  // Remplacer console.log → _log
  ```

### 2.11 Pas de CAPTCHA sur login / inscription

**Risque** : brute force du login, création massive de faux comptes, bots qui spamment l'inscription parrain.

**Évidence** : aucun CAPTCHA visible dans le code (Cloudflare Turnstile, hCaptcha, reCAPTCHA, etc.).

**Mitigation actuelle** :
- Edge Function `back-office-gate` → bloque l'accès à `/admin` et `/auditaz` (donc brute force impossible)
- Pour `/parrain` : pas de protection brute force native

**Mitigation recommandée** :
- Ajouter **rate-limiting des logins** (max 5 essais / 15 min / IP) côté serveur (Edge Function ou Supabase function)
- Ajouter **Cloudflare Turnstile** (gratuit, sans tracking) sur les pages login + inscription parrain

### 2.12 Mots de passe stockés en SHA-256 (site public)

**Localisation** : `users.password_hash` via `EcoSec.hash(pwd)` (SHA-256 simple)

**Risque** : SHA-256 nu est **rapide à brute-forcer** sur GPU (milliards de hashes/sec). Si la DB est leakée, tous les mots de passe faibles tombent.

**Bonne pratique manquante** : devrait utiliser **PBKDF2 / Argon2 / bcrypt** avec salt aléatoire par utilisateur.

**Note positive** : le BO admin utilise **PBKDF2 + AES-GCM + HMAC** (EcoSec v2) — plus robuste.

**Mitigation** :
- **Migrer le site public vers PBKDF2** :
  ```javascript
  // Au prochain login d'un utilisateur, re-hasher en PBKDF2 et mettre à jour
  if (user.password_hash_version === 'sha256') {
    var newHash = await EcoSec.pbkdf2(password, generateSalt());
    await sb.from('users').update({ password_hash: newHash, password_hash_version: 'pbkdf2' }).eq('id', user.id);
  }
  ```

### 2.13 Pas de versioning Postgres / pas de point-in-time recovery

**Risque** : si tu corromps une table par erreur (DELETE sans WHERE, UPDATE qui passe partout), pas moyen de revenir 2h avant.

**État** : Supabase plan gratuit = backup quotidien, conservation 7 jours, **pas de PITR**. Plan Pro+ = PITR.

**Mitigation** :
1. **Avant chaque opération risquée** : `SELECT pg_dump-equivalent` manuel
2. **Plan Pro Supabase** ($25/mois) : PITR sur 7 jours
3. **Backups manuels hebdomadaires** :
   ```bash
   # Depuis ton ordi (Linux/Mac)
   pg_dump "postgres://postgres:[PWD]@db.ftvowlmrsgcaienvhojj.supabase.co:5432/postgres" \
     --schema=public --no-owner > backup-$(date +%Y%m%d).sql
   ```

---

## 🟢 FAIBLE

### 2.14 Pas de Subresource Integrity (SRI) sur les CDN

**Localisation** : tous les `<script src="https://cdn...">`

**Risque** : si un CDN est compromis (jsdelivr, cdnjs), un attaquant pourrait y injecter du code malicieux servi à tous tes users. SRI permet de vérifier l'intégrité du fichier.

**État** : aucun `integrity="sha384-..."` détecté.

**Mitigation** :
```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"
        integrity="sha384-XXXX"
        crossorigin="anonymous"></script>
```

Générer le hash SRI : https://www.srihash.org/

### 2.15 `document.write()` dans des popups (3 occurrences index.html)

**Localisation** : `index.html` L13395, L13419, L13457

**Contexte** : utilisé pour générer des popups "Reçu" (commande, troc, proposition). Le contenu est **complètement contrôlé** côté serveur (pas de données externes injectées). 

**Verdict** : **pas un risque** dans le contexte actuel, mais `document.write()` est déprécié → à moderniser un jour.

**Mitigation** :
```javascript
// Au lieu de
w.document.write('<html>...');

// Préférer
w.document.body.innerHTML = '<div>...</div>';
// ou
w.document.write = null;
w.document.body.appendChild(myElement);
```

### 2.16 Pas de SBOM / pas d'audit dépendances CDN

**Risque** : si une dépendance CDN ajoute une vulnérabilité, tu ne le sais pas.

**Dépendances actuelles** :
- `@supabase/supabase-js@2` (toujours dernière v2.x)
- `qrcodejs@1.0.0`
- `xlsx@0.18.5`
- `dompurify@3.1.6`

**Mitigation** :
1. Pin des versions précises (déjà fait sauf Supabase qui est `@2`)
2. Audit manuel mensuel : https://snyk.io/advisor/
3. Revoir chaque mise à jour avant deploy

### 2.17 Pas de policy for unsafe code in CSP

**Localisation** : `_headers` CSP : `script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net ...`

**Risque** : `unsafe-inline` + `unsafe-eval` = la CSP ne protège plus du XSS. Mais comme on a beaucoup de JS inline (dans les HTML monolithiques), on ne peut pas le retirer.

**État** : nécessaire pour le fonctionnement actuel.

**Mitigation long terme** :
- Externaliser le JS inline (mais ça casse le pattern monolithique 1-fichier)
- Utiliser `nonce` sur chaque `<script>` au lieu de `unsafe-inline`

---

## ⚪ INFO

### 2.18 `eval()` détectés (2 occurrences) — FAUX POSITIFS

**Localisation** : `auditaz.html` L17569, L18075

**Contexte** : ce sont des **regex** qui CHERCHENT `eval(` dans le code des patches AUDITAZ pour les rejeter. **C'est une protection, pas un usage**.

```javascript
if ((ext === 'js' || ext === 'jsx') && /eval\s*\(/.test(patch.code)) {
  errors.push('Utilisation de eval() — risque XSS');
}
```

**Verdict** : ✅ aucun risque, c'est une feature de sécurité.

### 2.19 `unsafe` 4 occurrences dans auditaz

**Localisation** : `auditaz.html`

**Contexte** : à vérifier au cas par cas. Probablement des noms de variables descriptifs (ex: `unsafePatch`, `unsafeMode`) — pas de l'unsafe code à proprement parler.

**Action** : grep manuel quand tu as un moment :
```bash
grep -n "unsafe" auditaz.html
```

### 2.20 Anti-IA n'est pas étanche

**Localisation** : `robots.txt`, `_headers`, meta tags

**Contexte** : tu as déjà une protection 4 niveaux (robots, ai.txt, headers, meta). **MAIS** :
- Les bots IA respectueux (GPTBot, ClaudeBot, etc.) → respectent ces règles ✓
- Les bots IA voyous (qui ignorent robots.txt) → continuent de scraper
- Les humains qui copient → impossibles à bloquer techniquement

**Verdict** : tu as fait le maximum techniquement. La protection juridique (LICENSE.txt + dossier d'audit Netlify) est ton vrai recours.

---

## 3. Synthèse / Plan d'action recommandé

### 3.1 Priorité 1 (cette semaine)

- [ ] **Vérifier que ton compte super_admin a déjà été initialisé** (sinon : connecter via `admin123` puis changer)
- [ ] **Auditer les RLS Supabase** : aller dans le dashboard, lister chaque policy, s'assurer qu'aucune table sensible n'a `USING (TRUE)` non justifié
- [ ] **Backup manuel complet de la DB** (avant tout durcissement)
- [ ] **Confirmer que `service_role` key n'est PAS dans le code committé** (déjà vérifié : OK)

### 3.2 Priorité 2 (ce mois)

- [ ] **Sentry browser SDK** — pour voir les erreurs prod
- [ ] **Migrer le bootstrap admin password** vers une env var injectée
- [ ] **Audit innerHTML avec concaténation** (~77 occurrences) — wrapper `_esc()` partout
- [ ] **Plan Supabase Pro** — pour PITR (recommandé pour business critique)
- [ ] **Versioning des migrations SQL** (Supabase CLI ou checklist manuelle)

### 3.3 Priorité 3 (ce trimestre)

- [ ] **Migrer images produits vers Supabase Storage**
- [ ] **PBKDF2 pour mots de passe `users`** (migration progressive au login)
- [ ] **Remplacer `alert()` natifs** par modals custom
- [ ] **Cloudflare Turnstile** sur login/inscription parrain

### 3.4 Priorité 4 (à terme)

- [ ] **SRI sur CDN scripts**
- [ ] **CSP sans unsafe-inline** (gros chantier, refacto JS externalisé)
- [ ] **Tests automatisés** (Vitest, Playwright)
- [ ] **Migration TypeScript** (avec esbuild léger, pas de framework)
- [ ] **Monitoring runtime** (Sentry → Datadog si croissance)

## 4. Procédures en cas d'incident

### 4.1 Si tu détectes une intrusion

1. **Isoler** : changer toutes les env vars Netlify (rotation immédiate)
2. **Tracer** : exporter les logs Netlify + Supabase auth logs
3. **Notifier** : ARTCI (Côte d'Ivoire) sous 72h si données personnelles compromises (loi 2013-450 art. 22 — assimilable RGPD art. 33)
4. **Communiquer** : aux users concernés si fuite de données (loi CI + art. 34 RGPD)
5. **Documenter** : `error_logs` + `rgpd_audit_log` + email perso

### 4.2 Si tu suspectes un compte admin compromis

1. **Verrouiller** : `UPDATE admins SET disabled = TRUE WHERE id = X`
2. **Forcer reset** : reset password + suppression token rememberMe
3. **Auditer** : `auditaz_activity` pour les actions effectuées par ce compte
4. **Reverter** : annuler les actions suspectes (commandes créées, prix modifiés, etc.)

### 4.3 Si tu suspectes une fraude parrain

1. **Bloquer** : `INSERT INTO auditaz_blocked_users (user_id, raison, ...)`
2. **Geler les paiements** : `UPDATE parrain_paiements SET statut = 'gele' WHERE parrain_id = X`
3. **Auditer** : module AUDITAZ → `parrainage_fraude`
4. **Décider** : remboursement / ban définitif / poursuite légale

### 4.4 Si DB Supabase corrompue

1. **NE PAS PANIQUER**
2. **Stop write** : désactiver temporairement le site (Netlify → désactiver le site)
3. **Restaurer** : Supabase Dashboard → Database → Backups → Restore (24-48h en arrière)
4. **Comparer** : ce qui a été perdu (commandes, etc.)
5. **Notifier** : si commandes perdues, contacter manuellement les clients

## 5. Recommandations de sécurité opérationnelle

### 5.1 Mots de passe (à toi le mainteneur)

- **Gestionnaire** : 1Password, Bitwarden, ou KeePass
- **Mots de passe uniques** : ADMIN_AUTH_PASS ≠ AUDITAZ_AUTH_PASS ≠ Supabase ≠ Netlify ≠ GitHub
- **Longueur min** : 16 caractères, mix lettres/chiffres/symboles
- **Rotation** : tous les 90 jours pour les env vars Netlify (mettre un rappel calendrier)

### 5.2 2FA partout

- ✅ GitHub : 2FA activé (recommandé)
- ✅ Netlify : 2FA activé
- ✅ Supabase : 2FA activé
- ✅ Email principal : 2FA activé

### 5.3 Backups

- **Hebdomadaire** : `pg_dump` complet → stockage offline (Google Drive perso, disque externe)
- **Mensuel** : test de restauration sur un projet Supabase de staging

### 5.4 Logs à consulter régulièrement

- **Netlify → Functions logs** : 1x/semaine, chercher erreurs 5xx
- **Supabase → Logs → API Edge Logs** : 1x/semaine, chercher patterns suspects (mêmes IP, requêtes anormales)
- **`error_logs` (DB)** : 1x/semaine via BO admin
- **`auditaz_activity` (DB)** : 1x/mois via AUDITAZ

### 5.5 Compliance ARTCI (Côte d'Ivoire)

- **Déclaration ARTCI** : si pas encore fait, déclarer le traitement de données
- **DPO** : pas obligatoire à ta taille mais recommandé (peut être toi)
- **Registre des traitements** : maintenir à jour
- **Politique RGPD/ARTCI** : page publique sur le site (`/legal` ou similaire)

---

## 6. Résumé exécutif

**État global de la sécurité d'EcoDila** : 🟡 **Correct, avec quelques points à durcir**

**Forces** :
- Architecture défense en profondeur (Edge Function + RLS + auth custom)
- Crypto solide (Web Crypto API native)
- RGPD bien implémenté
- Anti-IA / anti-scraping multi-niveaux
- Try/catch quasi systématique

**Faiblesses principales** :
- RLS Supabase à durcir (priorité absolue)
- Pas de monitoring runtime (priorité forte)
- Bootstrap password en dur (mineur si compte déjà initialisé)

**Verdict** : la base est saine, mais il y a du travail pour passer de "bon pour une PME" à "audit-ready pour grand compte / scale-up".

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
