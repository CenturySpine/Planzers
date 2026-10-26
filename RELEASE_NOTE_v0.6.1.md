# Version 0.6.1

## Améliorations pour les utilisateurs

### Hébergements

- **Un hébergement par nuit** — Pour un voyage de plusieurs jours, on indique où l’on dort nuit par nuit : les nuits qui se suivent au même endroit forment une étape, avec son nom, son adresse et son lien. L’option « Même hébergement pour toutes les nuits » garde le cas simple et suit les dates du voyage. Un hébergement déjà saisi peut être repris pour une autre étape (par exemple la première et la dernière nuit d’un circuit).
- **Carrousel des hébergements** — L’aperçu du voyage présente les étapes en carrousel, nuits non renseignées comprises, ouvert sur l’étape de la nuit en cours. Les membres autorisés à modifier le voyage changent une étape d’un toucher ; les autres ouvrent le lien de l’hébergement.
- **Les nuits dans le planning** — Chaque nuit apparaît en fin de journée dans l’agenda et sur la carte du parcours. Les trajets vers et depuis l’hébergement sont proposés comme les autres trajets à prévoir, et une nuit non renseignée invite à indiquer l’hébergement. « Nuits » ne figure plus dans le menu « + ».
- **Trajet depuis le logement** — Le trajet en voiture affiché sur une activité part de l’hébergement où commence la journée (celui de la première nuit le jour de l’arrivée) et indique son nom.

### Lieux et activités

- **Lieux trouvés avec OpenStreetMap** — Les lieux sont recherchés et placés avec OpenStreetMap. La photo et le nom d’un lieu viennent de Google Places et s’affichent sur les cartes du planning, les suggestions et la page de l’activité ; la carte du voyage n’affiche que les noms saisis par le groupe et les photos des voyageurs.
- **Photos en plein écran** — Sur la page d’une activité, toucher la photo du lieu ou l’image du lien l’ouvre en plein écran, avec zoom.
- **Correspondances** — « Ajouter une correspondance » coupe un transport en deux étapes (par exemple un bateau puis un bus), qui se suivent sur la carte et dans l’agenda.
- **Nom des restaurants** — Les restaurants s’affichent de nouveau sous le nom trouvé depuis leur lien.

### Fonctions retirées

- **Génération d’activités par IA** — La génération d’activités, de trajets et d’hébergements à partir des documents, et la dictée d’activités du menu « + », sont retirées. Les activités déjà ajoutées ainsi restent dans les voyages. L’application ne demande plus l’accès au micro.

---

## Détails complémentaires (technique et exploitation)

### Hébergements

- **Anciens voyages** — Leur lien et leur adresse uniques s’affichent comme un hébergement pour toutes les nuits, jusqu’au premier enregistrement d’une étape ; aucune migration de données.
- **Permissions** — Modifier les hébergements relève de « Modifier les infos générales ».
- **Portefeuille** — Un document d’hébergement ne propose plus de créer une activité ; il peut toujours être relié à une activité existante.
- **Export / import de voyage** — Reprend les hébergements.

### Trajets

- **Calcul** — Le trajet en voiture est calculé avec OpenStreetMap, sans clé. Il est recalculé quand le lieu ou le jour de l’activité, un hébergement ou les dates du voyage changent ; les trajets existants se mettent à jour à leur prochain changement ou avec « Réessayer ».

### Confidentialité

- **Politique de confidentialité** — Mise à jour au 26/10/2026 : les fonctions d’IA retirées et la dictée vocale n’y figurent plus.

### Exploitation

- **Règles Firestore** — Hébergements des voyages (à déployer en production).
- **Cloud Functions** — `generateLodgingLinkPreview`, `generateLodgingLinkPreviewOnCreate`, `recomputeActivityDrivingRoutesOnLodgingChange` et `refreshActivityPlacePreview` (nouvelles) ; `computeActivityDrivingRouteFromTrip`, `recomputeActivityDrivingRoutesOnTripAddressChange`, `refreshActivityDrivingRoute`, `notifyTripActivityRecipients`, `exportTrip` et `importTrip` sont à déployer ; `extractTripActivitiesFromDocuments`, `importTripActivitiesFromDocuments` et `extractTripActivitiesFromText` sont à supprimer.
