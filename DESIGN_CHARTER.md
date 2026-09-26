# Charte graphique Planerz — « Riviera »

Référence **transversale** pour toute l'application (remplace la charte Néon issue des handoffs).
Couleurs détaillées : [`PALETTES.md`](PALETTES.md). Implémentation : `lib/app/theme/` (`AppTokens`, `AppTheme`, `activity_filter_colors.dart`).

**Usage agent :** ne jamais coder de couleur, rayon ou style de contrôle en dur dans un écran. Utiliser `Theme.of(context)` (les contrôles Material sont déjà stylés globalement) ou `AppTokens`. Un besoin non couvert = nouveau token ou nouveau réglage de thème, pas une surcharge locale.

---

## 1. Principes

1. **Joyeux mais contenu** — une seule couleur de chrome (Lagon), un surlignage (Soleil), quatre teintes métier réservées aux catégories.
2. **Compact** — Planerz affiche beaucoup d'informations : densité `VisualDensity(-1, -2)`, contrôles de 40 px, champs de 44 px, lignes de liste de 48–56 px. Les cibles tactiles restent ≥ 48 px (`MaterialTapTargetSize.padded`).
3. **Standard** — composants Material 3 natifs (TabBar, Chip, Switch, FAB, BottomSheet, PopupMenu…) stylés par le thème, plutôt que des widgets maison.
4. **Une action principale par écran** — un seul FAB ; les actions secondaires vont dans le menu ⋮ de l'écran.

## 2. Fondations

| Élément | Valeur |
|---|---|
| Police | **Figtree** (400 / 500 / 600 / 700 / 800), OFL — `assets/fonts/figtree/` |
| Grille | multiples de 4 dp ; marge d'écran 16 dp |
| Rayons | 6 (case à cocher) · 8 (puces) · 10 (boutons, champs) · 14 (cartes) · 20 (dialogues, feuilles) |
| Fond | `#F5F6F8` ; surfaces blanches ; bordures `#E2E5EA` (cartes **sans ombre**, filet 1 px) |
| Élévation | `AppTokens.elev1/elev2` uniquement pour éléments flottants (login, FAB) |

### Typographie (échelle compacte)

| Rôle | Taille / graisse |
|---|---|
| headlineSmall (titre de page) | 21 / 700 |
| titleLarge (app bar, dialogue) | 18 / 700 |
| titleMedium (titre de carte) | 15 / 600 |
| titleSmall / labelLarge | 14 / 600 |
| bodyMedium (texte courant) | 14 / 400 |
| bodySmall (méta, légende) | 12,5 / 400, couleur `onSurfaceVariant` |
| labelSmall (nav, badges) | 11 / 600 |

Chiffres (heures, montants, quantités) : `FontFeature.tabularFigures()`.

## 3. Composants (tous réglés dans `AppTheme`)

| Composant | Règle |
|---|---|
| App bar | Blanche, filet bas, titre aligné à gauche (18/700). En voyage : titre + sous-titre de dates compact (« 25 – 29 sept. 2026 »). |
| Champ de saisie | Rempli blanc, bordure `#E2E5EA`, focus Lagon 1,6 px, rayon 10, dense. Champs inline : `InputBorder.none` **+** `enabledBorder/focusedBorder: InputBorder.none` **+** `filled: false`. |
| Bouton principal | `FilledButton` Lagon, 40 px, rayon 10. Secondaire : `OutlinedButton` blanc bordé. Tertiaire : `TextButton` Lagon. |
| Toggle | `Switch` natif : piste Lagon / gris `#D3D8DF`, pouce blanc, sans icône. Jamais de switch maison. |
| Case à cocher | Rayon 6, remplissage Lagon. |
| Puces | `ChoiceChip` (exclusif) / `FilterChip` (cumulable) : 8 px de rayon, sélection = fond teinte Lagon + bordure Lagon, sans coche. Puces de catégorie : `TripCategoryFilterChip` (teinte métier). |
| Onglets | `TabBar` natif, style **pilule** (`PillTabIndicator`) : pastille teintée Lagon derrière l'onglet sélectionné, libellé Lagon foncé 14/700, filet bas. Jamais de fausse barre d'onglets maison. Sélecteur de vue hors `TabBar` : `PzSegmentedControl` (même rendu, sur piste grise). |
| Sélecteur « gros boutons » | Tuiles égales icône + libellé (ex. moment du repas, mode du repas). |
| Carte | `Card` blanche, rayon 14, filet, pas d'ombre. |
| Liste | `ListTile` dense ; séparateurs `Divider` pleine largeur ou indentés sous l'icône. |
| FAB | Lagon, rayon 14 ; version étendue quand l'action a besoin d'un libellé. |
| Choix d'action multiples | `showModalBottomSheet` (poignée, rayon 20), une ligne par action. **Pas de speed-dial.** |
| Menu ⋮ | `PopupMenuButton`, lignes icône + libellé ; actions destructrices en `error`. |
| Dialogue | Rayon 20, titre 18/700. |
| SnackBar | Flottante, fond encre `#1E2840`, action Soleil. |
| Badge | Fond Soleil, texte encre. |

