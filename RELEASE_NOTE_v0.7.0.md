# Version 0.7.0

## Améliorations pour les utilisateurs

### Créer un voyage à partir d’un modèle

- **Quatre modèles** — La création d’un voyage commence par le choix de son type : Séjour entre amis, Voyage itinérant, Voyage organisé ou Sortie à la journée. Chaque carte présente le modèle en une phrase ; une fois choisie, elle détaille ce qu’il permet et les modules qu’il active.
- **Un formulaire prérempli** — Le voyage s’ouvre avec les modules du modèle, l’option « à la journée » et la façon de renseigner les hébergements (le même pour toutes les nuits, ou nuit par nuit). « Changer » ramène aux modèles tant que le voyage n’est pas créé, sans perdre ce qui a été saisi. Tout reste modifiable ensuite.
- **Voyage organisé** — L’organisateur prépare le programme, les étapes, les hébergements, les chambres et les dates de chacun ; les voyageurs consultent le programme et la carte, ajoutent leurs photos et partagent leurs dépenses entre eux. Seul l’organisateur invite de nouveaux voyageurs.

### Des modules pour n’afficher que l’utile

- **Itinéraire** — La carte du voyage, les nuits dans l’agenda, les trajets à prévoir et les correspondances. Sans lui, le planning n’affiche plus le bouton de la carte ni les filtres « Nuits » et « Trajets ».
- **Repas maison** — Les repas cuisinés et les auberges espagnoles, avec recettes et contributions, et le matin / midi / soir des dates de présence. Sans lui, un nouveau repas est un repas au restaurant et les dates de présence se saisissent en journées complètes. Les restaurants se proposent, se votent et se planifient toujours, et apparaissent sur la carte.
- **Courses** — La liste de courses commune. Sans elle, l’onglet Courses et la partie courses du covoiturage disparaissent.
- **Où les régler** — Dans le formulaire du voyage et dans « + Ajouter un module », comme les chambres, le covoiturage ou les jeux.

### Navigation

- **Le 5e onglet** — La barre du bas propose les Courses, ou à défaut la carte du voyage, qui devient un onglet à part entière. Sans l’un ni l’autre, l’emplacement reste vide et Planning reste au centre.
- **Filtres du planning** — Quand ils tiennent sur la ligne, les filtres se répartissent sur toute la largeur.

### Une interface allégée

- **Suggestions** — L’onglet n’apparaît qu’à ceux qui peuvent proposer des activités.
- **Code d’invitation** — Il n’apparaît sur l’aperçu qu’à ceux qui peuvent partager le voyage.
- **Nuits des chambres** — Les pastilles des nuits n’apparaissent que lorsqu’une nuit est personnalisée ; « Personnaliser une nuit » les fait apparaître.

---

## Détails complémentaires (technique et exploitation)

### Permissions

- **Gérer les chambres** — Nouvelle permission (par défaut : participants) pour créer, modifier et supprimer les chambres et répartir les lits. Sans elle, la page des chambres est en lecture seule. Elle est désormais vérifiée par les règles Firestore.
- **Modifier ses dates de présence** — Nouvelle ligne dans les permissions des participants (par défaut : participants). Quand elle est réservée aux administrateurs, le voyageur garde les dates fixées par l’organisateur, y compris en rejoignant le voyage ; l’organisateur modifie toujours celles de chacun avec « Gérer les participants ».
- **Modules désactivés** — Leurs permissions ne sont plus proposées.
- **Voyage organisé** — Tout est réservé aux administrateurs, sauf les dépenses et ce qui appartient déjà au créateur du voyage.

### Voyages existants

- **Aucun changement** — Ils gardent tous leurs modules et les nouvelles permissions restent ouvertes aux participants ; aucune migration de données.
- **Désactiver Repas maison** — Les bornes de repas déjà saisies sont conservées, sans être réécrites.

### Exploitation

- **Règles Firestore** — Nouveaux modules du voyage et permission des chambres (à déployer en production).
- **Cloud Functions** — `updateParticipantProfile` et `getInviteJoinContext` sont à déployer.
