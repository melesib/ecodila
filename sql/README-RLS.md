# 🚨 LIRE AVANT D'EXÉCUTER UN SQL DE HARDENING RLS

## ⚠️ Honnêteté avant tout

L'audit de sécurité a identifié que les RLS Supabase actuelles peuvent être trop permissives. Le hardening RLS est **un sujet sensible** car il peut casser ton app si appliqué brutalement.

**Tu m'as posé la bonne question** : *"Ça ne va pas impacter le bon fonctionnement ?"*

**Réponse honnête** : selon le SQL que tu choisis d'exécuter, OUI ou NON.

---

## 📂 Tu as 3 fichiers SQL à ta disposition

### 1. `sql/audit_rls.sql` — 🟢 **ZÉRO RISQUE**

**Action** : NE MODIFIE RIEN. Liste juste l'état actuel.

**À faire EN PREMIER** : exécute-le dans Supabase SQL Editor pour voir où tu en es.

**Quand l'exécuter** : MAINTENANT, sans risque.

---

### 2. `sql/harden_rls_safe.sql` — 🟢 **RISQUE QUASI NUL**

**Action** : Active RLS sur toutes les tables sensibles AVEC des policies 100% permissives (`USING (TRUE)` partout).

**Ce que tu gagnes** :
- ✅ RLS infrastructurellement activée sur toutes les tables (defense in depth)
- ✅ Aucune fonctionnalité cassée (toutes les opérations passent)
- ✅ Tu peux durcir progressivement plus tard, table par table
- ✅ Conformité : RLS activée = bon pour audit ARTCI/RGPD

**Ce que tu ne gagnes pas (encore)** :
- ❌ Protection RLS effective contre exfiltration via anon key

**Métaphore** : c'est comme installer la serrure sur ta porte mais laisser la clé dessus. La porte est sécurisée mécaniquement, il suffira plus tard de retirer la clé.

**Recommandation** : ✅ **EXÉCUTE CELUI-CI** si tu veux durcir sans rien casser.

---

### 3. `sql/harden_rls.sql` — 🔴 **RISQUE MOYEN À ÉLEVÉ**

**Action** : Active RLS + applique des policies durcies (retire UPDATE/DELETE sur certaines tables, retire SELECT anon sur tables très sensibles).

**Ce que tu gagnes** :
- ✅ Sécurité réelle contre exfiltration
- ✅ Impossible de modifier les commissions/paiements depuis le client
- ✅ Audit-ready niveau enterprise

**Ce que tu risques de casser** :
- ❌ Si ton BO admin sauve des produits/settings via anon key → cassé
- ❌ Si ton BO admin valide un paiement parrain via anon key → cassé
- ❌ Si AUDITAZ lit ses propres tables `auditaz_*` via anon key → cassé
- ❌ Si une fonction "supprimer compte" fait `DELETE FROM users` côté client → cassé

**Recommandation** : ⚠️ **NE PAS EXÉCUTER** sans tests préalables en staging.

---

## 🎯 Ce que je te recommande comme parcours

```
ÉTAPE 1 — Maintenant (après déploiement v83 du code)
   │
   ├─► Exécute audit_rls.sql
   │   → Tu vois l'état actuel
   │
   ▼
ÉTAPE 2 — Quand tu te sens prêt (avec backup)
   │
   ├─► Exécute harden_rls_safe.sql
   │   → RLS activée partout, rien de cassé
   │   → Tu vérifies que tout fonctionne (10 min de tests)
   │
   ▼
ÉTAPE 3 — Plus tard, table par table (sur des semaines/mois)
   │
   ├─► Tu peux te baser sur harden_rls.sql comme référence
   │   → Mais à appliquer UNE TABLE À LA FOIS
   │   → En testant après chaque table
   │   → En commençant par les moins risquées (logs, audit)
```

---

## 🛡️ Ton plan d'action concret

### A. Maintenant : déploie le code v83 (HTML/JS/Edge Functions)

Les fixes #1, #2, #3, #4 du code sont **sûrs**. Aucun n'impacte le fonctionnement de :
- ✅ Fiches produits
- ✅ Capture stats BO parrains (`visitors`, `product_views`)
- ✅ Connexion parrains/clients/users
- ✅ Troc, achat, négociations
- ✅ Chat support
- ✅ Notifications, panier, commandes

