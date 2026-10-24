# Version 0.5.3

## Améliorations pour les utilisateurs

### Navigation

- **Passer d’un voyage à l’autre** — En ouvrant directement un autre voyage (notification, lien), les écrans n’affichent plus d’informations du voyage précédent : le code de partage affiché et copié est bien celui du voyage ouvert, et les onglets ne ramènent plus dans l’autre voyage.

---

## Détails complémentaires (technique et exploitation)

### Administration

- **Export / import de voyages** — Réservé à l’administrateur de l’application. Un voyage s’exporte depuis ses réglages en fichier JSON et s’importe depuis la liste des voyages comme un nouveau voyage, marqué « (export) », avec son propre code de partage. L’import n’accepte qu’un fichier exporté depuis la même version de l’application (usage prévu : passer un voyage de la préproduction à la production).
- **Ce qui est repris** — Le contenu partagé du voyage (planning, repas, courses, chambres, covoiturages, jeux, dépenses et remboursements, annonces, réglages, bannière, photos partagées) et les données privées de l’administrateur (documents, photos, favorites, liste « À emporter », modules). Les comptes ne suivent pas : l’administrateur reprend sa place, les autres participants réclament la leur avec le code de partage. Messagerie, Cupidon et données privées des autres participants ne sont pas repris.
- **Journaux des transferts** — Chaque export ou import laisse un journal détaillé, consultable, copiable et supprimable dans la section Administration.

### Exploitation

- **Cloud Functions** — `exportTrip` et `importTrip` (nouvelles) sont à déployer.
- **Règles Firestore et Storage** — Journaux des transferts et dossier de transit des fichiers (à déployer en production).
