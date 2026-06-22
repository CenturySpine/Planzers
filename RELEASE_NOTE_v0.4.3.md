# Version 0.4.3

## Améliorations pour les utilisateurs

### Trip

- **Refonte visuelle Néon** — Le parcours voyage adopte la nouvelle charte graphique : liste « Mes voyages », barre de navigation du voyage, aperçu, participants, création et édition, préférences personnelles, informations de voyage des participants, et parcours d’invitation. Typographie Geist intégrée à l’application pour un rendu homogène, y compris hors ligne.
- **Sorties à la journée** — Un voyage peut être créé en mode « À la journée » : destination, hébergement et plages multi-jours sont masqués ; la création, l’aperçu, l’invitation et les préférences participant s’adaptent en conséquence.
- **Codes d’invitation simplifiés** — Les nouveaux voyages reçoivent un code au format `ABC-123`. La saisie par code propose six cases dédiées, le collage en un geste, et des libellés qui indiquent clairement qu’il faut le code (pas le lien d’invitation).
- **Invitation repensée** — Rejoindre un voyage via invitation offre une expérience plus claire : sélection des participants, édition des dates de séjour, et synchronisation des séjours lorsque l’organisateur modifie les dates ou bascule entre sortie à la journée et séjour multi-jours.
- **Création et édition enrichies** — Photo de couverture, plages de repas, description, lien hébergement, mode Cupidon et lien photo stockage sont regroupés dans le formulaire de création ou d’édition. L’édition depuis l’aperçu ouvre ce même écran. Le nom affiché à l’inscription peut reprendre le surnom du profil ou un nom personnalisé.
- **Paramètres du voyage** — Les réglages généraux ne sont plus sur un écran séparé : ils figurent dans le formulaire voyage. L’entrée « Paramètres » devient **Permissions**.
- **Participants** — Les gestionnaires accèdent à une page dédiée pour modifier le nom affiché et les dates de présence d’un participant ; chaque voyageur gère son propre nom depuis ses préférences. Les icônes modifier et supprimer n’apparaissent que selon les droits (jamais sur l’organisateur ni sur soi-même pour la suppression).

### Games

- **Jeux de société** — La liste des jeux suit la charte Néon : encart d’introduction, recherche, cartes avec aperçu des liens, et dialogues d’ajout ou d’édition alignés sur le nouveau design.

---

## Détails complémentaires (technique et exploitation)

### Compte

- Refonte de la page profil (en-tête, cartes groupées, parcours d’édition et de photo) selon le handoff Néon.

### Trip — données et déploiements

- Nouveau champ `isDayTrip` sur le document voyage ; `startDate` et `endDate` forcés au même jour en mode journée.
- **Déploiements requis** après mise à jour :
  - `firebase deploy --only functions:getInviteJoinContext --project <preview|prod>`
  - `firebase deploy --only firestore:rules --project <preview|prod>`
- Script de migration Firestore pour convertir les anciens codes d’invitation au format `XXX-XXX` (mode dry-run / `--apply`, gestion des collisions) — à exécuter par le PO si des voyages existants conservent d’anciens tokens.

### Android

- Retrait du bouton de désinstallation sur l’écran de bascule web (sans effet sur appareil) ; le message d’orientation vers le navigateur est conservé.

### Index Firestore

- Synchronisation du fichier d’index local avec l’état Firebase (champ `__name__` manquant sur les index `messages`, source de conflits 409 au déploiement).

### Documentation

- Charte UI transversale (`DESIGN_CHARTER.md`) consolidée à partir des handoffs Néon, avec journal des arbitrages documentés.
