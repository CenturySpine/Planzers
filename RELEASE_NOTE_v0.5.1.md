# Version 0.5.1

## Améliorations pour les utilisateurs

### Activities

- **Mes photos** — Sur la fiche d’une activité planifiée, chaque voyageur ajoute ses propres photos : 10 au maximum par jour, toutes activités de la journée confondues, réduites sur le téléphone avant l’envoi. Pour l’instant, chacun ne voit que les siennes. Les photos suivent leur activité : si elle change de jour, elles comptent sur sa nouvelle journée.
- **Plein écran** — Les photos s’ouvrent en plein écran avec zoom ; on passe de l’une à l’autre d’un simple balayage (ou en les faisant glisser à la souris sur ordinateur).
- **Légendes** — Chaque photo peut recevoir une légende de 500 caractères au plus, affichée sous la photo en plein écran.
- **Photo favorite sur la carte** — Une photo par activité peut être marquée comme favorite : sur la carte du voyage, la pastille du lieu montre alors cette photo, le numéro de l’étape restant visible dans un coin.

---

## Détails complémentaires (technique et exploitation)

### Conservation des données

- **Mêmes règles que « Mes documents »** — Les photos sont supprimées quand le voyageur quitte le voyage ou en est retiré, quand le voyage est supprimé, et 60 jours après la fin du voyage. Supprimer une activité supprime ses photos pour tous les voyageurs, et un admin du voyage peut supprimer n’importe quelle photo.

### Exploitation

- **Règles Firestore et Storage** — Nouvelles règles pour les photos des activités (à déployer en production).
- **Cloud Functions** — Deux nouvelles fonctions de nettoyage des photos ; `leaveTrip`, `removeTripParticipant`, `removeTripRegisteredMember`, `deleteTripCascade` et `runDailyTripLifecycle` sont à redéployer.
- **Compte de service de déploiement** — Le rôle « Administrateur Cloud Scheduler » est nécessaire pour redéployer une fonction planifiée comme `runDailyTripLifecycle`.
