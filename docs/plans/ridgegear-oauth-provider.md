# Ridgegear comme fournisseur OAuth (côté Ridgegear)

## Contexte

Planerz sait déjà, côté client, se connecter à un fournisseur externe
générique (`beginExternalConnection`/`completeExternalConnection`, déjà
implémenté et vérifié via le fournisseur factice `planerz-selftest`). Il
manque le pendant côté **Ridgegear** : Ridgegear doit devenir un vrai
fournisseur OAuth 2.0 (authorization-code), pour qu'un utilisateur puisse
autoriser Planerz à accéder à son compte Ridgegear, et que Planerz obtienne
un jeton d'accès valide.

**Hors périmètre, comme convenu** : tout ce qui concerne l'affichage ou la
consommation des données Ridgegear dans une page voyage Planerz (les
"modules"). Ce plan s'arrête au moment où Planerz obtient et stocke avec
succès un jeton d'accès Ridgegear pour un utilisateur réel — exactement le
même point d'arrêt que le chantier symétrique déjà fait côté Planerz.

Ridgegear (`C:\Users\pc_ga\repos\ridgegear`) est une appli **Next.js 16 / React
19** (App Router), sans aucune API serveur aujourd'hui (`src/app/api/` n'existe
pas), qui n'utilise Firebase que pour Auth/Firestore/Storage côté client — pas
de Cloud Functions, pas de `.gitmodules`. Deux décisions confirmées avec toi :

