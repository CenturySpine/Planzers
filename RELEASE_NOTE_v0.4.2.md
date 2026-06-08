# Version 0.4.2

## Améliorations pour les utilisateurs

### Trip

- **Décommissionnement de l'application Android** — Les utilisateurs qui ouvrent l'APK Android voient désormais un écran les invitant à basculer vers l'application web Planerz. L'APK ne sera plus maintenu ni mis à jour ; l'expérience complète reste disponible depuis le navigateur.

### Messagerie

- La sélection d'un message se ferme automatiquement après l'ajout d'une réaction, évitant une étape manuelle superflue.
- Correction d'un bug rare où le tchat pouvait se recharger de façon inopinée au moment de l'envoi d'un message.
- Les images partagées dans le tchat sont désormais protégées contre les modifications non autorisées : seul l'auteur d'une image peut la remplacer ou la supprimer.

### Repas

- Le bouton de création de repas est désormais masqué pour les participants qui n'ont pas la permission de créer des repas (au lieu d'être visible puis refusé à l'action).

---

## Détails complémentaires (technique et exploitation)

### Notifications

- Le pipeline de distribution des notifications a été entièrement refactorisé autour d'une file d'attente idempotente sans verrous d'événement. Résultat : élimination des envois en double, meilleure résilience en cas d'erreur transitoire, et observabilité améliorée (logs structurés par étape).
- Correction d'un bug provoquant des notifications en double sur les navigateurs web (PWA).

### Messagerie — infrastructure

- Les requêtes du tchat voyage sont maintenant filtrées par portée (`threadType` / `visibilityType`), permettant de distinguer les messages globaux des messages contextuels (activités, repas, etc.).
- Les règles Storage pour les images du tchat ont été durcies : la métadonnée `authorId` est obligatoire à l'écriture, et les écrasements par un tiers sont bloqués.

### Participants

- Correction : le renommage d'un participant enregistré ne modifie plus incorrectement le champ `isChild`.
- Correction : les permissions des fonctions appelables pour la gestion des participants sont correctement alignées avec les règles produit.

### Index Firestore

- Ajout d'index COLLECTION_GROUP sur la collection `messages` (combinaisons `visibilityType`, `threadType`, `createdAt` ASC/DESC) — requis pour les nouvelles requêtes filtrées par portée.
