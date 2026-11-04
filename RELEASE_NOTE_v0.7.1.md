# Version 0.7.1

## Améliorations pour les utilisateurs

### Courses : répartir les achats

- **Assigner un article** — Dans le menu « ... » d’un article, un administrateur du voyage choisit le participant qui s’en charge, ou « Personne » pour le libérer. Cela fonctionne dans la liste manuelle comme dans la liste consolidée.
- **Assigner une catégorie** — Dans la liste consolidée, le menu « ... » d’une catégorie (par exemple Boucherie) confie tous ses articles libres, ni achetés ni déjà pris, à un même participant.
- **Comme une prise en charge** — Un article assigné se comporte comme un article que la personne a pris elle-même : son avatar s’affiche, elle seule peut le cocher, elle peut le relâcher, et il apparaît dans son filtre « Claimés par moi ». La main fonctionne comme avant pour se positionner soi-même.

### Recettes générées par l’IA

- **Génération par le serveur** — La génération d’une recette (ingrédients et étapes) passe désormais par le serveur, comme la consolidation des courses.
- **Pendant la génération** — L’écran s’assombrit avec un indicateur de chargement jusqu’à la fin ; le bouton IA garde son icône.

### Activités

- **Ma position** — Le bouton du sélecteur de lieu affiche bien son indicateur de chargement pendant la localisation.

---

## Détails complémentaires (technique et exploitation)

### Intelligence artificielle

- **Fin de Gemini 2.5 Flash** — Google retire ce modèle le 1er décembre 2026. Les fonctionnalités IA utilisent par défaut Gemini 3.5 Flash-Lite.
- **Réglages IA (administration)** — Nouvelle page « Intelligence artificielle » : fournisseur de la consolidation des courses (Google ou Anthropic), modèle retenu pour chaque fournisseur (Claude Haiku 5.5 par défaut pour Anthropic) et niveau de réflexion (Minimale, Faible, Moyenne, Élevée). Un changement enregistré s’applique à l’appel suivant, sans redéploiement. Les recettes utilisent toujours le modèle Google retenu.
- **Recettes côté serveur** — Nouvelle Cloud Function `generateRecipeWithAi`. L’app n’appelle plus l’IA directement : Firebase AI Logic et App Check ne sont plus utilisés pour l’IA, et les quotas des recettes sont comptés par le serveur.
- **Accès réservé aux membres** — La consolidation des courses, la génération de recettes et les quotas IA d’un voyage sont réservés à ses membres et aux propriétaires de l’application.
- **Politique de confidentialité** — Anthropic est cité comme fournisseur d’IA possible pour la consolidation des courses (français et anglais).

### Courses

- **Assignation** — Réservée aux administrateurs du voyage dans l’interface ; elle réutilise la prise en charge existante des articles, sans nouveau champ ni migration de données.

### Exploitation

- **Règles Firestore** — Écriture des réglages IA (`system/aiSettings`) par les propriétaires de l’application (à déployer en production).
- **Cloud Functions** — `generateRecipeWithAi` (nouvelle), `consolidateTripShoppingWithAi`, `reserveAiQuota` et `refundAiQuota` sont à déployer.
- **Secrets** — `GOOGLE_AI_API_KEY` sert désormais aussi aux recettes ; `ANTHROPIC_API_KEY` sert quand Anthropic est choisi pour la consolidation.
