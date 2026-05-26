# Plan — Groupes de participants (parts) pour les dépenses

> **Statut :** plan (non implémenté). Décisions validées en session de conception.

## Objectif

Permettre de constituer des **groupes de participants** (couple, famille, etc.) avec un nombre de **parts**, utilisables comme une seule unité dans les dépenses et les soldes — sans remboursements internes au sein du groupe.

---

## Principe

- **[`TripMember`](../../lib/features/trips/data/trip_member.dart)** : inchangé (identité, séjour, claim, etc.).
- **Nouvelle entité** `trips/{tripId}/participantGroups/{groupId}` : agrégat de facturation, pas un remplacement du participant.
- **Unité de facturation** : 1 `TripMember` non groupé (**1 part**) **ou** 1 `ParticipantGroup` (**`parts`** du groupe).
- **Périmètre** : les groupes ne s’appliquent **qu’aux dépenses** et concepts dérivés (soldes par poste, suggestions de remboursement, settlements enregistrés). **Aucun** autre module du voyage (repas, chambres, activités, shopping, cupidon, etc.) — les `TripMember` restent individuels partout ailleurs.
- **Dépense (persistance)** : champs existants (`paidBy`, `participantIds`, `participantShares`, settlements `from`/`to`) — **même format** (`string` / `string[]` / `Map<string,number>`). La valeur peut être un id `participants/*` **ou** `participantGroups/*` ; **pas de nouveau champ** sur [`TripExpense`](../../lib/features/expenses/data/expense.dart) ni modèles dérivés ([`GroupBalance`](../../lib/features/expenses/data/group_balance.dart), [`SuggestedReimbursement`](../../lib/features/expenses/data/suggested_reimbursement.dart)).
- **Calcul** : avant répartition, `resolveUnit(id)` charge `participantGroups` et retourne les `parts` (1 ou `group.parts`).

```mermaid
flowchart LR
  subgraph trip [Voyage]
    M1[TripMember]
    G[ParticipantGroup]
  end
  subgraph expense [expenses inchangé]
    paidBy[paidBy string]
    pIds[participantIds string array]
  end
  G --> M1
  paidBy --> G
  pIds --> G
  pIds --> M3[membre seul]
  paidBy --> resolve[resolveUnit + parts]
  pIds --> resolve
  resolve --> settle[computeBalances nets]
```

---

## Modèle Firestore

`participantGroups/{groupId}` :

| Champ | Type | Règle |
|-------|------|--------|
| `label` | string | obligatoire à la création (affichage) |
| `memberIds` | string[] | IDs `participants/*`, minimum **2** |
| `parts` | number | > 0, ex. `2`, `2.5` |
| `createdAt` / `updatedAt` | timestamp | |

**Contraintes produit (CF + client)** :

- Un `TripMember` dans **au plus un** groupe.
- Membre d’un groupe **jamais** stocké seul dans `paidBy` / `participantIds` d’une dépense (seul l’id du groupe).
- **Suppression groupe** : **interdite** si son id apparaît dans une opération — `paidBy`, `participantIds`, clé de `participantShares`, ou settlement équivalent. Pas de dissolution ni recalcul historique.
- **Suppression participant** : bloquer si membre d’un groupe **ou** référencé dans une dépense ; étendre [`assertMemberNotUsedInExpenses`](../../functions/index.js) + contrôle d’usage des groupes.

---

## Dépense — persistance (inchangée)

Aucun changement de **forme** des modèles / documents Firestore dépenses :

| Champ existant | Sémantique élargie |
|----------------|-------------------|
| `paidBy` | id participant **ou** id groupe |
| `participantIds` | liste d’ids participant **ou** groupe (jamais un membre déjà dans un groupe) |
| `participantShares` | clés = mêmes ids |
| `fromParticipantId` / `toParticipantId` (suggestions, settlements) | id participant **ou** groupe |

**Résolution** (helper partagé client + [`participantSharesForExpense`](../../functions/expense_settlement.js)) — **seul point d’évolution algo** :

```
resolveUnit(id, groupsMap, membersMap) → parts
  id ∈ participants  → 1
  id ∈ participantGroups → group.parts
  inconnu → fallback 1 ou erreur validation à l’écriture
```

**Répartition** (`splitMode: equal`, pondéré par parts) sur `participantIds` :

```
share(id) = amount × parts(id) / Σ parts(participantIds)
```

**Soldes (`nets`)** — clés = ces mêmes ids (membre ou groupe), **pas de ventilation** vers `memberIds` :

