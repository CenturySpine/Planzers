# Branchement réel Ridgegear (projets + poids du sac)

## Contexte

Le module voyageur "Ridgegear" (structure posée précédemment) affiche
aujourd'hui un poids en dur et ouvre l'accueil Ridgegear au tap. Ce chantier
le rend réel : après connexion OAuth (déjà fonctionnelle), l'utilisateur
choisit un de ses projets Ridgegear, et le cartouche affiche le vrai poids
du sac de ce projet, avec un tap qui ouvre ce projet précis dans Ridgegear.

**Question ouverte tranchée** : qui écrit l'écran de sélection de projet —
le fournisseur ou le consommateur ? **Planerz (le consommateur) l'écrit**,
en appelant l'API métier de Ridgegear via le jeton déjà stocké. C'est le
pattern standard de tout l'écosystème OAuth (Zapier, IFTTT, Slack apps,
Google Calendar...) : le fournisseur n'expose qu'une API de données
protégée par le jeton ; l'app consommatrice construit sa propre UI dessus.
Ça garde la promesse "pas de flux OAuth à réimplémenter par fournisseur" —
seule la donnée métier est spécifique par nature (elle change forcément
d'un fournisseur à l'autre), pas le mécanisme d'accès.

**Décision confirmée avec toi** : le retour après connexion OAuth doit
ramener directement sur le sélecteur de projet du voyage en cours (pas
juste sur "Comptes externes connectés") — nécessite de faire transiter un
petit contexte de reprise à travers le flux OAuth existant (détaillé
ci-dessous), en réutilisant l'infrastructure déjà en place plutôt que
d'ajouter un nouveau mécanisme de state.

**Portée** : uniquement Ridgegear-projets-poids. Le wallet reste hors
périmètre (toujours maquette statique).

## Partie 1 — API métier côté Ridgegear (`C:\Users\pc_ga\repos\ridgegear`)

Deux nouvelles routes dans `functions/public_api.js` (même `onRequest`,
même style d'auth Bearer que Planerz — `model.getAccessToken` +
`model.verifyScope(token, 'gear.read')`, portée déjà enregistrée) :

- **`GET /v1/projects`** → liste `[{id, name, date, endDate, location}]`
  depuis `users/{uid}/projects`.
