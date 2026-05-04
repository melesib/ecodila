# 05 — Back-Office Parrain "Djassa" (`parrain.html`)

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)

---

## 1. Vue d'ensemble

`parrain.html` est l'**espace personnel des parrains externes** (programme de parrainage "Djassa") : 12 800 lignes, 660 Ko, 205 fonctions JS classiques + 114 helpers `window._*`. C'est le plus petit des 3 back-offices.

**Concept Djassa** : un système de parrainage gamifié où chaque parrain :
- Génère un **lien unique** (`?ref=CODE_PARRAIN`)
- Touche **5-10% de commissions** sur chaque vente issue de son lien
- Participe à des **concours** mensuels avec récompenses
- Progresse dans des **niveaux** (Bronze → Silver → Gold → Platinum)
- Affronte les autres parrains dans un **classement** public

**Accès** : `https://ecodila.com/parrain.html` ou `/parrain` ou `/djassa`

**Authentification 2 couches** :
1. **Filtrage User-Agent** par Edge Function (bots IA, scrapers, curl bloqués → 403)
2. **Login parrain custom** (table `parrains`, hash mot de passe via SHA-256)

⚠️ Pas de Basic Auth ici (contrairement à admin/auditaz) car les parrains sont des utilisateurs externes qui doivent pouvoir s'inscrire et se connecter sans credentials partagés.

## 2. Pages disponibles

11 pages identifiées via `showPage(pageId, ...)` :

| Page ID | HTML ID | Icône | Description |
|---|---|---|---|
| `dashboard` | `page-dashboard` | 🏠 | Tableau de bord (KPIs personnels, podium, mon rang) |
| `challenges` | `page-challenges` | 🎯 | Challenges en cours + badges débloqués |
| `performances` | `page-performances` | 📊 | Stats détaillées (clics, ventes, commissions) |
| `filleuls` | `page-filleuls` | 👥 | Liste des filleuls (clients parrainés) |
| `lien` | `page-lien` | 🔗 | Mon lien de parrainage + outils de partage |
| `messages` | `page-messages` | 🛟 | Support — contacter l'équipe EcoDila |
| `deals` | `page-deals` | 💸 | Mes deals spéciaux |
| `leaderboard` | `page-leaderboard` | 🏆 | Classement public des parrains |
| `simulateur` | `page-simulateur` | 🧮 | Simulateur de gains (combien je gagnerais si...) |
| `rgpd` | `page-rgpd` | 🛡️ | Mes données RGPD (droits Art. 15-22) |
| `retraits` | (interne) | 💰 | Demande de retrait des gains (Mobile Money) |

## 3. Modules majeurs

### 3.1 Couches d'infrastructure (communes)

| Module | Lignes | Rôle |
|---|---|---|
| Protection Console & DevTools | L2113 | Anti-copie léger |
| Supabase Init + Cache mémoire | L2141 | Init avec cache asynchrone (perf 2G/3G) |
| Module Performance | L2156 | Détection device + connexion faible |
| Retry Wrapper | L2320 | Retry auto pour connexions instables |
| Helpers Network-Résilience | L2596 | Miroir d'index.html (sync queue) |
| Panneau Diagnostic Sync | L2801 | UI de diagnostic réseau |
| Module Hashing | L6864 | Hash mot de passe (jamais en clair) |

### 3.2 Modules métier spécifiques

| Module | Lignes | Rôle |
|---|---|---|
| **Sync Module** | L3313 | Connexion Supabase EcoDila (lecture parrains, commissions, etc.) |
| **Tracking évolution rang** | L4669 | Détecte les changements de rang dans le classement |
| **Astuces personnalisées** | L4769 | Génère des conseils selon ce qui manque au parrain |
| **Modal "Comment fonctionne le scoring"** | L4860 | Explication transparente du calcul de score |
| **Helper flèche évolution** | L4958 | Affichage flèche ↑/↓ dans le leaderboard |
| **HÉRO PARRAIN** | L5094-5330 | Vue podium 3D chevauchant en haut du BO |
| **CONCOURS PODIUM** | L5331-5875 | Bandeau dynamique du concours en cours |
| **Notifications classement** | L5876-6490 | Notif quand le rang change |
| **Système notifications BO** | L6491-6863 | Notifications internes parrain |
| **Module RGPD** | L7255-7817 | Droits parrains (export, oubli, opposition) |
| **Rectification directe (Art 16)** | L7818-8139 | UI pour modifier ses données |
| **Helper opt-out canaux** | L8140-8338 | Vérifie si un parrain a opt-out d'un canal (WhatsApp/Email/SMS) |
| **MODULE CHALLENGES** | L8339-9588 | Système complet de challenges admin |
| **MODULE SUPPORT** | L9589-9991 | Contacter l'équipe EcoDila |
| **MODAL RÉACTIVATION** | L9992-10816 | Message personnalisé pour filleul inactif |
| **TRACKER D'ACTIVITÉS** | L10817-10980 | Tracking actions parrain (RGPD-aware) |
| **MODULE LIEN PRODUITS** | L10981-11952 | Génération de liens spécifiques par produit |
| **MODULE RETRAIT** | L11953-12257 | Demande de retrait des gains |
| **MODULE DEALS** | L12258-12767 | Deals exclusifs parrain |

