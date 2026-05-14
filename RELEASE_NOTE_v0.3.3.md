# Release note — v0.3.3

## Nouveautés pour les participants

### Liste de courses

**Liste consolidée par rayon**
Les admins peuvent désormais lancer une consolidation IA des courses du voyage. Le résultat apparaît dans un nouvel onglet « Liste consolidée » où les articles sont regroupés par rayon (Fruits et légumes, Boulangerie, Surgelés, etc.), avec des sections repliables et un tri alphabétique au sein de chaque rayon.

**Deux modes de consolidation**
La boîte de dialogue de consolidation propose deux options au choix :
- *Liste libre uniquement* (par défaut) : les articles existants sont simplement classés par rayon, sans modification du texte ni des quantités.
- *Recettes et liste* : consolidation complète avec regroupement des doublons.

**Modification et organisation de la liste consolidée**
Chaque article de la liste consolidée est modifiable directement : quantité, unité, suppression, déplacement vers un autre rayon. Il est également possible d'ajouter des articles via le bouton d'action flottant (ils arrivent dans une section « Non assigné » en haut de liste, réaffectable ensuite).

**Sauvegarde partagée**
Les admins peuvent enregistrer la liste consolidée sur le voyage afin qu'elle soit visible pour tous les participants à la réouverture de l'onglet. Une action « Effacer » (avec confirmation) permet de la supprimer si besoin.

**Verrouillage des listes**
Les admins peuvent verrouiller ou déverrouiller chaque onglet de courses (Liste libre et Liste consolidée) indépendamment. En mode verrouillé, les autres participants conservent la possibilité de cocher et de réclamer des articles, mais ne peuvent plus ajouter, supprimer ni modifier les lignes. La consolidation IA et l'effacement sont également bloqués pendant que la liste consolidée est verrouillée.

**Réclamation exclusive**
Seul le participant qui a réclamé un article peut le cocher ou le décocher. Les articles non réclamés restent accessibles à tous.

**Filtre de statut par onglet**
Chaque onglet (Liste libre et Liste consolidée) conserve son propre état de filtre (tout, à faire, fait). Sur la liste consolidée, le filtre masque les rayons entiers qui n'ont aucun article correspondant, et un état vide dédié s'affiche si aucun résultat ne correspond.

**Renommage de l'onglet principal**
L'onglet de liste manuelle s'appelle désormais « Liste libre » (au lieu de « Ma liste »).

---

## Détails complémentaires (technique et exploitation)

- **Règles Firestore :** correction d'une erreur qui empêchait les participants d'ouvrir l'onglet consolidé lorsque la sous-collection n'existait pas encore. Les membres peuvent lire ; les admins peuvent créer, mettre à jour et supprimer les données consolidées.
- **Consolidation IA bilingue :** la Cloud Function accepte désormais un paramètre `lang` (`fr` / `en`). Les prompts, descriptions de schéma et libellés de catégories sont générés dans la langue demandée.
- **Déploiement requis :** la mise à jour des règles Firestore et le redéploiement de la Cloud Function `consolidateTripShoppingWithAi` sont nécessaires pour activer l'ensemble des fonctionnalités de cette version.