- **`GET /v1/projects/:id/weight`** → `{ totalWeightGrams }`, calculé à
  partir de `users/{uid}/projects/{id}/items` + `users/{uid}/gearItems`
  (pour la logique alimentation/hydratation). Extraire la logique de calcul
  en une **fonction pure exportée** `computeProjectTotalWeightGrams(items, gearItemsById, { activeDay, includeWater })`,
  mirroir exact de `carried()`/`totalWeight` dans
  `src/components/projects/project-checklist.tsx` (lignes 94-135) — même
  arithmétique (grammes, pas d'arrondi, `outOfBag` exclu, logique
  consommé/restant pour l'alimentation). Défauts pour l'API (différents de
  l'état initial de l'UI, sur ta demande) :
  `activeDay = aujourd'hui si le voyage a démarré (today >= project.date), sinon project.date (jour 1)`,
  `includeWater = false` (poids hors eau). Testée isolément dans un nouveau
  `functions/public_api.test.js`, comme `mapTripToApiShape` côté Planerz —
  cas de test couvrant explicitement : avant départ (jour 1), pendant le
  voyage (jour courant), après la fin du voyage.

Routage dans `exports.publicApi` (`functions/public_api.js`), même style
`if/return` que `/oauth/token` :
```js
const weightMatch = /^\/v1\/projects\/([^/]+)\/weight$/.exec(path);
if (path === '/v1/projects' && req.method === 'GET') { await handleProjectsList(req, res); return; }
if (weightMatch && req.method === 'GET') { await handleProjectWeight(req, res, weightMatch[1]); return; }
```

## Partie 2 — Backend Planerz (`functions/external_providers.js`)

### Nouveau champ sur `externalProviders/{providerId}` : `apiBaseUrl`

- `createExternalProvider` : nouveau paramètre `apiBaseUrl`, validé via
  `assertSafeProviderUrl` (déjà là) avant écriture.
- Nouvelle callable **`updateExternalProviderConfig`** (admin-only, mirroir
  de `updateExternalProviderSecret`) : permet d'éditer les champs non
  secrets (`displayName`, `iconUrl`, `authorizeUrl`, `tokenUrl`, `scope`,
  `apiBaseUrl`) sans toucher au secret ni recréer le fournisseur — évite le
  problème du secret Ridgegear déjà généré une seule fois pour
  `planerz-preview-local`.

### Nouvelle callable générique : `callExternalProviderApi({ providerId, path })`

- Auth requise. Charge `externalProviderTokens/{hashSecret(providerId+':'+uid)}` ;
  si absent → `failed-precondition` ("non connecté"). Vérifie
  `accessTokenExpiresAt` (jetons Ridgegear valables 30 jours, pas de
  rafraîchissement — limite connue, acceptée : au-delà, reconnexion
  manuelle requise, cas rare).
- `path` restreint à `^/v1/[a-zA-Z0-9/_-]+$` (garde-fou, pas un proxy
  ouvert).
- Charge `externalProviders/{providerId}.apiBaseUrl` (validé via
  `assertSafeProviderUrl`), fait `fetch(apiBaseUrl + path, { headers: { Authorization: 'Bearer ' + accessToken } })`,
  même style gestion d'erreur que `completeExternalConnection`
  (`res.ok`, `HttpsError('internal', ...)`, `insertApplicationLog`).
- Retourne `{ data: <json du fournisseur> }`.
- Aucun code spécifique Ridgegear ici — réutilisable tel quel pour tout
  futur fournisseur exposant une API `/v1/*` protégée par le même jeton.

### Reprise après OAuth (`beginExternalConnection` / `completeExternalConnection`)

- `beginExternalConnection` accepte un `resumeContext` optionnel (map
  libre, ex. `{ tripId, module }`), stocké tel quel sur le doc
  `pendingExternalConnections/{state}` déjà existant (pas de nouvelle
  collection).
- `completeExternalConnection` relit `pending.resumeContext` et le renvoie
  dans sa réponse : `{ connected: true, resumeContext }`.

## Partie 3 — Firestore (Planerz)

**Refonte du document `trips/{tripId}/travelerModules/{uid}`** : chaque
module a son propre sous-objet, au lieu d'empiler des champs à plat au
niveau racine (ce qui ne passerait pas à l'échelle avec de futurs modules
ayant chacun leur config). Structure revue :
```
{
  ridgegear: {
    enabled: bool,
    projectId: string | null,
    projectName: string | null,
  },
  wallet: {
    enabled: bool,
  },
  updatedAt: serverTimestamp,
}
```
Chaque module ne connaît que sa propre config, sous sa propre clé — ajouter
un futur module voyageur (ex. Killer) n'ajoute qu'une nouvelle clé de
premier niveau, jamais de nouveaux champs plats à gérer en parallèle.

**Migration depuis la structure actuelle** (`ridgegearEnabled`/
`walletEnabled` en champs plats, posée au chantier précédent, aucune
donnée réelle dessus à ce jour) : remplacement direct, pas de script de
migration nécessaire — le module vient d'être livré, personne n'a encore
de vraies données dessus en prod.

Règle (`firestore.rules`, bloc `travelerModules/{uid}`), validée mais sans
sur-ingénierie :
```
match /travelerModules/{uid} {
  allow read: if isTripMember(tripId) && uid == request.auth.uid;
  allow create, update: if isTripMember(tripId)
    && uid == request.auth.uid
    && request.resource.data.keys().hasOnly(['ridgegear', 'wallet', 'updatedAt'])
    && (!('ridgegear' in request.resource.data)
      || (request.resource.data.ridgegear is map
        && request.resource.data.ridgegear.keys().hasOnly(['enabled', 'projectId', 'projectName'])
        && (!('enabled' in request.resource.data.ridgegear)
          || request.resource.data.ridgegear.enabled is bool)))
    && (!('wallet' in request.resource.data)
      || (request.resource.data.wallet is map
        && request.resource.data.wallet.keys().hasOnly(['enabled'])
        && (!('enabled' in request.resource.data.wallet)
          || request.resource.data.wallet.enabled is bool)));
  allow delete: if false;
}
```
(`projectId`/`projectName` volontairement non type-checkés dans la règle —
ils peuvent être `null` en désactivation ; la validation de forme suffit
pour ce niveau de risque, la donnée n'est de toute façon lisible que par
son propriétaire.)

## Partie 4 — Flutter (Planerz)

### Data layer

- `lib/features/oauth/data/external_connection_repository.dart` :
  - `beginConnection(...)` gagne un `resumeContext` optionnel (transmis
    tel quel à la callable).
  - `completeConnection(...)` retourne maintenant `Map<String, dynamic>?`
    (le `resumeContext` reçu), au lieu de `void`.
  - Nouvelle méthode `callProviderApi({required String providerId, required String path})`
    → appelle `callExternalProviderApi`, retourne `result.data['data']`.
- `lib/features/trips/data/traveler_modules_repository.dart` — modèle revu
  pour suivre la nouvelle structure imbriquée :
  ```dart
  class RidgegearModuleConfig {
    const RidgegearModuleConfig({
      this.enabled = false,
      this.projectId,
      this.projectName,
    });
    final bool enabled;
    final String? projectId;
    final String? projectName;
  }

  class TravelerModules {
    const TravelerModules({
      this.ridgegear = const RidgegearModuleConfig(),
      this.walletEnabled = false,
    });
    final RidgegearModuleConfig ridgegear;
    final bool walletEnabled;
  }
  ```
  Méthodes d'écriture dédiées (plutôt qu'un `setModuleEnabled` générique à
  champs plats) :
  - `setWalletEnabled(tripId, enabled)` → merge `{'wallet': {'enabled': enabled}}`.
  - `setRidgegearProject({tripId, projectId, projectName})` → merge
    `{'ridgegear': {'enabled': true, 'projectId': projectId, 'projectName': projectName}}`
    (écriture atomique activation+sélection).
  - `disableRidgegear(tripId)` → merge
    `{'ridgegear': {'enabled': false, 'projectId': null, 'projectName': null}}`
    (état propre, pas de projet fantôme si réactivé).
  `set(..., SetOptions(merge: true))` avec une valeur imbriquée fait un
  merge profond côté Firestore (seules les clés fournies dans le sous-objet
  sont touchées) — pas besoin de notation à points.