## 4. Le système Djassa en détail

### 4.1 Calcul du score parrain

Le score détermine le **classement public** et les **niveaux** (Bronze/Silver/Gold/Platinum).

**Logique principale** (cherchable dans le code via "_classerParrains" ou similaire) :
```
score = (ventes_validées * 100)
      + (challenges_complétés * 50)
      + (filleuls_actifs * 20)
      + (bonus_concours)
      - (pénalités_fraude)
```

⚠️ **À vérifier** : la formule exacte est dans le code à L6146 ("VENTES D'ABORD + PARTICIPATION CHALLENGES").

### 4.2 Classement & Concours

**Classement permanent** : tous les parrains rangés par score → leaderboard public.

**Concours** : compétitions limitées dans le temps (ex: "Concours Septembre"). Le top N gagne des prix monétaires.

- Source de données : `parrain_concours` (participations) + `concours_paiements` (récompenses)
- Vue publique : `v_concours_publics` (concours actifs visibles par tous)
- Configuration : depuis BO admin → module `parrainage_challenges`

### 4.3 Commissions

Quand un client passe une commande **après avoir cliqué sur un lien parrain** :
1. `users.parrain_code = CODE_PARRAIN` (attribué via cookie/session)
2. À la commande validée → INSERT dans `parrain_commissions`
3. Statut commission : `en_attente` → `validee` → `payee`

**Calcul** :
- 5% par défaut (Bronze)
- 7% (Silver) après N filleuls
- 10% (Gold) après ventes cumulées > seuil
- 12% (Platinum) — top tier

### 4.4 Paiements (retraits)

Le parrain demande un retrait via le **Module Retrait** (L11953).

**Flux** :
1. Parrain saisit montant + numéro Mobile Money (Orange/MTN/Moov)
2. Création row dans `parrain_paiements` (statut `demande`)
3. Notification BO admin (module `parrainage_paiements`)
4. Trésorier valide → fait le virement Mobile Money manuellement
5. MAJ statut → `effectue`

⚠️ **Risque fraude** : un parrain pourrait essayer de demander un retrait > son solde. À vérifier côté serveur (PostgreSQL trigger ou check côté admin).

## 5. Vue HÉRO PARRAIN (UI distinctive)

Conception unique du BO : un **podium 3D chevauchant** en haut de la page Dashboard.

**Affiche** :
- Top 3 parrains du concours en cours (avec avatars)
- Flèches d'évolution (↑↓ vs hier)
- Rang du parrain connecté
- Distance au top 3 (ex: "+12 ventes pour atteindre le 3e")

**Animation** : l'avatar du parrain connecté est mis en avant avec un effet de glow.

CSS : L447 (`/* 🆕 ═══ HÉRO PARRAIN — Podium 3D chevauchant ═══ */`)

## 6. Le système de challenges

Module sophistiqué (L8339-9588).

**Concept** : l'admin crée des challenges pour stimuler les parrains :
- "Faire 5 ventes ce mois → bonus 5 000 FCFA"
- "Recruter 3 nouveaux filleuls → badge Recruteur"
- "Atteindre 50 000 FCFA de commissions → upgrade niveau"

**Affichage côté parrain** :
- Page Challenges : liste actifs + complétés + badges
- Notification quand un challenge est complété
- Animation de célébration

**Source données** : table `challenges` (configuration côté admin) + `parrain_concours` (participation).

## 7. Module RGPD parrain

Page dédiée `page-rgpd` (L1801) implémentant les droits RGPD pour les parrains.

| Droit | Action UI |
|---|---|
| Art. 15 — Accès | Bouton "Exporter mes données" → JSON download |
| Art. 16 — Rectification | Module Rectification Directe (L7818) — édition profil |
| Art. 17 — Oubli | Bouton "Supprimer mon compte" (avec confirmation) |
| Art. 20 — Portabilité | Export JSON structuré |
| Art. 21 — Opposition | Toggles canaux (WhatsApp/Email/SMS opt-out) |

