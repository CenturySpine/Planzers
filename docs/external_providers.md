# Fournisseurs externes (OAuth)

Ce document couvre les **deux sens** possibles de connexion OAuth entre
Planerz et un autre projet de l'écosystème (ex. Ridgegear) :

- **Planerz-en-tant-que-client** : un utilisateur Planerz lie son compte à un
  fournisseur externe pour que Planerz puisse lire ses données là-bas (ex.
  Planerz lit le poids du sac d'un utilisateur sur Ridgegear). C'est
  l'écran admin "Fournisseurs externes (OAuth)". Voir "Ajouter un
  fournisseur externe" ci-dessous.
- **Planerz-en-tant-que-fournisseur** : une appli tierce (ex. Ridgegear) lit
  les données d'un utilisateur Planerz (ses trips) via l'API publique
  Planerz. C'est l'écran admin "Applications tierces (OAuth)". Voir
  "Déclarer une application tierce" plus bas.

Ces deux sens sont symétriques et indépendants : connecter Ridgegear ↔
Planerz dans un sens ne configure pas l'autre. Dans le cas Ridgegear, les
**deux** manipulations sont faites, une de chaque côté :

| Côté configuré                              | Sens                                    | Doc                                                    |
|----------------------------------------------|------------------------------------------|---------------------------------------------------------|
| Écran admin **Planerz** "Fournisseurs externes" | Planerz lit les données Ridgegear       | "Ajouter un fournisseur externe" (ce document)           |
| Écran admin **Ridgegear** "Applications tierces" | Ridgegear lit les données Planerz (si besoin un jour) | équivalent, côté Ridgegear |
| Écran admin **Planerz** "Applications tierces"  | Une appli tierce lit les données Planerz | "Déclarer une application tierce" (ce document)          |

## Prérequis techniques (une seule fois par projet Firebase, pas par fournisseur)

- **IAM Secret Manager** accordé au compte de service des Cloud Functions du
  projet (nécessaire uniquement côté "Planerz-en-tant-que-client", puisque
  c'est là que les `client_secret` des fournisseurs externes sont stockés) —
  voir la section "IAM requis" plus bas pour la commande exacte et comment
  diagnostiquer un oubli.
- **IAM Cloud Run invoker** vérifié sur toutes les fonctions HTTP/callable du
  flow (`publicApi`, `listExternalProviders`, `beginExternalConnection`,
  `completeExternalConnection`, `revokeExternalConnection`,
  `callExternalProviderApi`, `createExternalProvider`,
  `updateExternalProviderSecret`, `updateExternalProviderConfig`,
  `listExternalProvidersAdmin`, `deleteExternalProvider`,
  `getOAuthClientPublicInfo`, `authorizeOAuthClient`, `revokeConnectedApp`,
  `createOAuthClient`, `listOAuthClients`, `deleteOAuthClient`) — voir "IAM
  requis" plus bas.
- Tu disposes d'un compte administrateur Planerz (`isApplicationOwner: true`)
  sur le projet Firebase concerné.

## Étape 1 — S'enregistrer comme client chez le fournisseur

Avant toute manipulation côté Planerz, va sur la console développeur du
fournisseur (ex. Ridgegear, une fois qu'elle existera) et enregistre
"Planerz" comme application autorisée. Renseigne comme redirect URI :

    https://<domaine-planerz>/external/callback

Le fournisseur te délivre alors :

- un `client_id`
- un `client_secret`

Note aussi, depuis sa documentation :

- l'URL d'autorisation (`authorizeUrl`)
- l'URL d'échange de jeton (`tokenUrl`)
- la ou les portées (`scope`) à demander (ex. `gear.read`)

### Trouver `tokenUrl` quand le fournisseur est lui-même en Cloud Functions v2

Si le fournisseur expose son endpoint `/oauth/token` via une Cloud Function
Gen2 (cas de Ridgegear, qui réutilise le même sous-module
`oauth-provider-core` que Planerz), l'URL n'est pas prévisible à l'avance :
Cloud Functions v2 génère une URL Cloud Run avec un hash aléatoire,
déterminé seulement après le déploiement. Récupère-la avec :

```powershell
gcloud functions describe publicApi --region=europe-west9 --project=<project-id-du-fournisseur> --gen2 --format="value(serviceConfig.uri)"
```

(remplacer `publicApi` par le nom réel de la fonction côté fournisseur si
différent). `tokenUrl` = cette URL + `/oauth/token`.

Pour Ridgegear précisément, ces deux URLs sont déjà connues et stables (le
hash Cloud Run ne change pas tant que la fonction n'est pas supprimée et
recréée) — pas besoin de refaire cette manip, utilise directement les
valeurs de l'étape 2 ci-dessous.

## Étape 2 — Enregistrer le fournisseur dans Planerz

Administration → "Fournisseurs externes (OAuth)" → icône "+".

| Champ                | Exemple (Ridgegear)                            |
|-----------------------|-------------------------------------------------|
| `providerId`          | `ridgegear` (minuscules, chiffres, tirets)       |
| Nom affiché            | `Ridgegear`                                      |
| URL de l'icône         | URL de l'icône Ridgegear                         |
| URL d'autorisation     | `https://ridgegear.centuryspine.org/oauth/authorize` |
| URL de jeton           | `https://publicapi-w2qekjkc6q-od.a.run.app/oauth/token` |
| Portée                | `gear.read`                                      |
| `client_id`           | celui délivré par Ridgegear                      |
| `client_secret`       | celui délivré par Ridgegear                      |

Valide. C'est tout — **aucune commande, aucun redéploiement**. Le secret est
écrit directement dans Secret Manager par l'écran lui-même (jamais stocké en
clair dans Firestore) ; le fournisseur apparaît immédiatement dans l'écran
"Comptes externes connectés" de tous les utilisateurs.

## IAM requis

### Secret Manager (côté Planerz-en-tant-que-client uniquement)

Le `client_secret` de chaque fournisseur est écrit par
`createExternalProvider` dans Google Secret Manager (jamais en clair dans
Firestore), sous l'id `extprov-<providerId>-client-secret`. Le compte de
service par défaut des Cloud Functions (`roles/editor` au niveau projet)
**suffit pour créer/écrire** un secret, mais **pas pour le lire** :
`roles/editor` exclut délibérément `secretmanager.versions.access`. Sans le
grant ci-dessous, la création du fournisseur dans l'admin semble réussir,
l'écran de consentement s'affiche normalement, mais le retour du callback
échoue avec :

```
Erreur : [firebase_functions/failed-precondition]
Configuration du fournisseur incomplète
```

Retrouve d'abord le compte de service utilisé par les fonctions du projet :

```powershell
gcloud functions describe completeExternalConnection --project=<project-id> --region=europe-west9 --gen2 --format="value(serviceConfig.serviceAccountEmail)"
```

Puis accorde l'accès en lecture. Au niveau du secret (scoppé, à refaire par
fournisseur) :

```powershell
gcloud secrets add-iam-policy-binding extprov-<providerId>-client-secret --project=<project-id> --member="serviceAccount:<compte-de-service>" --role="roles/secretmanager.secretAccessor"
```

Ou, une seule fois pour tout le projet (recommandé, évite de refaire ce
binding à chaque nouveau fournisseur) :

```powershell
gcloud projects add-iam-policy-binding <project-id> --member="serviceAccount:<compte-de-service>" --role="roles/secretmanager.secretAccessor"
```

Pour diagnostiquer un doute sur un secret existant :

```powershell
# Le secret et sa dernière version existent-ils bien ?
gcloud secrets versions list extprov-<providerId>-client-secret --project=<project-id>

# Des bindings IAM sont-ils posés directement sur ce secret ?
gcloud secrets get-iam-policy extprov-<providerId>-client-secret --project=<project-id>

# Le compte de service a-t-il le rôle au niveau projet ?
gcloud projects get-iam-policy <project-id> --flatten="bindings[].members" --filter="bindings.members:<compte-de-service>" --format="table(bindings.role)"
```

### Cloud Run invoker (toutes les fonctions du flow, obligatoire)

Règle projet standard, à répéter pour chaque fonction listée dans les
"Prérequis techniques" ci-dessus, nom de fonction en minuscules :

```powershell
gcloud run services get-iam-policy <nom-fonction-minuscule> --region=europe-west9 --project=<project-id>
```

Si `allUsers` / `roles/run.invoker` manque :

```powershell
gcloud run services add-iam-policy-binding <nom-fonction-minuscule> --region=europe-west9 --project=<project-id> --member=allUsers --role=roles/run.invoker
```

## Vérifier que ça marche

Depuis un compte utilisateur (pas admin) : Compte → "Comptes externes
connectés" → "Connecter" en face du fournisseur. Tu dois être redirigé vers
son écran de consentement, puis revenir sur Planerz avec la connexion
affichée comme active.

## Faire tourner le secret d'un fournisseur

Si le `client_secret` doit être renouvelé côté fournisseur, il n'y a pas
besoin de supprimer/recréer le fournisseur : une action dédiée
("Régénérer le secret", callable `updateExternalProviderSecret`) permet de
le remplacer en place. (Pas encore d'entrée dédiée dans l'écran admin au
premier jet — à ajouter si le besoin se présente ; la callable existe déjà.)

## Limites connues (fournisseur externe, sens client)

- Révoquer la connexion côté Planerz ne révoque pas forcément le jeton côté
  du fournisseur (dépend de si celui-ci expose sa propre révocation).
- Changer l'URL de callback Planerz après coup oblige à se ré-enregistrer
  chez chaque fournisseur déjà connecté.
- Supprimer un fournisseur (bouton corbeille dans l'admin) ne révoque pas
  automatiquement les connexions déjà établies par les utilisateurs.

---

# Déclarer une application tierce (Planerz-en-tant-que-fournisseur)

Procédure pour autoriser une appli tierce (ex. Ridgegear) à lire les trips
d'un utilisateur Planerz via l'API publique, avec son consentement explicite.

Planerz sert ici de fournisseur OAuth via le sous-module partagé
`functions/vendor/oauth-provider-core` (voir son propre README pour le
contrat réutilisable) ; la seule partie spécifique à Planerz est le contrôle
d'accès admin (`isApplicationOwner`) et les noms des callables exposés,
gérés par [`oauth_authorize.js`](../functions/oauth_authorize.js).

## Étape 1 — Enregistrer l'appli tierce dans Planerz

Administration → "Applications tierces (OAuth)" → icône "+".

| Champ                | Exemple (Ridgegear)                                      |
|-----------------------|------------------------------------------------------------|
| `client_id`            | `ridgegear` (technique, choisi par toi)                   |
| Nom affiché             | `Ridgegear`                                                |
| URL de l'icône          | URL de l'icône Ridgegear (affichée sur l'écran de consentement) |
| Redirect URI autorisée  | `https://ridgegear.example.com/api/planerz/callback`      |

Valide. Le `client_secret` est généré côté serveur et **affiché une seule
fois** dans la boîte de dialogue qui suit — copie-le immédiatement (bouton
"Copier") et transmets-le à l'équipe de l'appli tierce par un canal sûr : il
n'est jamais réaffichable ensuite. Les portées (`scopesAllowed`) sont fixées
en dur à `['trips.read']` pour ce premier jet — pas d'écran pour en ajouter
d'autres tant qu'aucun besoin ne se présente.

## Étape 2 — Ce que fait l'appli tierce avec ce `client_id`/`client_secret`

1. Elle redirige l'utilisateur vers l'écran de consentement Planerz
   (`authorizeOAuthClient`, page [oauth_authorize_page.dart](../lib/features/oauth/presentation/oauth_authorize_page.dart))
   avec son `client_id` et sa `redirect_uri`.
2. L'utilisateur valide (ou refuse) depuis son compte Planerz.
3. Planerz redirige vers la `redirect_uri` de l'appli tierce avec un `code`.
4. L'appli tierce échange ce `code` contre un `access_token` via
   `POST <URL de la fonction publicApi>/oauth/token` (échange
   serveur-à-serveur, RFC 6749 `authorization_code`).
5. Elle appelle ensuite `GET <URL de la fonction publicApi>/v1/trips` avec
   `Authorization: Bearer <access_token>` pour lire les trips non archivés
   de l'utilisateur (voir [public_api.js](../functions/public_api.js)).

L'URL de la fonction `publicApi` se récupère comme n'importe quelle fonction
Gen2 (hash Cloud Run non prévisible avant déploiement) :

```powershell
gcloud functions describe publicApi --region=europe-west9 --project=<project-id> --gen2 --format="value(serviceConfig.uri)"
```

## Ce que voit l'utilisateur final

Compte → "Comptes connectés"
([connected_apps_page.dart](../lib/features/account/presentation/connected_apps_page.dart)) :
liste des applications tierces auxquelles il a donné son consentement,
possibilité de révoquer (`revokeConnectedApp`).

## Limites connues (application tierce, sens fournisseur)

- Une seule portée possible aujourd'hui (`trips.read`) — pas d'écran pour en
  déclarer d'autres par appli tierce ; à ajouter si le besoin se présente.
- Supprimer une application tierce (bouton corbeille dans l'admin) invalide
  ses jetons futurs mais ne force pas la révocation immédiate d'un jeton déjà
  émis et non expiré côté appli tierce.
- Le `client_secret` n'étant affiché qu'une fois, le perdre oblige à
  supprimer puis recréer l'application tierce (nouveau `client_id` à
  retransmettre), il n'y a pas d'action "régénérer le secret" pour ce sens
  (contrairement au fournisseur externe, voir "Faire tourner le secret d'un
  fournisseur" plus haut).