```
nets[paidBy] += amount
pour chaque id dans participantIds : nets[id] -= share(id)
```

- `customAmounts` : clés inchangées ; somme ±0,02 €.
- **Suggestions** : [`suggestTransfers`](../../functions/expense_settlement.js) inchangé (greedy, minimise le nombre de virements) ; entrée/sortie = mêmes champs, ids pouvant être des groupes.
- **Vue utilisateur connecté** : `billingUnitId(memberId)` → `groupId` si membre groupé, sinon `memberId` (voir filtres ci‑dessous).
- Voyages sans groupes → comportement strictement identique à aujourd’hui.

---

## Calcul / sync

Fichiers à aligner (même algo) :

- [`functions/expense_settlement.js`](../../functions/expense_settlement.js)
- [`scripts/expense_settlement.js`](../../scripts/expense_settlement.js)
- `tripExpenseUnitLabelsProvider` (ou équivalent) consommé par les écrans dépenses ; pas de logique de label inline dans les widgets
- Tests [`functions/expense_settlement.test.js`](../../functions/expense_settlement.test.js)

`computeBalances` charge les groupes du voyage (ou snapshot passé au recalc) une fois par batch.

---

## UI (scope v1)

### Gestion des participants — nouvel onglet

[`trip_participants_page.dart`](../../lib/features/trips/presentation/trip_participants_page.dart) : ajouter un **`TabBar` / `TabBarView`** (même page, pas de route séparée).

| Onglet | Contenu |
|--------|---------|
| **Participants** (existant) | Liste / ajout / édition des voyageurs — inchangé |
| **Groupes** (nouveau) | Constitution et gestion des groupes de facturation |

**Onglet Groupes** : visible pour tous ; **lecture seule** si `manageParticipants` absent (pas de création / édition / suppression) :

- Liste des groupes du voyage (label, membres résumés, `parts`).
- **Créer / modifier** (dialog ou page secondaire légère) :
  - **Label** (obligatoire, ex. « A&B », « Famille Martin »).
  - **Membres** : sélection multi parmi les `TripMember` **non déjà dans un autre groupe** ; minimum **2**.
  - **Parts** : par défaut = **nombre de membres du groupe** ; champ **éditable à la main** (nombre > 0, décimales autorisées — ex. 2,5).
- **Supprimer** un groupe : autorisé **uniquement** s’il n’apparaît dans aucune opération ; sinon action désactivée + message l10n (CF `failed-precondition` en secours).
- l10n : libellés onglet, actions, validations (min 2 membres, parts invalides, membre déjà groupé, groupe utilisé dans des dépenses).

### Dépenses (v1)

[`trip_expenses_page.dart`](../../lib/features/expenses/presentation/trip_expenses_page.dart) — **payeur** et **concernés** : **même liste d’unités** :

- Membres **non groupés** (individuels).
- **Groupes** entiers (une entrée = une unité de facturation).
- **Jamais** les `TripMember` qui appartiennent déjà à un groupe (ni en payeur, ni en concerné).

Règle produit : un groupe **paie** ou **est concerné** en bloc ; l’app ne modélise pas qui paie quoi **à l’intérieur** du groupe (compte commun / arrangement hors app).

Sélection payeur / concernés : liste = membres non groupés + groupes (ids stockés dans les champs existants).

### Soldes & remboursements (UI existante — ne pas refactoriser)

Écrans / widgets actuels (liste des `nets`, suggestions, settlements faits) : **mise en page et structure inchangées**.

Seul changement : résolution du **nom affiché** pour une clé/id (participant ou groupe).

Pas de nouvelle ligne UI, pas de regroupement visuel supplémentaire : une clé = une ligne, comme aujourd’hui.

### Filtres « Tous / Moi » (comportement existant, élargi aux groupes)

Filtres actuels : opérations (`_showAllOperations` + `involvesMember`) ; onglet équilibres — suggestions et remboursements enregistrés (`_showAllPost` + `_involvesCurrentUser`).

**Règle** : résoudre `viewerBillingUnitId = billingUnitId(currentUserMemberId)` une fois par écran.

| Filtre « Moi » | Avant | Après |
|----------------|-------|-------|
| Liste opérations | `expense.involvesMember(memberId)` | `expense.involvesUnit(viewerBillingUnitId)` — `paidBy`, `participantIds` ou clé `participantShares` |
| Suggestions | `from` / `to` == `memberId` | `from` / `to` == `viewerBillingUnitId` |
| Settlements enregistrés | idem `involvesMember` | idem `involvesUnit` |
| Participant solo | = comportement actuel | `viewerBillingUnitId` == `memberId` |