**Stockage des préférences** : `parrains.rgpd_prefs` (JSONB) + `parrains.notif_prefs` (JSONB).

**Helper utile** :
```javascript
// L8140
window._parrainHasOptOut(parrainId, canal)
  // → true si le parrain a opt-out de ce canal (whatsapp/email/sms)
  // À utiliser avant CHAQUE envoi de notification
```

⚠️ Toujours vérifier opt-out avant d'envoyer une comm — sanctions RGPD lourdes en cas de non-respect.

## 8. Sync module — connexion Supabase

Le BO parrain ne fait que des requêtes en LECTURE sur les tables `parrains`, `parrain_commissions`, `parrain_concours`, `parrain_statuts`, `challenges`. Avec parfois des UPDATE sur `parrains` (profil, prefs RGPD).

**Pattern type** :
```javascript
async function _loadMyData() {
  var phone = window._currentParrain.telephone;
  
  // Lecture parallèle pour perf
  var [parrainRes, commissionsRes, challengesRes] = await Promise.all([
    _sb.from('parrains').select('*').eq('telephone', phone).maybeSingle(),
    _sb.from('parrain_commissions').select('*').eq('parrain_code', code),
    _sb.from('challenges').select('*').eq('actif', true)
  ]);
  
  // ... merge et affichage
}
```

## 9. Pièges connus

| Piège | Symptôme | Cause | Fix |
|---|---|---|---|
| **Polling agressif sur 2G** | Latence UI atroce | Polling toutes les 5s | Adapter selon connexion (10s+ sur 2G) |
| **Cache obsolète au login** | Anciennes données affichées | Cache mémoire pas vidé | `window._cacheParrain.clear()` au logout |
| **Solde négatif après retrait** | Parrain peut demander > solde | Pas de check serveur | Ajouter trigger SQL `parrain_paiements` |
| **Score = 0 toujours** | Mauvaise formule | Bug dans `_classerParrains` | Vérifier L6146 |
| **Notification doublonnée** | Reçoit 2x la même notif | Polling + Realtime simultanés | Utiliser un seul mécanisme |
| **Lien parrain casse au partage** | URL coupée par WhatsApp | Caractères spéciaux | Toujours `encodeURIComponent` |

## 10. Comment ajouter un nouveau challenge

**Côté admin** (admin.html → `parrainage_challenges`) :
1. Créer un row dans `challenges` avec :
   ```json
   {
     "type": "ventes",
     "objectif": 5,
     "recompense": "5000 FCFA",
     "date_debut": "2026-05-01",
     "date_fin": "2026-05-31",
     "description": "Faire 5 ventes en mai"
   }
   ```

2. Créer la **logique de check** dans le code parrain (L8339+) :
   ```javascript
   function _checkChallenge_ventes_5(parrain) {
     var nbVentes = parrain.ventes_mois_courant || 0;
     return nbVentes >= 5 ? 'completed' : 'in_progress';
   }
   ```

3. Tester :
   - Forcer un parrain à 5 ventes en DB
   - Recharger sa page → challenge doit apparaître complété

## 11. Comment ajouter une nouvelle page

```javascript
// 1. Ajouter le HTML
<div class="page" id="page-mon_module">
  <h2>Mon module</h2>
  <div id="mon-module-content"></div>
</div>

// 2. Ajouter dans la nav (chercher class="nav-item")
<div class="nav-item" onclick="showPage('mon_module',this,'bn-mon_module')">
  <span class="nav-icon">🎯</span>Mon module
</div>

// 3. Créer la fonction de rendu
async function _loadMonModule() {
  // ... logique
  document.getElementById('mon-module-content').innerHTML = '...';
}

// 4. Câbler dans showPage
function showPage(pageId, navEl, btnId) {
  // ...
  if (pageId === 'mon_module') _loadMonModule();
}
```

## 12. Tests à faire avant déploiement

- [ ] Login parrain (téléphone + password) — table `parrains` accessible
- [ ] Filtrage UA Edge Function : `curl /parrain.html` → 403, Mozilla → 200
- [ ] Dashboard charge mon rang + podium
- [ ] Page Challenges : challenges actifs affichés
- [ ] Page Filleuls : liste affichée
- [ ] Page Lien : copie de mon lien fonctionne, QR code généré
- [ ] Page Performance : graphiques OK
- [ ] Demande de retrait fonctionne (notification BO)
- [ ] RGPD : export, suppression, rectification fonctionnent
- [ ] Notifications classement reçues quand rang change
- [ ] Mobile responsive OK (Galaxy Fold testé !)

---

[← Retour à l'index](../DOCUMENTATION-TECHNIQUE.md)