### Sélecteur de projet (nouveau)

Nouveau `lib/features/trips/presentation/ridgegear_project_picker.dart` —
`showModalBottomSheet` (même style que le sheet "+" existant) :
appelle `callProviderApi(providerId: 'ridgegear', path: '/v1/projects')`,
liste les projets (nom + dates), **tap = sélection immédiate** (pas de
bouton "valider" séparé — le tap fait office de confirmation, pattern
standard de sélecteur). Sur tap : écrit `ridgegearProjectId`/`Name` +
`ridgegearEnabled: true`, ferme le sheet. États chargement/erreur standards.

### Flux d'activation (`traveler_modules_toggle_list.dart`)

Le toggle Ridgegear devient spécial (le toggle Wallet reste un simple
booléen direct) :
- Si déjà connecté (vérifié via
  `connectedExternalProvidersRepositoryProvider.watchMyConnectedProviders()`,
  cherche `providerId == 'ridgegear'`) → ouvre directement le sélecteur de
  projet ci-dessus.
- Sinon → `beginConnection(providerId: 'ridgegear', redirectUri: ..., resumeContext: {tripId, module: 'ridgegear'})`
  puis `launchUrl(...)` (flux déjà existant, juste enrichi du
  `resumeContext`).
- Toggle OFF → `disableRidgegear(tripId)` (état propre, pas de projet
  fantôme si réactivé plus tard — il faudra re-choisir).
