# Version 0.5.0

## Améliorations pour les utilisateurs

### Activities

- **Lieux précis** — Chaque activité peut être placée exactement : recherche d’un lieu par son nom, repère posé sur une carte OpenStreetMap (même pour un lieu isolé sans adresse), « Ma position », ou coordonnées GPS et liens Google Maps, Apple Maps ou OpenStreetMap collés. La fiche affiche une mini-carte qui ouvre l’itinéraire dans Google Maps ou Waze, et les activités plus anciennes se localisent en un geste.
- **Lieux récents** — Les lieux déjà utilisés dans le voyage sont proposés en premier au moment de choisir un lieu.
- **Carte du voyage** — Depuis le Planning, une carte retrace le voyage : étapes numérotées dans l’ordre, trajets du départ à l’arrivée (en pointillés pour l’avion), filtre par jour, et ajout d’une activité par appui long sur la carte.
- **Trajets proposés** — Entre deux lieux distants de plus d’un kilomètre sans trajet prévu, l’agenda et la carte proposent un trajet : choisir le mode (à pied, vélo, voiture, bus, train, avion, bateau, autre) suffit pour l’ajouter, avec des horaires calés sur les activités voisines. Les trajets ne se saisissent plus à la main depuis le Planning ; les billets du portefeuille créent toujours le leur.
- **Dupliquer une activité** — Une activité se copie depuis sa fiche ; la copie s’ouvre aussitôt pour en changer la date.

### Meals

- **Restaurants toujours disponibles** — Un restaurant reste proposé dans les suggestions et pour les repas même s’il a reçu une date, et la création d’un restaurant ne propose plus de date.

---

## Détails complémentaires (technique et exploitation)

### Application web

- **Nouvelle version dès le premier lancement** — Sur une connexion mobile lente, la nouvelle version de l’application s’affiche dès le premier lancement qui suit une mise à jour, au lieu de l’ancienne copie gardée pour le mode hors ligne.

### Exploitation

- **Déploiement des règles Firebase** — Nouveau workflow GitHub Actions : règles Firestore, index et règles Storage sont déployés automatiquement en preview à chaque changement sur `develop`, et à la main depuis `main` pour la production.
- **Règles Firestore** — Validation du format des positions GPS et du mode de transport des activités (à déployer en production).

### Confidentialité

- **Politique de confidentialité** — Ajout des services de cartes et de recherche de lieux (fondation OpenStreetMap, komoot / Photon) et des lieux enregistrés avec les activités.
