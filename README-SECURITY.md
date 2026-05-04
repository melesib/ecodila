# 🔒 EcoDila — Configuration sécurité serveur

## Architecture en couches

```
┌─────────────────────────────────────────────────────────────┐
│  1. robots.txt + ai.txt          (signaling pour bots respectueux) │
│  2. Meta noindex/noai/X-Robots   (signaling moteurs/IA)            │
│  3. Edge Function back-office    (gate serveur AVANT le HTML)  ← NOUVEAU │
│  4. Auth client Supabase         (logique métier, sessions)        │
│  5. Supabase RLS                 (sécurité données niveau row)     │
│  6. LICENSE.txt                  (terrain juridique : DMCA/poursuite) │
└─────────────────────────────────────────────────────────────┘
```

## ⚙️ Configuration OBLIGATOIRE après déploiement

L'Edge Function `back-office-gate.js` protège `/admin.html` et `/auditaz.html`
par HTTP Basic Auth. **Sans variables d'environnement, ces pages renvoient
une page 503 "Configuration requise"** (fail-closed).

### Étapes (5 minutes)

1. Aller sur **Netlify dashboard → ton site EcoDila → Site settings → Environment variables**
2. Cliquer **"Add a variable"** et créer ces 4 variables :

| Variable                | Valeur recommandée                          | Usage                |
|-------------------------|---------------------------------------------|----------------------|
| `ADMIN_AUTH_USER`       | Un login (ex: `melesib_admin`)              | Login de /admin.html |
| `ADMIN_AUTH_PASS`       | Mot de passe fort 16+ caractères aléatoires | Pwd de /admin.html   |
| `AUDITAZ_AUTH_USER`     | Un login (peut être le même)                | Login de /auditaz.html |
| `AUDITAZ_AUTH_PASS`     | Mot de passe fort différent du précédent    | Pwd de /auditaz.html |

3. Pour générer des mots de passe forts :
   ```bash
   openssl rand -base64 24
   # exemple : aBcDeFgHiJkLmNoPqRsTuVwXyZ12==
   ```

4. **Trigger un nouveau deploy** (Deploys → Trigger deploy → Deploy site)
   pour que les variables soient injectées dans l'Edge Function.

5. Vérifier :
   - `https://ecodila.com/admin.html` → demande login navigateur
   - Mauvais login → 401
   - Bon login → admin se charge normalement
   - `https://ecodila.com/parrain.html` → accessible aux navigateurs normaux,
     `curl https://ecodila.com/parrain.html` → 403

## 🧪 Tests manuels

```bash
# Doit retourner 401 (Basic Auth requis)
curl -i https://ecodila.com/admin.html

# Doit retourner 200 avec le HTML
curl -i -u "ADMIN_AUTH_USER:ADMIN_AUTH_PASS" https://ecodila.com/admin.html

# Doit retourner 403 (curl bloqué)
curl -i https://ecodila.com/parrain.html

# Doit retourner 200 (Mozilla autorisé)
curl -i -A "Mozilla/5.0 (X11; Linux x86_64) Chrome/120" https://ecodila.com/parrain.html

# Doit retourner 403 (GPTBot bloqué)
curl -i -A "Mozilla/5.0 (compatible; GPTBot/1.0)" https://ecodila.com/parrain.html
```

## 🚨 Que se passe-t-il si je perds mes credentials ?

Aucun risque permanent. Va dans Netlify → Environment variables, modifie
`ADMIN_AUTH_PASS` et `AUDITAZ_AUTH_PASS`, redéploie. Les anciens credentials
sont invalidés.

## 🔄 Rotation recommandée

Change les mots de passe **tous les 90 jours** ou **immédiatement** si :
- Tu donnes un accès temporaire à un dev externe
- Tu suspectes une fuite
- Un membre de l'équipe quitte le projet

## 📝 Notes

- **Pourquoi pas Supabase auth pour /admin et /auditaz ?** Supabase auth est
  client-side. Un attaquant peut récupérer le HTML brut sans s'authentifier.
  La Basic Auth Edge Function bloque AVANT le HTML soit servi → l'attaquant
  ne voit même pas le code source.

- **Pourquoi seulement filtrage UA pour /parrain ?** Les parrains externes
  doivent pouvoir s'inscrire/se connecter sans credentials partagés. La gate
  bloque uniquement les bots/scrapers identifiables. La sécurité métier
  (qui est parrain, ses données, ses commissions) repose sur Supabase RLS.

- **Et si quelqu'un fake un User-Agent Mozilla pour scraper /parrain ?**
  C'est la limite de cette gate. Pour aller plus loin :
  - Ajouter un challenge captcha (hCaptcha, Turnstile) à la connexion parrain
  - Rate-limiting via Netlify (ou en amont via Cloudflare)
  - Détection comportementale (mouvement souris, frappe clavier)

## 📋 Checklist post-déploiement

- [ ] `ADMIN_AUTH_USER` configuré dans Netlify
- [ ] `ADMIN_AUTH_PASS` configuré (16+ char aléatoires)
- [ ] `AUDITAZ_AUTH_USER` configuré
- [ ] `AUDITAZ_AUTH_PASS` configuré (différent de ADMIN)
- [ ] Site redéployé après config des env vars
- [ ] Test `curl https://ecodila.com/admin.html` → 401 ✓
- [ ] Test login admin avec bons credentials → 200 ✓
- [ ] Test `curl https://ecodila.com/parrain.html` → 403 ✓
- [ ] Test navigation Mozilla `/parrain.html` → 200 ✓
- [ ] Credentials sauvegardés dans un gestionnaire de mots de passe sécurisé
- [ ] Calendrier de rotation des mots de passe (90 jours)

---

© 2026 EcoDila — Tous droits réservés