- Quand déjà activé, un petit lien "Changer de projet" à côté du nom du
  projet actuel rouvre le sélecteur.

### Retour après connexion (`external_connection_callback_page.dart`)

- Lit le `resumeContext` retourné par `completeConnection(...)`.
- Si présent avec `tripId` : `context.go('/trips/${resumeContext['tripId']}/overview?openModulePicker=${resumeContext['module']}')`
  au lieu d'aller vers `ConnectedExternalProvidersPage`.
- Sinon (flux actuel, ex. connexion depuis le compte) : comportement
  inchangé.

### Reprise automatique du sélecteur (`trip_overview_page.dart`)

Dans `initState`/`postFrameCallback` : lit
`GoRouterState.of(context).uri.queryParameters['openModulePicker']` ; si
`== 'ridgegear'`, ouvre directement le sélecteur de projet (une fois,
puisqu'on est déjà connecté à ce stade — la reconnexion vient de réussir).

### Cartouche Ridgegear (données réelles)

- Poids : `FutureProvider`/appel `callProviderApi(path: '/v1/projects/${ridgegear.projectId}/weight')`
  quand `ridgegear.projectId` est renseigné, conversion grammes → kg
  (`/ 1000`, 1 décimale, format déjà utilisé "12,4"). État vide (pas de
  projet choisi) → statusText invite à choisir un projet, tap ouvre le
  sélecteur au lieu du poids.
- Tap (projet choisi) : ouvre
  `https://ridgegear.centuryspine.org/projects/${ridgegear.projectId}` (au
  lieu de l'accueil générique actuel).

### Écran admin (Planerz) — `apiBaseUrl`

- `external_providers_repository.dart` / `admin_external_providers_page.dart` :
  nouveau champ `apiBaseUrl` dans le formulaire de création
  (`createProvider(...)`), et une petite action "Modifier l'URL API" sur
  chaque ligne de la liste (dialog un-champ, appelle
  `updateExternalProviderConfig`) — nécessaire notamment pour mettre à jour
  l'entrée Ridgegear déjà enregistrée sur `planerz-preview` sans devoir la
  supprimer/recréer (ce qui obligerait à regénérer un secret déjà
  consommé).

## Vérification

- Ridgegear : nouveau `functions/public_api.test.js` (calcul de poids pur,
  cas simples + alimentation/hydratation/`outOfBag`) + `npm test`.
- Planerz : `flutter analyze` sur les fichiers touchés.
- Test manuel de bout en bout (comme le chantier précédent) : depuis
  Planerz local ou preview, activer Ridgegear sur un voyage → si pas
  connecté, redirection OAuth → retour automatique sur le sélecteur du
  **même voyage** → choix d'un projet réel → cartouche affiche le vrai
  poids → tap ouvre le bon projet Ridgegear.

## ⚠️ Opérations manuelles à faire toi-même

1. **Déploiement Ridgegear** :
   ```powershell
   firebase deploy --only functions:publicApi --project ridgegear-6974b
   ```
2. **Déploiement Planerz** (nouvelles/`updateExternalProviderConfig`,
   `callExternalProviderApi`, champs `beginExternalConnection`/`completeExternalConnection`) :
   ```powershell
   firebase deploy --only functions,firestore:rules --project planerz-preview
   ```
3. **Vérification IAM Cloud Run** pour `updateExternalProviderConfig` et
   `callExternalProviderApi` (nouvelles fonctions), même procédure que les
   chantiers précédents.
4. **Renseigner `apiBaseUrl`** pour le fournisseur `ridgegear` déjà
   enregistré sur `planerz-preview`, via la nouvelle action "Modifier l'URL
   API" de l'écran admin (valeur : l'URL de la fonction `publicApi`
   Ridgegear déjà récupérée précédemment,
   `https://publicapi-w2qekjkc6q-od.a.run.app`).
5. **`git commit`** sur les deux repos — laissé à ton initiative comme
   toujours.
