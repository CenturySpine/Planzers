# Ajouter un fournisseur externe (OAuth)

Procédure pour connecter Planerz à un nouveau fournisseur de l'écosystème
(ex. Ridgegear), afin que les utilisateurs puissent lier leur compte.

## Prérequis (une seule fois pour tout le projet, pas par fournisseur)

- Le provisionnement IAM Secret Manager a été fait sur le projet Firebase
  (permission de création/écriture de secrets accordée au compte de service
  des Cloud Functions — voir la section "Opérations manuelles" du chantier
  d'implémentation).
- Tu disposes d'un compte administrateur Planerz (`isApplicationOwner: true`).

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

```bash
gcloud functions describe publicApi --region=europe-west9 --project=<project-id-du-fournisseur> --gen2 --format="value(serviceConfig.uri)"
```

(remplacer `publicApi` par le nom réel de la fonction côté fournisseur si
différent). `tokenUrl` = cette URL + `/oauth/token`.

## Étape 2 — Enregistrer le fournisseur dans Planerz

Administration → "Fournisseurs externes (OAuth)" → icône "+".

| Champ                | Exemple (Ridgegear)                            |
|-----------------------|-------------------------------------------------|
| `providerId`          | `ridgegear` (minuscules, chiffres, tirets)       |
| Nom affiché            | `Ridgegear`                                      |
| URL de l'icône         | URL de l'icône Ridgegear                         |
| URL d'autorisation     | `https://ridgegear.example.com/oauth/authorize`  |
| URL de jeton           | `https://ridgegear.example.com/oauth/token`      |
| Portée                | `gear.read`                                      |
| `client_id`           | celui délivré par Ridgegear                      |
| `client_secret`       | celui délivré par Ridgegear                      |

Valide. C'est tout — **aucune commande, aucun redéploiement**. Le secret est
écrit directement dans Secret Manager par l'écran lui-même (jamais stocké en
clair dans Firestore) ; le fournisseur apparaît immédiatement dans l'écran
"Comptes externes connectés" de tous les utilisateurs.

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

## Limites connues

- Révoquer la connexion côté Planerz ne révoque pas forcément le jeton côté
  du fournisseur (dépend de si celui-ci expose sa propre révocation).
- Changer l'URL de callback Planerz après coup oblige à se ré-enregistrer
  chez chaque fournisseur déjà connecté.
- Supprimer un fournisseur (bouton corbeille dans l'admin) ne révoque pas
  automatiquement les connexions déjà établies par les utilisateurs.
