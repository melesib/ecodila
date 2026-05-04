# 📚 Documentation Technique — EcoDila

> **Version** : v82 (mai 2026)
> **Domaine** : https://ecodila.com
> **Stack** : HTML/CSS/JS vanilla, Netlify (Edge Functions + Functions), Supabase (Postgres + Auth + Storage)
> **Repo** : https://github.com/melesib/ecodila

---

## 🎯 À qui s'adresse cette documentation

- **Toi (mainteneur principal)** : pour retrouver une fonctionnalité, comprendre un module, débuguer
- **Un développeur externe** mandaté pour une mission ponctuelle (à qui tu donnes le zip + cette doc)
- **Une IA** (Claude, GPT, autre) à qui tu donnes le code en local pour l'aider à modifier/étendre
- **Auditeur sécurité / RGPD** qui doit comprendre l'architecture pour challenger les choix

## 🗺️ Comment naviguer

| Document | À lire si tu veux comprendre... |
|---|---|
| [01-architecture-globale.md](docs/01-architecture-globale.md) | La vue d'ensemble : composants, flux, dépendances |
| [02-base-de-donnees-supabase.md](docs/02-base-de-donnees-supabase.md) | Le schéma DB, les ~40 tables, les vues, les politiques RLS |
| [03-site-public-index.md](docs/03-site-public-index.md) | `index.html` — la marketplace publique, le bot LIDA, la négociation |
| [04-bo-admin.md](docs/04-bo-admin.md) | `admin.html` — le back-office équipe (ventes, clients, KPIs) |
| [05-bo-parrain.md](docs/05-bo-parrain.md) | `parrain.html` — l'espace parrain (Djassa : commissions, classement) |
| [06-auditaz.md](docs/06-auditaz.md) | `auditaz.html` — l'outil de sécurité/audit + IA assistant code |
| [07-netlify-edge-functions.md](docs/07-netlify-edge-functions.md) | Les Edge Functions (auth gate, OG dynamique) et Functions (proxy IA, IP) |
| [08-securite-et-risques.md](docs/08-securite-et-risques.md) | **Audit sécurité** : risques connus + recommandations |
| [09-maintenance-et-extension.md](docs/09-maintenance-et-extension.md) | Comment développer/déployer/débuguer/étendre |

---

## ⚡ TL;DR — l'essentiel en 30 secondes

EcoDila est une **marketplace ivoirienne d'appareils électroniques reconditionnés** (smartphones, TV, PC, drones) avec :

- 🛒 **Site public** (`index.html`, 40 573 lignes, 2 Mo) — catalogue + bot conversationnel "LIDA" + moteur de négociation gamifiée + paiement à la livraison
- 🛠️ **BO Admin** (`admin.html`, 59 012 lignes, 3,4 Mo) — gestion produits, clients, commandes, marges, propositions, fournisseurs, page builder
- 🌟 **BO Parrain "Djassa"** (`parrain.html`, 12 800 lignes, 660 Ko) — espace parrains externes avec commissions, classement, challenges, retraits
- 🛡️ **AUDITAZ** (`auditaz.html`, 22 949 lignes, 2,9 Mo) — outil interne de sécurité, audit, et **IA assistant de code patching**

**Architecture** : 4 fichiers HTML monolithiques (CSS + JS inline) + Supabase pour la DB + Netlify pour l'hébergement et les Edge Functions.

**Pas de framework** : pas de React, Vue, Angular. Vanilla JS + DOM API. Routing client-side via `?p=PROD123`, `?page=parrainage`, etc.

**Pas de build step** : déploiement direct des fichiers HTML sur Netlify. Pas de bundling, pas de transpilation.

**Stack publique exposée** : Supabase URL + anon key (publiques par design — la sécurité repose sur RLS).

**Stack privée serveur** : variables d'environnement Netlify (`ADMIN_AUTH_USER/PASS`, `AUDITAZ_AUTH_USER/PASS`).

---

## 📊 Métriques globales

| Métrique | Valeur |
|---|---|
| Lignes de code total | ~135 000 (HTML+CSS+JS+SQL) |
| Fichiers HTML | 4 (monolithiques) |
| Fonctions JavaScript | ~2 400 fonctions classiques + ~880 helpers `window._*` |
| Tables Supabase | ~40 tables identifiées |
| Edge Functions | 3 (`back-office-gate`, `og-product`, `og-image`) |
| Serverless Functions | 2 (`claude-proxy`, `get-ip`) |
| Fichiers SQL de migration | 13 |
| Try/Catch (gestion d'erreur) | 1 704 occurrences (santé : excellente) |
| `innerHTML` (vecteurs XSS potentiels) | 838 occurrences (à auditer) |

---

## 🏗️ Stack technique

```
┌─────────────────────────────────────────────────────────────┐
│  CLIENT — Navigateur (ordinateur, mobile Android/iOS)       │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  HTML5 + CSS3 (custom, pas de framework)             │  │
│  │  JavaScript ES6+ vanilla (pas de transpilation)      │  │
│  │  Web APIs : Crypto.subtle, SpeechRecognition,        │  │
│  │  IntersectionObserver, localStorage, indexedDB       │  │
│  │  Libs CDN : @supabase/supabase-js@2, qrcode.js,      │  │
│  │             xlsx (auditaz), DOMPurify (auditaz)      │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────────┘
                     │ HTTPS
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  CDN Netlify (edge mondial)                                 │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Edge Functions (Deno runtime, latence < 50ms)       │  │
│  │  • back-office-gate.js (auth Basic + UA filter)      │  │
│  │  • og-product.js (preview WhatsApp/FB dynamique)     │  │
│  │  • og-image.js (sert images base64 → binaire HTTP)   │  │
│  └──────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Functions (Node.js Lambda, latence ~200ms)          │  │
│  │  • claude-proxy.js (rate-limited proxy vers          │  │
│  │    api.anthropic.com — utilisé par auditaz IA)       │  │
│  │  • get-ip.js (retourne IP client)                    │  │
│  └──────────────────────────────────────────────────────┘  │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  Supabase (Postgres + Auth + Storage + Realtime)            │
│  Project ID : ftvowlmrsgcaienvhojj                          │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  Tables (~40) : users, products, orders, propositions │  │
│  │  parrains, parrain_commissions, chat_conversations,   │  │
│  │  chat_tickets, offers, offer_logs, nego_abandoned,    │  │
│  │  visitors, settings, notifications, error_logs, etc.  │  │
│  │                                                        │  │
│  │  Row Level Security (RLS) : OBLIGATOIRE sur toutes    │  │
│  │  les tables sensibles                                 │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 🚀 Liens rapides

- **Setup local** : voir [09-maintenance-et-extension.md#setup-local](docs/09-maintenance-et-extension.md#setup-local)
- **Déploiement** : voir [09-maintenance-et-extension.md#deploiement](docs/09-maintenance-et-extension.md#deploiement)
- **Variables d'env. Netlify** : voir [README-SECURITY.md](README-SECURITY.md)
- **Schéma DB** : voir [02-base-de-donnees-supabase.md](docs/02-base-de-donnees-supabase.md)
- **Risques connus** : voir [08-securite-et-risques.md](docs/08-securite-et-risques.md)

---

## 📜 Licence

Code propriétaire — voir [LICENSE.txt](LICENSE.txt). Toute reproduction, scraping ou utilisation pour entraînement IA est strictement interdite sans autorisation écrite.

© 2026 EcoDila. Tous droits réservés.
