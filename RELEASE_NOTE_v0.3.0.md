# Notes de version — v0.3.0

## Pour les utilisateurs

### Voyages

**Nouveau visuel de la page Mes voyages**

La page d'accueil des voyages s'enrichit d'une illustration de fond décalée vers le bas, avec une barre d'application transparente. L'en-tête adopte un fond clair unifié.

**Vue d'ensemble d'un voyage redessinée**

Les tuiles de catégories (Activités, Repas, etc.) affichent désormais leurs propres couleurs thématiques issues de la palette de chaque domaine. Le bandeau de participants est revu en bande compacte d'une seule ligne de badges.

### Repas

**Heure de la journée**

Un créneau horaire peut désormais être associé à chaque repas. Il est affiché directement sur la carte du repas dans les listes.

**Sélection d'un restaurant depuis le détail d'un repas**

Il est possible de choisir une suggestion de restaurant directement depuis la fiche d'un repas, sans quitter l'écran.

### Activités

**Repas intégrés dans la planification**

Les repas apparaissent dans les listes de planification sous le filtre Repas. Les activités de type restaurant sont exclues des vues Planifié et Agenda : elles ne figurent que dans ce filtre dédié.

**Protection de suppression**

La suppression d'une activité restaurant liée à un repas est désormais bloquée afin d'éviter les incohérences.

### Planning

**Onglet Planning en navigation principale**

L'onglet Planning devient l'action centrale de la barre de navigation, matérialisée par un bouton flottant proéminent.

**Filtres de catégorie**

Des filtres de catégorie sont disponibles dans la vue de planification pour restreindre l'affichage par domaine d'activité.

**Améliorations visuelles**

Le jour de la semaine est affiché dans les séparateurs de date. Le FAB s'étend en éventail pour proposer les différentes actions de planification. Les cartes d'activités et de repas sont visuellement alignées.

### Dépenses

**Saisie sur écrans dédiés**

La création d'une nouvelle dépense et la rédaction d'un post s'ouvrent chacune sur un écran dédié, offrant plus d'espace et de clarté.

**Visibilité par défaut**

Les nouveaux posts sont désormais visibles uniquement par leur créateur par défaut.

**FAB extensible**

Les actions dépense et post sont regroupées dans un FAB extensible en éventail.

### Achats

Les actions de liste sont regroupées dans un FAB extensible. L'icône du FAB principal affiche un sac de courses en contour.

---

## Détails techniques et opérationnels

### Apparence et thème

- Introduction d'un système de couleurs statiques pour un style de carte unifié sur les écrans de voyages et d'activités.
- L'image de fond est restreinte à l'écran de connexion et à la liste des voyages ; la barre d'application est globalement transparente sur les autres écrans.
- Couleur primaire du thème Oligarch mise à jour (#3F46F7).

### Navigation

- Style de sélection de la barre de navigation inférieure revu : un point indicateur apparaît sous l'élément actif.
- Correction d'un décalage du bouton Planning sur la version web.

### Application

- Nouvelle icône d'application déployée sur toutes les plateformes (Android, iOS, web).
- La connexion par lien e-mail est supprimée de l'écran de connexion.
- La sélection de palette est retirée des paramètres du compte.