### Composants partagés (`lib/core/presentation/pz_components.dart`)

| Widget | Usage |
|---|---|
| `PzSectionHeader` | Titre de section 14/800 + compteur + action (ex. « Chambres 3 », « Voitures ») |
| `PzCountPill` | Compteur neutre (ou Soleil pour un non-lu) |
| `PzSegmentedControl` | Bascule de vue exclusive (Dépenses / Équilibres) |
| `PzCallout` | Bloc de message teinté : `info`, `warning`, `error`, `success`, `brand` |
| `PzEmptyState` | État vide : tuile icône teintée + titre (+ message) |
| `PzProgressBar` | Progression « faits / total » + actions de liste (Courses, À emporter) |
| `PzInitialAvatar`, `PzPersonChip` | Avatars à initiale et puces personne (chambres, covoiturage) |

## 4. Navigation

- **Barre basse du voyage** (5 entrées inchangées : Aperçu, Messagerie, **Planning**, Dépenses, Courses). Onglets standards (icône + libellé, pastille teintée quand sélectionné). **Planning** est une capsule centrale plus large, toujours teintée Lagon (pleine quand sélectionnée) : l'emphase passe par la forme et la couleur, sans bouton flottant qui déborde de la barre.
- ≥ 720 px : `NavigationRail` (même ordre).
- Le titre de l'app bar ramène à l'Aperçu ; la flèche retour ramène à « Mes voyages ».

## 5. Écrans métier

### Planning
1. Onglets **Agenda · Planifiées · Suggestions** (l'onglet par défaut en premier).
2. Rangée de filtres de catégorie compacte (une ligne, défilable).
3. Agenda : semaine en pastilles (jour sélectionné plein Lagon, aujourd'hui cerclé Soleil, un point coloré **par catégorie** présente ce jour-là), puis **frise horaire** (heure à gauche, nœud coloré, carte).
4. Bouton « + » → feuille « Ajouter » (Loisirs, Repas, Nuits, Trajets).

### Courses
1. Onglets Liste libre / Consolidée (cadenas dans l'onglet).
2. Recherche, puis puces **Tous · À acheter · Déjà achetés · Moi** + menu ⋮ (aide, consolidation IA, suppression des cochés, effacement de la consolidation).
3. Barre de progression « cochés / total ».
4. Lignes regroupées dans une carte ; quantité dans une capsule unique (− qté + unité).
5. FAB étendu « Ajouter un article ».

### Repas
- Liste = **tableau de menus** : chaque jour du voyage affiche Petit-déjeuner / Déjeuner / Dîner ; un créneau vide reste visible (« — ») pour repérer les repas manquants.
- Détail : moment et mode du repas en tuiles icône + libellé.

### Modules secondaires
- **Aperçu** : modules en **grille 2 colonnes** (tuile icône + compteur, libellé, statut) ; Planning en Lagon, modules métier dans leur teinte (Chambres = Nuits, Covoiturage = Trajets, Jeux = Loisirs), modules personnels neutres.
- **Chambres** : carte par chambre (teinte Nuits), occupation « occupés/capacité », une ligne par lit avec les occupants en puces.
- **Covoiturage** : carte par voiture (teinte Trajets) : heure de départ en tuile, conducteur, lieu, places occupées (puces) et libres (sièges vides) ; voiture où je suis = contour Lagon.
- **Jeux**, **À emporter**, **Annonces** : liste compacte dans une carte, états vides `PzEmptyState`.

## 6. Iconographie

- Material Symbols **Rounded** pour les nouvelles icônes (`Icons.*_rounded`), 20–22 px ; icônes de catégorie dans une tuile teintée 34 px (rayon 10).
- Logo : repère « épingle + soleil couchant sur la mer » (`assets/images/planerz_mark.svg`, widget `PlanerzBrandMark` / `PlanerzBrandLockup`). Icône d'app : `assets/images/app_icon.png` (1024 px, plein cadre).