- **Backend OAuth = nouvelles Firebase Functions v2** (nouveau dossier
  `functions/` dans le projet Firebase `ridgegear-6974b`, déployé
  séparément du site Next.js) plutôt que de réimplémenter la logique en
  Route Handlers Next.js — ça permet de réutiliser **tel quel**
  `oauth-provider-core` (déjà sur
  [github.com/CenturySpine/oauth-provider-core](https://github.com/CenturySpine/oauth-provider-core)),
  exactement la promesse de ce sous-module.
- **Contrôle admin = champ Firestore `isApplicationOwner`** sur
  `users/{uid}`, même pattern que Planerz.

## Partie 1 — Backend Firebase Functions v2

Nouveau dossier `functions/` à la racine de `ridgegear`, structure calquée
sur `Planzers/functions/` :

```
functions/
  index.js               # exporte les fonctions ci-dessous
  oauth_authorize.js      # fin wrapper, comme Planzers/functions/oauth_authorize.js
  package.json             # firebase-admin, firebase-functions, @node-oauth/oauth2-server
  vendor/
    oauth-provider-core/   # git submodule (même repo que Planerz)
```

- `git submodule add https://github.com/CenturySpine/oauth-provider-core.git functions/vendor/oauth-provider-core`
  depuis la racine `ridgegear`.
- `functions/oauth_authorize.js` : même structure que
  [functions/oauth_authorize.js](../../Planzers/functions/oauth_authorize.js)
  côté Planerz — `requireApplicationOwner(uid)` lit
  `users/{uid}` via `firebase-admin` (Admin SDK, donc pas soumis aux règles
  Firestore) et vérifie `isApplicationOwner === true`, puis
  `createClientAdmin({ model, requireAdmin: requireApplicationOwner })`
  ré-exporte `getOAuthClientPublicInfo`, `authorizeOAuthClient`,
  `revokeConnectedApp`, `createOAuthClient`, `listOAuthClients`,
  `deleteOAuthClient`.
- `functions/public_api.js` (ou directement dans `index.js`, pas de logique
  métier à part côté Ridgegear pour l'instant — pas de "trips" à exposer) :
  route unique `/oauth/token`, `onRequest`, déléguée à
  `createTokenHandler(model)` du sous-module (`handleToken` + `setCors`),
  identique au `handleToken` déjà utilisé côté Planerz. Pas de `/v1/*`
  additionnel — Ridgegear n'expose aucune donnée métier via cette API pour
  l'instant (hors périmètre : ce sera le sujet du futur chantier "module").
- `functions/index.js` : `setGlobalOptions` région `europe-west9` (cohérence
  avec Planerz, aucune contrainte différente identifiée côté Ridgegear),
  exporte les 6 callables + `publicApi`.
- `functions/package.json` : `firebase-admin`, `firebase-functions`,
  `@node-oauth/oauth2-server` en dépendances directes (mêmes versions que
  Planerz) ; `"engines": {"node": "22"}`. Le `firebase-admin@^14.2.0` déjà
  utilisé dans `src/lib/firebase/admin.ts` (racine Next.js) est indépendant —
  `functions/` a son propre `package.json`/`node_modules`, aucun conflit.
- `firebase.json` (racine `ridgegear`) : ajouter un bloc `"functions": {
  "source": "functions" }` à côté des blocs `firestore`/`storage` déjà
  présents.

**Identification de l'utilisateur connecté** : les callables `onCall`
reçoivent automatiquement `context.auth.uid` une fois le SDK client Firebase
Functions appelé depuis le front (le jeton d'ID FirebAse Auth déjà utilisé
partout dans Ridgegear est transmis automatiquement) — pas besoin de
`adminAuth.verifyIdToken()` manuel, exactement comme Planerz ne le fait pas
non plus pour ses callables.

## Partie 2 — Firestore

Réutilisation intégrale du modèle générique du sous-module :
`oauthClients`, `oauthAuthorizationCodes`, `oauthAccessTokens` — fermées
aux clients (`allow read, write: if false`), à ajouter dans
[firestore.rules](../../ridgegear/firestore.rules) (qui aujourd'hui ne
contient qu'un seul bloc générique `users/{uid}/{document=**}`) :

```
match /oauthClients/{clientId} { allow read, write: if false; }
match /oauthAuthorizationCodes/{code} { allow read, write: if false; }
match /oauthAccessTokens/{tokenId} { allow read, write: if false; }
```

Le champ `isApplicationOwner` vit directement sur le document
`users/{uid}` existant — déjà couvert en lecture/écriture par la règle
générique actuelle (le propriétaire peut lire/écrire son propre document).
Même modèle de confiance que Planerz : c'est toi (au clavier, via la
console Firebase) qui poses `isApplicationOwner: true` sur ton propre
utilisateur Ridgegear, pas un flux self-service.

Pas de miroir `connectedApps` nécessaire côté Ridgegear pour l'instant —
personne d'autre que Planerz ne consommera cette API dans l'immédiat, et la
liste des clients autorisés est déjà consultable via l'écran admin (Partie
4). À ajouter plus tard si un vrai "écran utilisateur : applications
connectées à mon compte Ridgegear" devient nécessaire.

## Partie 3 — Écran de consentement (`/oauth/authorize`)

Nouvelle page `src/app/oauth/authorize/page.tsx` (hors du groupe de routes
`(app)` — pas besoin du chrome applicatif complet), `"use client"`, suit le
pattern déjà en place (`useAuth()`, composants `Button`/`Input` de
`src/components/ui/`) :

- Lit les query params standards OAuth : `client_id`, `redirect_uri`,
  `scope`, `state` (posés par l'URL que construit `beginExternalConnection`
  côté Planerz).
- Si `!loading && !user` : redirige vers
  `/login?redirect=${encodeURIComponent(currentUrlWithQuery)}` — nécessite
  une petite extension de
  [src/app/login/page.tsx](../../ridgegear/src/app/login/page.tsx) pour lire
  un paramètre `redirect` optionnel et l'utiliser à la place du
  `router.replace("/home")` codé en dur après connexion (2 endroits :
  `handleSubmit` et `handleGoogle`).
- Si connecté : appelle `getOAuthClientPublicInfo({ clientId: client_id })`
  (callable générique du sous-module) pour afficher le nom de l'app
  demandeuse (Planerz) et le `scope` demandé, avec deux boutons
  "Autoriser" / "Refuser".
- "Autoriser" → appelle `authorizeOAuthClient({ clientId, redirectUri,
  scope, state })`, récupère le `code`, puis
  `window.location.href = `${redirectUri}?code=${code}&state=${state}``.
- "Refuser" → redirige vers `redirectUri` avec `?error=access_denied&state=...`.

Modèle direct de
[lib/features/oauth/presentation/oauth_authorize_page.dart](../../Planzers/lib/features/oauth/presentation/oauth_authorize_page.dart)
côté Planerz, transposé en React/Next.

## Partie 4 — Écran admin des clients OAuth

Nouvelle page, ex. `src/app/(app)/admin/oauth-clients/page.tsx` (dans le
groupe `(app)` pour bénéficier du chrome existant), gardée côté client par
une lecture du champ `isApplicationOwner` du document `users/{uid}` courant
(via le SDK client Firestore, déjà autorisé par les règles) — si absent ou
`false`, `redirect("/home")`.

CRUD via les callables génériques déjà exportées (`listOAuthClients`,
`createOAuthClient`, `deleteOAuthClient`) : formulaire de création
(`displayName`, `redirectUris`, `scopesAllowed` — ex. `gear.read`), affichage
one-time du `client_secret` généré (jamais réaffiché ensuite, même logique
que côté Planerz), liste avec suppression confirmée (réutiliser
`ConfirmDialog` de `src/components/ui/` s'il existe, sinon `window.confirm`
en dernier recours). Pas de nouveau design system à inventer — réutiliser
`Button`/`Input` existants.

C'est cet écran qui servira, une fois déployé, à générer le `client_id`/
`client_secret` que tu iras ensuite saisir dans l'écran admin **Planerz**
"Fournisseurs externes" pour enregistrer Ridgegear comme fournisseur — geste
manuel, symétrique à ce qui a été fait côté Planerz pour enregistrer
Ridgegear comme consommateur.

## Vérification

- **Non-régression du sous-module** : `oauth-provider-core` n'est pas
  modifié par ce chantier ; aucun test à ajouter dedans.
- **Émulateurs** : `firebase emulators:start --only auth,firestore,functions
  --project ridgegear-6974b` + `next dev` en parallèle, pour tester le flow
  complet avec un client OAuth factice créé via l'écran admin, sans dépendre
  de Planerz.
- **Test d'intégration réel** (le seul segment qui ne peut pas être testé en
  émulateur) : une fois les deux côtés déployés, depuis un compte Planerz
  réel → Compte → "Comptes externes connectés" → "Connecter" en face de
  Ridgegear → vérifier la redirection réelle vers l'écran de consentement
  Ridgegear déployé, l'autorisation, puis le retour sur Planerz avec la
  connexion affichée comme active.
- `npm run lint` (ESLint déjà configuré) sur les fichiers touchés/ajoutés
  côté Ridgegear.

## ⚠️ Opérations manuelles à faire toi-même

1. **Vérifier/passer le projet Firebase `ridgegear-6974b` en plan Blaze**
   (pay-as-you-go) — `firebase.json` n'a jamais eu de bloc `functions`
   jusqu'ici, ce qui suggère que Cloud Functions n'a peut-être jamais été
   activé sur ce projet ; c'est un prérequis strict pour déployer la
   moindre fonction (le plan Spark ne permet pas les Cloud Functions v2).
2. **Provisionnement IAM** : aucun besoin de Secret Manager ici (pas de
   fournisseur tiers à configurer côté Ridgegear), donc pas de grant
   équivalent à celui fait côté Planerz.
3. **Déploiement** :
   ```powershell
   firebase deploy --only firestore:rules --project ridgegear-6974b
   firebase deploy --only functions --project ridgegear-6974b
   ```
4. **Vérification IAM Cloud Run obligatoire** pour les 6 nouvelles fonctions
   (même exigence que côté Planerz) :
   ```powershell
   gcloud run services get-iam-policy getoauthclientpublicinfo --region=europe-west9 --project=ridgegear-6974b
   gcloud run services get-iam-policy authorizeoauthclient --region=europe-west9 --project=ridgegear-6974b
   gcloud run services get-iam-policy revokeconnectedapp --region=europe-west9 --project=ridgegear-6974b
   gcloud run services get-iam-policy createoauthclient --region=europe-west9 --project=ridgegear-6974b
   gcloud run services get-iam-policy listoauthclients --region=europe-west9 --project=ridgegear-6974b
   gcloud run services get-iam-policy deleteoauthclient --region=europe-west9 --project=ridgegear-6974b
   gcloud run services get-iam-policy publicapi --region=europe-west9 --project=ridgegear-6974b
   ```
   Si `allUsers`/`roles/run.invoker` manque :
   ```powershell
   gcloud run services add-iam-policy-binding <service> --region=europe-west9 --project=ridgegear-6974b --member=allUsers --role=roles/run.invoker
   ```
5. **Poser `isApplicationOwner: true`** sur ton propre document
   `users/{uid}` dans Firestore (console Firebase, projet
   `ridgegear-6974b`) pour accéder à l'écran admin.
6. **Créer le client OAuth "Planerz"** depuis le nouvel écran admin
   Ridgegear une fois déployé, noter le `client_id`/`client_secret`
   affichés (one-time), puis aller les saisir dans l'écran admin Planerz
   "Fournisseurs externes" (`providerId: ridgegear`, `authorizeUrl` =
   l'URL de la page `/oauth/authorize` déployée, `tokenUrl` = l'URL de la
   fonction `publicApi` déployée + `/oauth/token`, `scope` = à définir,
   ex. `gear.read`).
7. **Déployer le site Next.js** (Vercel ou autre hébergeur déjà en place)
   avec les nouvelles pages — non couvert ici, dépend de l'hébergement
   actuel de `ridgegear.centuryspine.org`.
8. **`git commit`** — laissé à ton initiative une fois le diff relu, comme
   toujours.
