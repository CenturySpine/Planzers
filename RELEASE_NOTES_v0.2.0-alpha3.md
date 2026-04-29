# Release notes — v0.2.0-alpha3

> Période couverte : v0.2.0-alpha2 → v0.2.0-alpha3

---

## Voyages & séjours

### Nouvelles fonctionnalités

- **Aperçu Google Maps enrichi** — les liens Maps sont désormais complétés via la Places API pour afficher une prévisualisation riche (nom, photo, adresse) dans les cartes.
- **Raccourci photos dans l'en-tête d'aperçu** — un accès rapide au stockage photos du voyage est ajouté directement dans l'en-tête de la page de vue d'ensemble.
- **Réglages voyage scindés en deux sous-pages** — les paramètres généraux (lien de stockage photos, mode Cupidon) sont maintenant séparés des autres réglages pour plus de clarté.
- **Éditeur de séjour unifié** — la page des préférences et le formulaire d'adhésion partagent désormais un même composant d'édition des options de séjour, décliné en deux onglets distincts.
- **Carte de visibilité du numéro de téléphone repensée** — mise en page inline, état désactivé plus explicite.
- **Tuile Jeux sur la vue d'ensemble** — un accès rapide à la section jeux est visible depuis l'aperçu du voyage.
- **Image de lien preview dans la carte de voyage** — quand aucune bannière n'est définie, la photo issue de la prévisualisation de lien est affichée.

### Correctifs

- Le formulaire d'adhésion exige maintenant la saisie des détails d'invitation avant de permettre l'association à un profil existant.
- Les bornes de dates de l'invitation sont normalisées en heure locale (évite les décalages liés au fuseau horaire).
- Le séjour proposé par défaut dans l'invitation est pré-rempli avec les repas inclus au voyage.
- Pour les voyages d'une seule journée, le séjour par défaut de l'invitation est maintenant correctement calculé.
- Le seuil de correspondance automatique des placeholders dans l'invitation a été abaissé pour réduire les faux positifs.
- Le toggle admin sur la liste des membres ne se déclenche plus qu'au appui long (évite les activations accidentelles).
- La bascule Cupidon d'un membre est désormais désactivée automatiquement si le mode Cupidon du voyage est éteint, et masquée si le mode est inactif ; elle est en revanche bien visible dans le formulaire d'adhésion quand le mode est actif.
- Le libellé du toggle Cupidon reste statique (il ne change plus selon l'état).
- Correction d'un bug de confusion entre le lien de stockage photos et le lien de logement.
- Le champ `photosStorageUrl` est maintenant bien inclus dans la sérialisation du voyage (`Trip.toMap()`).
- En cas d'échec de validation du séjour en direct, l'interface revient correctement à l'état précédent.
- Les cartes des options de séjour et la bannière de brouillon ont été visuellement unifiées.
- L'espacement entre les cartes d'options de séjour a été resserré.
- Les boutons d'action de l'étape 2 du parcours d'adhésion sont alignés avec le bouton Retour.

---

## Repas

### Nouvelles fonctionnalités

- **Aperçu compact du contenu dans les cartes de repas** — les cartes affichent maintenant un résumé visuel des composants (plats cuisinés, potluck, restaurant).
- **Bascule du mode repas intégrée directement dans la carte de détail** — plus besoin d'aller dans un menu séparé pour changer le mode.
- **Clarté des cartes de plats cuisinés améliorée** — meilleure lecture des composants individuels.
- **Tri automatique des composants cuisinés** — les composants sont ordonnés automatiquement jusqu'à ce qu'un réordonnement manuel soit effectué.

### Correctifs & refactorisation

- Le nom du restaurant issu de la prévisualisation de lien est maintenant affiché dans la carte de repas.
- Le bouton d'ajout pour le mode potluck et le bouton d'ajout de composant suivent désormais le style standard de l'application.
- L'édition du lien restaurant suit le même pattern que l'édition de profil.
- Le type de composant « autre » (`other`) a été supprimé (refactorisation).
- Le champ `name` inutilisé a été retiré du modèle `TripMeal` (refactorisation).

---

## Activités

### Nouvelles fonctionnalités

- **Création d'activité sur une page dédiée** — le formulaire de création d'activité dispose maintenant de sa propre page au lieu d'un dialog/modal.

### Correctifs

- L'heure de planification est prise en compte et les éléments du planning journalier sont triés par heure.
- Le pseudo du créateur (nickname du profil) est affiché à la place de son identifiant brut.

---

## Invitations & rejoindre un voyage

### Nouvelles fonctionnalités

- **Suggestion de voyageur par e-mail dans le parcours d'adhésion** — lors de la jointure, l'application propose des correspondances basées sur l'adresse e-mail pour simplifier l'association à un placeholder existant.
- **Rejoindre un voyage sans revendiquer de placeholder** — il est désormais possible d'adhérer à un voyage même si aucun placeholder ne correspond, sans être bloqué.

---

## Application & thème

- **Version de l'application affichée** — la version courante est visible dans l'en-tête principal et sur l'écran de connexion.
- **Palette Oligarch définie comme palette par défaut.**