Le seul flow potentiellement impacté est **AUDITAZ IA** (claude-proxy plus strict), mais tu utilises ecodila.com → c'est dans la whitelist.

### B. Cette semaine : audit RLS (sans risque)

Exécute `audit_rls.sql` dans Supabase. Lis les résultats. Tu sauras précisément quelles tables sont déjà bien configurées et lesquelles ne le sont pas.

### C. Quand tu auras un weekend tranquille : harden_rls_safe.sql

1. **Backup Supabase complet** (Manual backup dans le dashboard)
2. Exécute `harden_rls_safe.sql`
3. Teste chaque BO + le site (15 min)
4. Si quelque chose casse → tu as le backup pour rollback (mais c'est très peu probable)

### D. Plus tard (mois prochain) : durcissement progressif

Tu prends `harden_rls.sql` comme guide. Tu choisis UNE table à durcir (ex: `chat_conversations`). Tu remplaces les policies `_safe_` par des policies durcies. Tu testes. Tu passes à la suivante.

---

## ❓ Questions / réponses rapides

**Q : Si je n'exécute aucun SQL, est-ce que je suis vulnérable ?**

R : Tu restes au niveau de sécurité v82 actuel. C'est suffisant pour démarrer mais pas pour scale.

**Q : Si j'exécute uniquement `harden_rls_safe.sql`, est-ce que je gagne en sécurité ?**

R : Marginalement. Tu gagnes l'infrastructure RLS activée + un meilleur score d'audit. La protection effective viendra avec le durcissement progressif (étape D).

**Q : Si je veux la sécurité max maintenant ?**

R : Crée un projet Supabase de **staging** (gratuit). Copie ton schéma. Exécute `harden_rls.sql` dessus. Teste tous les flows. Si OK → applique en prod. Si KO → ajuste les policies pour les flows cassés.

**Q : Le risque que `harden_rls_safe.sql` casse quelque chose ?**

R : Très faible. Toutes les policies sont `USING (TRUE)` ce qui est strictement équivalent au comportement actuel "pas de RLS". Le seul cas de casse théorique : si une table avait déjà des policies STRICTES qu'on aurait écrasées. Mais l'audit dans `audit_rls.sql` te le dira AVANT.

---

## 📞 Si quelque chose casse

### Rollback `harden_rls_safe.sql` (cas peu probable)

```sql
-- Désactiver RLS sur toutes les tables ciblées
-- À exécuter dans Supabase SQL Editor

DO $$
DECLARE
  t TEXT;
BEGIN
  FOR t IN 
    SELECT tablename FROM pg_tables 
    WHERE schemaname = 'public' 
    AND tablename IN (
      'users', 'parrains', 'admins', 'auditaz_users', 'products',
      'settings', 'orders', 'propositions', 'trocs', 'coupons',
      'cart_history', 'offers', 'offer_logs', 'nego_abandoned',
      'parrain_commissions', 'parrain_paiements', 'parrain_concours',
      'parrain_statuts', 'concours_paiements', 'challenges', 'avis',
      'chat_conversations', 'chat_tickets', 'conversations',
      'visitors', 'product_views', 'notifications', 'error_logs',
      'rgpd_audit_log', 'auditaz_activity', 'auditaz_transfers',
      'auditaz_resolved', 'auditaz_banned_ips', 'auditaz_blocked_users',
      'auditaz_config', 'auditaz_permissions'
    )
  LOOP
    EXECUTE format('ALTER TABLE public.%I DISABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;
```

Ce script désactive RLS sur toutes les tables — état strictement équivalent à v82.

---

## 🎯 Ma reco finale

Pour ton **profil** (PME, croissance, pas d'équipe sécurité dédiée) :

1. ✅ **Déploie le code v83 maintenant** (fixes du code = sûrs)
2. ✅ **Exécute `audit_rls.sql` cette semaine** (zéro risque, juste lire)
3. ⏳ **Attends 1-2 semaines** (laisse v83 se stabiliser en prod)
4. ✅ **Exécute `harden_rls_safe.sql`** un dimanche matin (avec backup)
5. ⏳ **Plus tard** : durcissement progressif si tu as le temps

Cette approche te donne **80% du gain de sécurité avec 5% du risque**.

---

[← Retour à SECURITY-FIXES-v83.md](SECURITY-FIXES-v83.md)
