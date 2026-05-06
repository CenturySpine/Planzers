# Notes de version — v0.2.0-beta3

> Période couverte : v0.2.0-beta2 → v0.2.0-beta3

---

## 1) Priorité utilisateurs (par domaine métier)

### Voyages

- **Création de voyage repensée** : la création passe par une page dédiée et impose des bornes de séjour précises (jour de début et jour de fin, avec partie de journée). Le même contrôle est utilisé partout — création, rejoindre un voyage, préférences de séjour personnel et modification depuis l’aperçu — pour une expérience cohérente.
- **Covoiturage, nouvelle section dédiée au voyage** :
  - liste des trajets partagés, avec le trajet du voyageur connecté épinglé en tête et mis en évidence ;
  - rejoindre ou quitter une voiture en un geste, sans passer par un administrateur ;
  - point de rendez-vous "courses" mis en avant pour les équipages concernés ;
  - résumé adapté au rôle de chacun (conducteur, passager, en attente d’affectation) directement sur l’aperçu du voyage ;
  - un bandeau guide les membres qui ne sont rattachés à aucune voiture ;
  - les administrateurs ajustent les permissions de covoiturage depuis les réglages du voyage.
- **Jeux de société, nouvelle page dédiée** : consultation et complément de la liste collective avec édition selon les permissions. Le pavé "Jeux" de l’aperçu affiche désormais le nombre de jeux et un aperçu des titres ajoutés.
- **Liste des voyages plus claire** : un unique bouton d’action ouvre des choix explicites (créer un voyage, rejoindre un voyage), à la place du double bouton flottant. Les textes d’invitation ont été simplifiés.
- **Gestion du voyage rationalisée** :
  - la suppression du voyage est regroupée dans le menu de l’aperçu ;
  - l’action "quitter le voyage" est déplacée dans les préférences de membre, avec un message de confirmation plus clair et masquée pour le créateur ;
  - retour à un défilement plein écran sur l’aperçu (pas de bascule par onglet).

### Messagerie

- Aucun changement fonctionnel dans cette version.

### Activités

- **Vote ouvert à tous les membres** : la participation aux votes d’activités ne dépend plus de la permission de proposer une activité.
- **Suggestions plus puissantes** : le panneau de suggestions peut filtrer sur plusieurs catégories à la fois, et les cartes d’activité sont identiques entre l’aperçu du voyage et la planification.
- **Onglet hébergement dans l’aperçu** : un onglet de suggestions d’hébergement est désormais disponible directement depuis l’aperçu du voyage.

### Dépenses

- Aucun changement fonctionnel dans cette version.

### Repas

- **Suggestions de restaurants alignées sur les activités** : en mode restaurant, le panneau de suggestions s’appuie sur les activités de catégorie "Restaurant", avec la même expérience que les autres activités. La permission spécifique "suggérer un restaurant" disparaît au profit de la permission "suggérer une activité".

---

## 2) Détails complémentaires (technique / exploitation)

- **Sécurité Firestore renforcée** :
  - écritures sur la section covoiturage limitées au créateur du trajet ou aux rôles autorisés ;
  - écritures client bloquées sur les aperçus de jeux de société ;
  - permissions ciblées maintenues pour les actions légitimes des proposants.
- **Cloud Functions (Gen2, region `europe-west9`)** :
  - prise et libération de place passager traitées côté serveur via des callables authentifiés (plus d’écriture directe par le client) ;
  - contrôles d’intégrité sur les données covoiturage (places disponibles, identifiants véhicule, cohérence des entrées) ;
  - helpers de parsing des timestamps mutualisés et logique serveur consolidée pour une maintenance plus fiable.
- **Préproduction / exploitation** :
  - l’application preview peut cibler la Firebase Emulator Suite (Auth, Firestore, Functions, Storage) via un drapeau de compilation, pour les validations internes.
- **Divers dépôt** :
  - nettoyage de `.gitignore` ;
  - publication de la version applicative `0.2.0-beta3+8`.
