# Release Notes — v0.3.7

## Pour les utilisateurs

Cette version lève l’écran de maintenance de la v0.3.6 et déploie le nouveau système de participants sur l’ensemble de l’application.

### Voyage

- **Participants unifiés :** les voyageurs prévus et les membres inscrits sont gérés dans une seule liste ; les droits de gestion des participants sont regroupés sous une permission dédiée.
- **Nom d’affichage obligatoire :** à la connexion et lors d’une invitation hors liste invités, chacun doit choisir ou confirmer un nom d’affichage avant d’accéder au voyage.
- **Modifier son nom :** tout membre peut mettre à jour son propre nom d’affichage ; les responsables peuvent renommer les voyageurs prévus ou inscrits via une boîte de dialogue commune (profil du compte ou nom saisi pour le voyage).
- **Pseudo cohérent :** le nom affiché dans les listes, badges et écrans du voyage reflète le profil ou le nom choisi pour ce voyage, selon la source retenue.
- **Création de voyage :** le créateur est initialisé comme participant avec des valeurs par défaut complètes (dates de séjour, etc.).
- **Propriétaires de l’application :** possibilité d’afficher tous les voyages et de gérer les participants sur n’importe quel voyage ; le sélecteur de liste utilise le rendu Material attendu sur le web.

### Liste de courses

- **Réclamation obligatoire :** seul le participant qui a réclamé un article peut le cocher ou le décocher.
- **Filtre par réclamation :** filtre combinable pour n’afficher que les articles réclamés (ou l’inverse), en plus des filtres de statut existants.

### Repas

- **Sélection des participants :** la présélection automatique des participants dans les formulaires de repas fonctionne à nouveau après la refonte.
- **Recettes du chef :** l’édition des recettes associées à un repas est de nouveau disponible.

### Notes de frais

- **Visibilité et formulaires :** les groupes par défaut, les listes de participants et la visibilité des publications s’appuient sur l’identifiant participant (et non plus uniquement sur le compte Firebase) ; tous les participants apparaissent dans le formulaire de dépense, qu’ils aient réclamé un compte ou non.
- **Nouveau voyageur :** un participant ajouté récemment n’est visible que sur la publication de frais par défaut tant qu’il n’est pas intégré aux autres groupes.

### Covoiturage

- **Assignations :** conducteurs, passagers et étapes du covoiturage sont liés aux participants du voyage (voyageurs prévus ou inscrits), ce qui aligne le covoiturage avec le reste de l’application.

### Chambres

- **Vue d’ensemble :** la chambre assignée à un participant s’affiche à nouveau correctement sur la page d’aperçu du voyage.

### Jeux

- **Cupidon :** correction du lien « j’aime » vers un autre membre du voyage.

---

## Détails complémentaires (technique et exploitation)

### Fin de la maintenance v0.3.6

- L’écran de blocage client (`kMaintenanceMode`) est retiré ; l’application est à nouveau utilisable normalement après migration des données.

### Administration

- **Mode maintenance piloté par Firestore :** entrée depuis l’espace d’administration pour activer ou désactiver la maintenance sans redéployer l’application.
- **Scripts de migration (à lancer manuellement par l’exploitant, jamais avec `--apply` par un agent) :**
  - Phase 1 : migration des participants (membres → participants) ; blocage si incohérences détectées avant écriture.
  - Phase 2 : migration des identifiants participant dans les sections concernées (dont covoiturage) et recalcul du nombre de participants par voyage.
  - Script de purge des utilisateurs placeholder `ph_`.
  - Rapport lecture seule de régularisation des notes de frais par voyage.
- **Déploiement Firebase :** règles Firestore, index et Cloud Functions doivent être alignés sur `planerz` (prod) après merge sur `main`, conformément à [`RELEASE.md`](RELEASE.md).

### Compte et authentification

- Le profil compte n’est plus écrasé automatiquement par le nom fourni à la connexion Google ; la connexion par téléphone conserve les données du profil existant.

### Voyage (correctifs complémentaires)

- Redirection de tous les participants vers la liste des voyages lorsqu’un voyage est supprimé.
- Formulaire de séjour et d’options à l’invitation même lorsque le voyage n’a encore aucun participant.
- Dates de séjour par défaut corrigées lors de l’ajout d’un voyageur prévu.

### Développement web local

- Port fixe **47432** documenté dans [`RELEASE.md`](RELEASE.md) ; configuration CORS Storage mise à jour pour `localhost:47432` sur les buckets preview et prod.