Helper partagé (ex. `expenseInvolvesBillingUnit(expense, unitId)`) — pas de duplication dans chaque filtre.

**En-tête poste** (« mes totaux » / « ma part ») : agrégats indexés par `viewerBillingUnitId` dans `summary` / boucle coût, pas par `memberId` seul si l’utilisateur est dans un groupe.

« Tous » : inchangé (toutes les opérations / tous les remboursements visibles).

### Résolution des libellés (factorisée, réutilisable)

Sur le modèle existant participants ([`tripMemberLabelsFromMembers`](../../lib/features/auth/data/user_display_label.dart), [`tripMemberResolvedLabelsProvider`](../../lib/features/trips/data/trip_members_repository.dart)) :

| Couche | Participants (existant) | Groupes (à ajouter) |
|--------|----------------------|---------------------|
| Fonction pure | `resolveTripMemberDisplayLabel` / `tripMemberLabelsFromMembers` | `resolveParticipantGroupDisplayLabel` / `participantGroupLabelsFromGroups` → `group.label` |
| Provider Riverpod | `tripMemberResolvedLabelsProvider(tripId)` | `tripParticipantGroupLabelsProvider(tripId)` → `Map<groupId, String>` |
| Résolution d’un id dépense | — | `tripExpenseUnitLabelsProvider(tripId)` : lookup membre puis groupe ; **une seule API** pour dépenses / soldes / suggestions |

Règles :

- Pas de libellés groupes en dur dans les widgets ; toujours via provider / helper.
- Périmètre dépenses : le provider fusionné vit côté `expenses` ou `trips/data` selon dépendances, mais les helpers groupes restent réutilisables (détail dépense, onglet Groupes, etc.).

**Hors périmètre (toutes versions tant que non spécifié)** : repas, chambres, activités, listes, votes, profils, invitations, etc. — aucune référence à `participantGroups` en dehors du fil dépenses.

---

## Permissions

Réutiliser `permissions.participants.manageParticipants` (ou équivalent existant) pour gérer les groupes ; lecture pour tous les participants du voyage.

---

## Ce qu’on évite

- Pas d’usage des groupes hors **dépenses + dérivés** (ne pas toucher aux collections / écrans repas, chambres, activités, …).
- Pas de fusion groupes / [`expenseGroups`](../../lib/features/expenses/data/expense_group.dart) (postes de dépense ≠ groupes de voyageurs).
- Pas de modification du schéma `TripMember` ni des **champs** des modèles dépense / balance / suggestion / settlement.
- Pas de refonte UI des écrans soldes & remboursements (libellés uniquement).
- **Pas de ventilation des montants vers les `memberIds`** (ni pour soldes, ni pour suggestions) — c’est le cœur métier du regroupement.
- Pas de stockage de parts par membre sur chaque dépense (résolution via le groupe).
- Pas de suppression de groupe « en cascade » sur les dépenses existantes.

---

## Scénario de référence (validé)

Pierre, Sabine ; groupe A&B (`parts=2`, Alice+Bob). Deux dépenses 100 €, concernés : Pierre, Sabine, A&B (4 parts → 25 € / part unitaire).

| | Pierre | Sabine | A&B |
|--|--------|--------|-----|
| T0 Sabine paie | −25 | +75 | −50 |
| T1 A&B paient | −25 | −25 | +50 |
| **nets** | **−50** | **+50** | **0** |

Suggestion : **Pierre → Sabine, 50 €** (pas 25+25). Décomposition bilatérale par dépense = lecture informative seulement.

---

## Hors scope v1 (extensions possibles)

- Répartition **interne** au groupe, sélection mixte groupe + membre du même groupe, ou membre groupé en individuel dans une dépense.
- Migration auto des dépenses historiques vers des groupes.

---

## Tâches d’implémentation

- [ ] Collection `participantGroups` + modèle Dart + repository + règles Firestore
- [ ] Schéma dépense inchangé ; `resolveUnit` au calcul (CF + script + tests)
- [ ] `computeBalances` / suggestions / settlements sur ids unitaires
- [ ] Onglet Groupes dans `TripParticipantsPage`
- [ ] Sélection unités dépenses + filtres Tous/Moi via `billingUnitId` + libellés factorisés
- [ ] Blocage suppression groupe/participant si référencé dans une opération
