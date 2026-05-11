# Notes de version — v0.2.0-beta4

> Période couverte : v0.2.0-beta3 → v0.2.0-beta4

---

## 1) Priorité utilisateurs (par domaine métier)

### Voyages

- **Aperçus de liens unifiés et compacts** : dans l’aperçu du voyage, le détail d’activité, le formulaire d’édition d’activité et la section "rendez-vous courses" du covoiturage, les liens (lieux, sites, etc.) s’affichent désormais sous une forme condensée — petite vignette à gauche, titre du lien et URL en dessous — pour une lecture homogène et plus dense d’un écran à l’autre.
- **Itinéraire en un tap depuis l’aperçu** : sur la fiche d’aperçu du voyage, l’adresse n’apparaît plus comme une ligne séparée. À la place, une icône "itinéraire" s’affiche à côté du lien dès qu’une adresse ou un lien Google Maps est renseigné. Un appui ouvre Maps directement (le lien prime sur l’adresse si les deux sont présents), pour lancer une navigation sans jamais voir la ligne d’adresse brute.
- **Covoiturage — date de départ visible sur la carte** : chaque carte de covoiturage affiche maintenant la date de départ (jour + mois) à côté de l’horaire, pour distinguer en un coup d’œil les trajets qui partent sur un autre jour que celui du voyage.
- **Covoiturage — détail en lecture seule** : ouvrir un covoiturage existant présente d’abord une vue propre en lecture seule (libellés et texte). Le formulaire d’édition n’apparaît qu’après avoir touché le bouton de modification.
- **Covoiturage — section "rendez-vous courses" restructurée** : la section perd son encadré, son titre est plus compact, et un titre "Voitures" introduit clairement la liste des covoiturages en dessous, pour une hiérarchie visuelle plus lisible.
- **Covoiturage — état "aucun passager" plus clair pour le conducteur** : sur l’aperçu du voyage, lorsque vous êtes conducteur d’un covoiturage que personne n’a encore rejoint, la place passager affiche désormais "[personne]" au lieu d’un libellé générique "Non renseignée".
- **Jeux — liste plus dense** : les lignes de la liste de jeux sont condensées (hauteur réduite, espacement plus serré entre les éléments). L’URL du lien n’apparaît plus sur chaque ligne, seul le nom du jeu reste visible, et la vignette d’aperçu adopte un format portrait, mieux adapté aux pochettes de jeux de société.

### Messagerie

- Aucun changement fonctionnel dans cette version.

### Activités

- **Aperçu de lien compact dans le détail et l’édition** : la fiche détail d’activité et le formulaire d’édition adoptent le même aperçu de lien condensé que le reste de l’application, pour une expérience visuelle cohérente.

### Dépenses

- Aucun changement fonctionnel dans cette version.

### Repas

- Aucun changement fonctionnel dans cette version.

---

## 2) Détails complémentaires (technique / exploitation)

- **Composant d’aperçu de lien partagé** : un format compact unique (vignette + titre + URL) est désormais réutilisé dans l’aperçu du voyage, le détail et l’édition d’activité, et la section "rendez-vous courses" du covoiturage, en remplacement des cartes verbeuses utilisées auparavant à plusieurs endroits.
- **Aperçu du voyage — logique d’itinéraire centralisée** : la décision d’afficher l’icône "itinéraire" et la cible d’ouverture (lien Google Maps existant ou adresse renseignée) sont gérées au même endroit, ce qui supprime la ligne d’adresse autonome de l’aperçu sans perdre l’accès à la navigation.
- **Localisation** : ajout des chaînes `tripCarpoolCarsTitle` (titre "Voitures") et `tripOverviewCarpoolNoPassengersPlaceholder` ("[personne]") dans les fichiers ARB de référence (`app_fr`, `app_fr_FR`, `app_en`, `app_en_US`).
- **Divers dépôt** : publication de la version applicative `0.2.0-beta4` (bump de `pubspec.yaml` à effectuer au moment du tag).
