# Version 0.6.0

## Améliorations pour les utilisateurs

### Repas

- **Choisir le restaurant d’un repas** — En mode Restaurant, le repas affiche le restaurant retenu, avec « Changer » et « Retirer », ou un bouton « Choisir un restaurant ». Le choix se fait dans la liste des restaurants proposés pour le voyage, les plus votés en tête ; « Nouveau restaurant » permet d’en ajouter un, aussitôt relié au repas.
- **Un choix fiable** — Le restaurant choisi en créant un repas est bien enregistré, tous les participants voient le restaurant retenu, et la carte du repas indique « Restaurant à choisir » tant qu’aucun n’est choisi. Le nom affiché suit les modifications du restaurant.
- **Photos de repas** — On peut ajouter des photos à un repas, comme à une activité : privées ou partagées avec le groupe, légende, favorite, signalement. Elles comptent dans la même limite quotidienne que les photos d’activités.

### Carte du voyage

- **Les repas au restaurant sur la carte** — Un repas dont le restaurant a un lieu apparaît comme une étape numérotée, à l’heure du repas, avec sa photo favorite (ou à défaut celle du restaurant). Le toucher ouvre le repas.
- **Transports à prévoir** — Les trajets suggérés entre deux lieux éloignés tiennent compte de ces restaurants, sur la carte comme dans l’agenda.

---

## Détails complémentaires (technique et exploitation)

### Permissions

- **Choisir le restaurant d’un repas** — Nouvelle ligne dans les permissions des repas (par défaut : administrateurs du voyage) pour décider qui peut choisir, changer ou retirer le restaurant.

### Photos

- **Limite quotidienne** — 15 photos par jour pour l’administrateur de l’application, 10 pour les autres participants.
- **Suppression et transfert** — Supprimer un repas supprime ses photos ; l’export / import de voyage reprend les photos de repas.

### Restaurants

- **Suppression** — Seul un repas encore en mode Restaurant empêche de supprimer le restaurant qu’il a choisi.

### Exploitation

- **Règles Firestore** — Photos rattachées à un repas (à déployer en production).
- **Cloud Functions** — `deleteMealPhotosOnMealDeleted` (nouvelle), `exportTrip` et `importTrip` sont à déployer.
