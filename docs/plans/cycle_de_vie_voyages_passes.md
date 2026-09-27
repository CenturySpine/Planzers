# Cycle de vie des voyages passés — archivage et suppression des documents

## Règles (validées avec le product owner)

Pour **chaque membre** d'un voyage, en jours calendaires comptés depuis le
dernier jour du voyage (date de fin, sinon date de début ; sans date :
rien d'automatique) :

- **J+30 — archivage automatique** pour tous les membres qui ne l'ont pas
  déjà archivé (l'archivage reste propre à chaque utilisateur :
  `users/{uid}/archivedTrips/{tripId}`, marqué `auto: true`). Il n'a lieu
  **qu'une fois** : un membre qui désarchive ensuite n'est pas réarchivé.
- **J+60 — suppression des documents personnels** (« Mes documents ») de
  tous les voyageurs du voyage, fiches et fichiers, **indépendamment de
  l'archivage**. Les copies hors connexion disparaissent à la synchronisation
  suivante de l'app.

## Interface

- Aperçu d'un voyage passé non archivé par le membre : encart
  « Ce voyage sera archivé automatiquement dans X jours. »
- « Mes documents » d'un voyage terminé : encart d'avertissement
  « Le voyage est terminé : tes documents seront supprimés automatiquement
  dans X jours. » ; le bouton `+` disparaît à J+60.

## Serveur

- `functions/trip_lifecycle.js` + tests ; fonction planifiée
  `runDailyTripLifecycle` (chaque nuit à 03:30, Europe/Paris).
- **Région `europe-west1`** : Cloud Scheduler n'existe pas en
  `europe-west9` (même exception que `cleanupOrphanAdminAnnouncementDismisses`).
- Voyages traités : fin entre J-151 et J-29 (rattrape ~3 mois de passages
  manqués). Avancement enregistré dans `tripLifecycle/{tripId}` (serveur
  uniquement, supprimé avec le voyage) ; une suppression en échec est
  retentée le lendemain.
- Les voyageurs qui ont des données de modules personnels sans être (encore)
  membres sont aussi couverts par la suppression.

## Hors périmètre

- Notification avant suppression (à envisager).
