# Notes de version — v0.2.0-beta1

> Période couverte : v0.2.0-alpha3 → v0.2.0-beta1

---

## 1) L'essentiel pour les utilisateurs

### Voyages

- **Nouveaux réglages de permissions pour les repas** : un voyage peut désormais définir précisément qui peut gérer les repas, avec un rôle **chef** dédié.
- **Contrôle renforcé des suppressions de membres** : l'application bloque plus strictement la suppression d'un membre quand cela mettrait le voyage dans un état incohérent.
- **Annonces plus flexibles** : les annonces déjà publiées peuvent maintenant être modifiées.

### Messagerie

- **Réactions plus fiables** : les boutons de réaction restent facilement cliquables, même sur des bulles de message étroites.

### Activités

- **Catégories d'activités étendues** : le choix passe de 5 à 20 catégories, pour mieux représenter les différents types d'activités.
- **Lecture des votes améliorée** : la fiche d'une activité affiche les votants dans une zone dédiée, plus lisible.

### Dépenses

- **Sélection des payeurs plus robuste** : les noms longs n'écrasent plus la mise en page dans les champs de sélection.

### Repas

- **Organisation des apports par catégories** : les contributions auberge espagnole sont affichées et regroupées par catégorie, pour une vue plus claire.
- **Règles d'accès mieux appliquées** : les droits sur les repas (dont l'édition de recettes côté chef) sont appliqués de manière cohérente dans l'interface.
- **Participants de repas plus fiables** : les listes de participants restent cohérentes lors des remplacements ou suppressions de membres.
- **Vue repas plus précise** : le comptage des participants utilise uniquement les membres actifs du voyage.

### Profil utilisateur

- **Support & compte utilisateur** :
  - Ajout d'une page **Aide et support**.
  - Affichage de la version de l'application avec un lien vers les notes de version.
  - Contrôle de mise à jour renforcé avec mise à jour obligatoire lorsqu'une nouvelle version GitHub est disponible.

---

## 2) Détails complémentaires (technique et exploitation)


- **Fonctions Cloud et sécurité** :
  - Correction d'un risque d'exposition de clé API Places dans les URLs de photos.
  - Ajustements sur les rôles/permissions pour conserver des rangs cohérents.
  - Optimisations de lecture de dépendances pour éviter des traitements redondants sur la gestion des placeholders.
- **Stabilité et cohérence des données** :
  - Retrait de champs historiques devenus inutiles dans le modèle des repas (`notes` et ancien champ `name`).
  - Ajustements de fallback d'authentification pour fiabiliser les libellés de membres.
  - Correctifs divers de cohérence entre droits voyage, règles backend et fixtures de test.
