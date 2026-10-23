# Version 0.5.2

## Améliorations pour les utilisateurs

### Activities

- **Photos partagées avec le groupe** — Les photos d’une activité sont désormais visibles par tous les participants du voyage : les siennes d’abord, puis celles des autres, entourées de couleur. Une nouvelle photo est partagée par défaut, et un cadenas permet de la rendre privée à tout moment. Les photos ajoutées avant cette version restent privées.
- **Photos des autres en plein écran** — Le nom de l’auteur et sa légende s’affichent. On peut choisir la photo comme favorite de l’activité, qui apparaît alors sur la carte du voyage, ou la signaler.
- **Signaler une photo** — Trois motifs au choix ; la photo disparaît aussitôt pour la personne qui la signale.

---

## Détails complémentaires (technique et exploitation)

### Modération

- **Signalements réservés à l’administration** — Seul l’administrateur de l’application voit les signalements, dans la section Administration : une entrée par photo avec le nombre de signalements et une alerte à partir de 3, l’historique de leur traitement (ignoré, photo retirée) et une vue par signaleur pour repérer les signalements abusifs. Les admins du voyage peuvent supprimer une photo partagée depuis son affichage en plein écran.

### Conservation des données

- **Favorites** — Le choix des photos favorites suit les mêmes règles de conservation que les photos.

### Exploitation

- **Règles Firestore** — Partage des photos, favorites et signalements (à déployer en production).
- **Cloud Functions** — `leaveTrip`, `removeTripParticipant`, `removeTripRegisteredMember` et `runDailyTripLifecycle` sont à redéployer.
