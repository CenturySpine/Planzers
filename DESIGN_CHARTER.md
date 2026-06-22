# Charte graphique Planerz — synthèse des handoffs Claude Design

Document de référence **transversal** pour l’application entière.  
Sources : 10 packages ZIP du dossier `claude design handoff` (accountpage, bottom menu, join-code-popup, join-trip, my-trips, overview, params-move, participants, participant-preferences) + `Planzers Design System-trip-create-neon-only.zip` pour create_trip, analysés en juin 2026.

**Usage agent :** appliquer les tokens et règles de composants ci-dessous ; ne pas recopier le HTML/React des handoffs ; mapper sur Flutter Material 3 et le thème existant (`BrandPaletteData`, `PlanerzColors`, `AppTheme`). Écarts entre packages et arbitrages : [`DESIGN_CHARTER_INCOHERENCES.md`](DESIGN_CHARTER_INCOHERENCES.md).

---

## 1. Fondations

| Règle | Valeur |
|---|---|
| Framework UI | Flutter + Material 3 |
| Grille d’espacement | 4 dp (multiples de 4) |
| Police principale | **Geist** (`--font-sans`) |
| Police monospace | **Geist Mono** (`--font-mono`) — codes, OTP |
| Fond scaffold | `--scaffold-bg` → `#F8F9FA` |
| Surface carte | `--surface` / `--bg-card` → `#FFFFFF` |
| App bar | Plate, fond = scaffold (`--appbar-bg`), **sans ombre**, hauteur **52 px** |
| Texte principal | `--fg-1` = `--deep` (couleur de la palette active) |
| Texte secondaire | `--fg-2` = `--on-surface-variant` → `#6B7280` |
| Texte tertiaire / légende | `--fg-3` = `--outline` → `#A0A0A0` |
| Overlay modal | `--bg-overlay` → `rgba(0, 0, 0, 0.40)` |

---

## 2. Palette de marque

**Une seule palette** dans l’ensemble des handoffs : **Néon**. Elle expose **exactement trois couleurs de marque** : `primary`, `accent`, `secondary`, plus `deep` dérivé. Tout le reste (neutres, sémantiques erreur/succès/avertissement, surfaces) est **partagé**.

### 2.1 Neutres

| Token | Hex |
|---|---|
| `--neutral-bg` / scaffold | `#F8F9FA` |
| `--neutral-card` | `#FFFFFF` |
| `--neutral-mid` / outline | `#A0A0A0` |
| `--neutral-300` / divider | `#E5E7EB` |
| `--neutral-500` / on-surface-variant | `#6B7280` |
| `--neutral-700` | `#374151` |
| `--neutral-900` | `#111418` |
| `--surface-highest` | `#EEEFF2` |
| `--inverse-surface` | `#2A2D33` |
| `--on-inverse-surface` | `#F8F9FA` |

### 2.2 Sémantiques (palette-agnostiques)

| Token | Hex |
|---|---|
| `--success` | `#2EB37F` |
| `--success-container` | `#DCF5E8` |
| `--warning` | `#C49A00` |
| `--warning-container` | `#FFF3CC` |
| `--error` | `#BA1A1A` |
| `--error-container` | `#FFDAD6` |
| `--on-error` | `#FFFFFF` |
| `--on-error-container` | `#410002` |

### 2.3 Néon (palette active — tous les handoffs)

| Token | Hex | Rôle |
|---|---|---|
| `--primary` | `#6745DE` | États actifs, CTA principal, liens, focus |
| `--accent` | `#FF6B6B` | Action secondaire (rejoindre, dépenses actives) |
| `--secondary` | `#4ECDC4` | Accent tertiaire discret, teintes décoratives |
| `--deep` | `#1F1547` | Texte principal / titres forts |
| Jaune logo (mosaïque) | `#FFD166` | Tuile logo uniquement |

### 2.4 Teintes dérivées (`color-mix` sur `--neutral-card`)

| Token | Formule |
|---|---|
| `--primary-light` | `color-mix(in srgb, var(--primary) 35%, var(--neutral-card))` |
| `--primary-soft` | `color-mix(in srgb, var(--primary) 16%, var(--neutral-card))` |
| `--primary-tint` | `color-mix(in srgb, var(--primary) 8%, var(--neutral-card))` |
| `--accent-soft` | `color-mix(in srgb, var(--accent) 16%, var(--neutral-card))` |
| `--accent-tint` | `color-mix(in srgb, var(--accent) 8%, var(--neutral-card))` |
| `--secondary-container` | `color-mix(in srgb, var(--secondary) 28%, var(--neutral-card))` |
| `--secondary-soft` | `color-mix(in srgb, var(--secondary) 14%, var(--neutral-card))` |

### 2.5 Rôles couleur par type d’élément

| Élément | Couleur |
|---|---|
| Bouton filled principal | `--primary` + texte `--fg-on-primary` (`#FFFFFF`) |
| Bouton / lien secondaire corail | `--accent` |
| Onglet / nav actif (défaut) | `--primary` |
| Onglet Dépenses actif | `--accent` (exception documentée) |
| Champ focus | bordure `--primary` |
| Champ erreur | bordure `--error` |
| Séparateur | `--divider` / `--outline-variant` |
| Snackbar | fond `--inverse-surface`, texte `--on-inverse-surface` |
| Action snackbar | `--primary-light` |
| Pastille avatar sans photo | fond `--primary-light`, texte `--deep` |
| Badge compteur | fond `--primary` ou `--accent` selon contexte, texte blanc |
| Astérisque requis | `--accent` |
| Lien texte | `--primary` |

---

## 3. Typographie (échelle Material 3)

Famille : Geist. Poids disponibles : 300 / 400 / 500 / 600 / 700.

| Rôle | Taille | Line-height | Poids | Letter-spacing |
|---|---|---|---|---|
| Display L | 57 px | 64 px | 400 | −0.25 px |
| Display M | 45 px | 52 px | 400 | — |
| Display S | 36 px | 44 px | 400 | — |
| Headline L | 32 px | 40 px | 400 | — |
| Headline M | 28 px | 36 px | 400 | — |
| Headline S | 24 px | 32 px | 400 | — |
| Title L | 22 px | 28 px | 400 | — |
| Title M | 16 px | 24 px | 500 | 0.15 px |
| Title S | 14 px | 20 px | 500 | 0.1 px |
| Body L | 16 px | 24 px | 400 | 0.5 px |
| Body M | 14 px | 20 px | 400 | 0.25 px |
| Body S | 12 px | 16 px | 400 | 0.4 px |
| Label L | 14 px | 20 px | 500 | 0.1 px |
| Label M | 12 px | 16 px | 500 | 0.5 px |
| Label S | 11 px | 16 px | 500 | 0.5 px |

### Usages transverses

| Contexte | Spec |
|---|---|
| Titre app bar | 20 px / 500 / lh 28 px / `--fg-1` |
| Titre app bar détail voyage | 20 px / **600** / letter-spacing −0.2 px / `--deep` |
| Dialogue standard (M3, titre seul) | 22 px / 400 / lh 28 px |
| Dialogue d'action (en-tête icône + titre ≤ 1 ligne) | 22 px / **600** / `--deep` |
| Titre section (uppercase) | 12 px / 600 / `--neutral-500` / letter-spacing 0.5 px |
| Libellé champ (floating) | 12 px / `--fg-2` ; focus → `--primary` |
| Helper / erreur champ | 11 px ; erreur → `--error` |
| Code invitation / voyage | Geist Mono, 13–24 px selon contexte, weight 600 |
| Wordmark splash | 56 px / 700 / lh 1.0 |
| Sous-titre wordmark | 18 px / 600 / letter-spacing 0.6 px |

Corps HTML prototype : 14 px base ; l’app Flutter suit l’échelle M3 ci-dessus.

---

## 4. Espacement (`--space-n`)

| Token | Valeur |
|---|---|
| `--space-1` | 4 px |
| `--space-2` | 8 px |
| `--space-3` | 12 px |
| `--space-4` | 16 px |
| `--space-5` | 20 px |
| `--space-6` | 24 px |
| `--space-7` | 32 px |
| `--space-8` | 40 px |
| `--space-9` | 56 px |

Padding horizontal formulaire standard : **16 px**. Gap vertical entre sections formulaire : **16 px**.

---

## 5. Rayons (`--radius-*`)

| Token | Valeur | Usage |
|---|---|---|
| `--radius-xs` | 4 px | Champs outlined M3, snackbar, menu popup |
| `--radius-sm` | 8 px | — |
| `--radius-md` | 12 px | Cartes, champs « shell », tuiles date, segments |
| `--radius-banner` | 14 px | Pastilles page, CTA speed-dial item |
| `--radius-lg` | 16 px | Cartes larges, FAB liste, groupes préférences |
| `--radius-xl` | 28 px | Dialogues, bottom-sheet (coins supérieurs) |
| `--radius-full` | 9999 px | Boutons pill, avatars, switches, FAB ronds |

Rayons ponctuels hors tokens : tuile icône **10 px** ; bouton SSO **10 px** ; FAB liste et speed-dial **16 px** (`--radius-lg`) ; bannière couverture **18 px**.

---

## 6. Élévation et ombres

| Token | Valeur |
|---|---|
| `--elev-0` | none |
| `--elev-1` | `0 1px 2px rgba(0,0,0,0.06), 0 1px 3px rgba(0,0,0,0.05)` |
| `--elev-2` | `0 1px 2px rgba(0,0,0,0.06), 0 2px 6px 2px rgba(0,0,0,0.06)` |
| `--elev-3` | `0 4px 8px 3px rgba(0,0,0,0.08), 0 1px 3px rgba(0,0,0,0.06)` |
| `--elev-4` | `0 6px 10px 4px rgba(0,0,0,0.08), 0 2px 3px rgba(0,0,0,0.06)` |
| `--elev-5` | `0 8px 12px 6px rgba(0,0,0,0.10), 0 4px 4px rgba(0,0,0,0.08)` |

| Composant | Élévation |
|---|---|
| Carte standard | `--elev-1` |
| Carte liste avec bordure | bordure `1px --divider` + ombre `0 1px 2px rgba(0,0,0,0.04)` |
| FAB | `--elev-2` |
| Bottom nav | `--elev-3` |
| Dialogue | `--elev-3` |
| Menu popup | `--elev-3` |
| Dialogue code invitation | ombre custom `0 28px 56px -16px rgba(31,21,71,0.42), 0 10px 22px -12px rgba(31,21,71,0.30)` |
| FAB bottom nav (centre) | `0 10px 22px -6px rgba(103,69,222,0.70), 0 2px 6px rgba(0,0,0,0.18)` |
| CTA principal formulaire | `0 6px 18px color-mix(in srgb, var(--primary) 28%, transparent)` |

---

## 7. Motion

| Token | Durée | Usage |
|---|---|---|
| `--motion-fast` | **150 ms** | Hover, switch, segments, couleur onglet |
| `--motion-medium` | **250 ms** | Bottom-sheet, dialogue, FAB nav, rotation speed-dial |
| `--motion-slow` | **400 ms** | — |

| Courbe | Valeur |
|---|---|
| `--ease-standard` | `cubic-bezier(0.2, 0.0, 0, 1.0)` |
| `--ease-emphasized` | `cubic-bezier(0.2, 0.0, 0, 1.0)` |
| `--ease-decelerate` | `cubic-bezier(0.0, 0.0, 0, 1.0)` |
| `--ease-accelerate` | `cubic-bezier(0.3, 0.0, 1, 1)` |

Reduced motion : états finaux visibles sans animation ; couleurs et anneaux conservés.

---

## 8. Iconographie

| Règle | Valeur |
|---|---|
| Famille | **Material Symbols** |
| Repos / inactif | `Material Symbols Outlined` — `FILL 0, wght 400, opsz 24` |
| Actif / emphase | `Material Symbols Rounded` — `FILL 1, wght 400, opsz 24` |
| Onglet nav actif | `FILL 1, wght **600**, opsz 24` |
| Taille standard | 24 px |
| Taille app bar / tuile | 20 px |
| Taille FAB nav centre | 27 px |
| Couleur repos | `currentColor` ou `--fg-2` |
| Leading list tile | `--fg-2` |

Ne pas utiliser d’URL d’images Google pour les avatars en production (règle produit) — badges Firestore uniquement.

---

## 9. Composants — spécifications transverses

### 9.1 Bouton icône (`IconBtn`)

- Taille touch : **40 × 40 px**, `border-radius: full`
- Fond repos : transparent
- Hover : `color-mix(in srgb, var(--primary) 8%, transparent)`
- Active : `color-mix(in srgb, var(--primary) 16%, transparent)`
- Transition : `--motion-fast` + `--ease-standard`

### 9.2 Boutons texte

| Variante | Spec |
|---|---|
| **Filled** | pill, padding `10px 24px`, 14 px / 500, fond `--primary`, texte blanc ; hover : `--elev-1` + brightness 1.05 ; disabled : `rgba(22,29,29,0.12)` fond, `rgba(22,29,29,0.38)` texte |
| **Outlined** | pill, padding `9px 23px`, bordure `1px --outline`, texte `--primary` |
| **Text** | pill, padding `10px 12px`, texte `--primary` ; hover : `--primary-tint` |
| **Danger** | fond `--error`, texte `--on-error` |
| **CTA barre formulaire** | hauteur **52 px**, radius **14 px**, 16 px / 600, icône `check` |
| **CTA dialogue popup** | hauteur **42–48 px**, radius full, 14–15 px / 600 |

État loading bouton filled : spinner 18–20 px, bordure blanche semi-transparente.

État disabled bouton filled (tous contextes, popup compris) : fond `rgba(22,29,29,0.12)`, texte `rgba(22,29,29,0.38)`.

### 9.3 Avatar

| Taille | Dimensions | Texte initiale |
|---|---|---|
| Standard | 36 × 36 | 14 px / 600 |
| Grand (profil) | 84–88 × 88 | 28–32 px / 700 |
| Cluster | 34 × 34 | bordure `2px --bg-card`, chevauchement −8 px |

### 9.4 Carte (`Card`)

**Carte générique**
- Fond `--bg-card`, radius **12 px** (conteneur) ou **16 px** (section)
- Padding **16 px** (générique) ou **12–16 px** (listes)
- Ombre `--elev-1`
- Hover tuile liste : `color-mix(in srgb, var(--primary) 6%, transparent)`

**Carte voyage (liste)**
- Fond `--bg-card`, radius **12 px**, padding `12px 6px 12px 14px`, marge `0 16px 12px`
- Bordure `1px --divider` + ombre `0 1px 2px rgba(0,0,0,0.04)` (pas `--elev-1`)
- Accent gauche `border-left: 3px solid` selon période :
  - À venir → `--secondary`
  - En cours → `--primary`
  - Passé → `--neutral-mid` ; carte à `opacity: 0.92`
- Pas de fond teinté `tint-*` (remplacé par l'accent gauche)

### 9.5 Champ texte outlined (M3)

- Bordure repos : `1px --border-strong`, radius **4 px**
- Focus : `2px --primary`, padding réduit de 1 px
- Erreur : `2px --error`
- Label flottant : 12 px, fond = couleur scaffold derrière le label
- Texte saisi : 16 px / lh 24 px

### 9.6 Champ « input-shell » (formulaires Néon)

- Hauteur **52 px**, bordure **1.5 px** `--outline-variant`, radius **12 px**
- Focus : bordure **2 px** `--primary` + icône leading violette
- Erreur : bordure `--error`
- Icône leading : 18–20 px dans tuile ou inline

### 9.7 Switch

Deux variantes uniquement. Ne pas utiliser la piste générique `.switch` 46×26 / knob 20 (legacy handoff).

| Variante | Piste | Knob | ON |
|---|---|---|---|
| **Standard** (formulaires, options) | 46 × 28, radius full | 22 × 22, ombre `0 1px 3px rgba(0,0,0,0.2)` | fond `--primary` |
| **Compact** (filtre chip) | 38 × 22 | 16 × 16 | fond `--primary` |
| OFF (les deux) | `mix(--neutral-500 40%, transparent)` ou `--neutral-300` / `#E5E7EB` | blanc | — |
| Translation knob ON | `translateX(16px)` (compact) / `left` animé (standard) |

### 9.8 Segmented control (repas)

- Piste : `mix(--neutral-mid 12%, white)`, radius **10 px**, padding **4 px**
- Option sélectionnée : pastille blanche, texte `--primary`, ombre légère
- Icône sélectionnée : Rounded filled ; non sélectionnée : Outlined

### 9.9 Select / menu déroulant

- Shell : hauteur **48 px**, bordure **1.5 px**, radius **12 px**, chevron `expand_more`
- Menu : fond `--surface`, radius **4 px**, ombre `--elev-3`, item padding `12px 16px`

### 9.10 Option radio en carte (`name-opt`)

- Pleine largeur, bordure **1.5 px**, radius **12 px**
- Sélectionnée : bordure **2 px** `--primary`, fond `mix(--primary 6%, white)`, radio plein violet **22 px**

### 9.11 Liste / tuile (`ListTile`)

- Padding `12px 16px`, gap **16 px**
- Titre : 14 px / 500, ellipsis
- Sous-titre : 12 px / `--fg-2`
- Divider : `1px --divider`, marge horizontale **16 px**

### 9.12 Onglets horizontaux

- Padding onglet `12px 4px`, 13 px / 500 repos, **600** actif
- Inactif : `--fg-2` ; actif : `--primary`
- Indicateur : barre **2 px** haut, `left/right 16px`, `--primary`, coins supérieurs radius **2 px**
- Fond barre : `--bg-appbar` ou givré `rgba(255,255,255,0.55)` + `backdrop-filter: blur(2px)`

### 9.13 FAB

Deux rayons : **16 px** (`--radius-lg`) pour les FAB de liste et speed-dial ; **full** uniquement pour le FAB surélevé du bottom nav (§ 9.14).

| Type | Taille | Radius | Couleur |
|---|---|---|---|
| Standard (liste) | 56 × 56 | 16 px | `--primary` |
| Petit secondaire | 48 × 48 | 16 px | `--accent` ou `--secondary` |
| Speed-dial principal | 60 × 60 | 16 px | `--primary` ; ouvert → `--deep` + rotation 90° |
| Bottom nav Planning | 60 × 60 | full | dégradé `--primary` → `mix(--primary 78%, #000)` |

Position FAB liste : `right 16px`, `bottom 20–22px`.

### 9.14 Bottom navigation (voyage)

Barre horizontale fixe en bas de chaque écran voyage. Source handoff : package **bottom menu**.

- Hauteur barre **72 px**, fond `--bg-card`, ombre **`--elev-3`**, **overflow visible** (le FAB centre déborde)
- Layout flex horizontal, 5 enfants : tab · tab · **slot FAB centre** · tab · tab
- Flex onglets latéraux : `1` ; slot FAB centre : `1.1`
- **5 destinations** (gauche → droite) :

| Section | Icône Material Symbols | Notes |
|---|---|---|
| Aperçu | `dashboard` | onglet standard |
| Messagerie | `chat_bubble` | onglet standard |
| Planning | `event_available` | **FAB centre surélevé**, sans label |
| Dépenses | `payments` | onglet standard ; actif → `--accent` |
| Courses | `shopping_cart` | onglet standard |

**Onglet latéral (repos)**
- Layout vertical centré, gap **3 px**
- Icône Outlined **24 px**, `FILL 0, wght 400`
- Label **10.5 px / 600**, letter-spacing **0.1 px**, couleur `--neutral-500`
- Zone tactile ≥ **48 × 48 px**

**Onglet latéral (actif)**
- Icône Rounded filled : `FILL 1, wght 600, opsz 24`
- Couleur `--primary` ; **Dépenses** → `--accent`
- Indicateur : pilule **18 × 3 px**, `position absolute; top 6px`, `border-radius full`, `currentColor`
- Transition couleur : `--motion-fast` + `--ease-standard`

**FAB Planning (centre)**
- Taille **60 × 60 px**, `border-radius full`, position `left 50%`, `top -24px`, `transform translateX(-50%)`
- Fond : dégradé `150deg`, `--primary` → `mix(--primary 78%, #000)` (≈ `#5036AD`)
- Bordure **4 px** `#FFFFFF` ; icône `event_available` Rounded **27 px** blanche
- Ombre : `0 10px 22px -6px rgba(103,69,222,0.70), 0 2px 6px rgba(0,0,0,0.18)`
- Hover : `translateY(-2px)` ; transition `--motion-medium` + `--ease-emphasized`
- **Sélectionné** (Planning actif) : anneau `box-shadow: 0 0 0 3px #FFF, 0 0 0 6px --primary` + ombre violette ci-dessus

**Comportement** : une seule destination active ; tap → navigation + mise à jour de l’état actif.

### 9.15 Dialogue / bottom-sheet

| Élément | Spec |
|---|---|
| Overlay | `--bg-overlay` |
| Dialogue standard (M3) | radius **28 px**, padding **24 px**, max-width **320 px**, titre **400** |
| Dialogue d'action | radius **28 px**, padding **24–28 px**, max-width **384 px**, titre **600** avec en-tête icône |
| Bottom-sheet | coins supérieurs **28 px**, animation montée **250 ms** |
| Actions | alignées à droite, gap **6 px** |

### 9.16 Snackbar

- Position basse, marges **16 px**, fond `--inverse-surface`
- Radius **4 px**, ombre `--elev-3`, texte 14 px
- Animation entrée : translateY 20 px → 0, **250 ms** decelerate

### 9.17 Bandeau succès / info

- Fond `mix(--success 14%, --surface)` ou teinte sémantique équivalente
- Bordure `mix(--success 28%, transparent)`
- Icône `info` ou check dans pastille

### 9.18 Pastille d’action (accent secondaire)

- Hauteur **46 px**, radius **14 px**
- Fond `--primary-tint`, bordure `1px --primary-soft`, texte `--primary` 15 px / 600
- Hover : `mix(--primary 14%, --neutral-card)`

### 9.19 En-tête de marque (dégradé)

- Hauteur **66 px**
- Dégradé : `118deg, --deep 0% → --primary 72% → mix(--primary 55%, --secondary) 100%`
- Logo mosaïque 40 × 40, radius 12 px, tuiles `#6745DE` / `#FFD166` / `#4ECDC4` / `#FF6B6B`

### 9.20 Code OTP / invitation (segmenté)

- Cellule : **46 × 58 px**, bordure **1.5 px** `--border-subtle`, radius **12 px**
- Police Geist Mono **24 px** / 600
- Focus cellule : bordure **2 px** `--primary` + halo `0 0 0 4px mix(--primary 12%, transparent)`
- Séparateur groupes : tiret **12 × 2 px** `--border-strong`

### 9.21 Barre CTA épinglée (formulaires)

- Fond scaffold, bordure haute `1px --divider`
- Padding `12px 16px 18px`
- Layout deux boutons : Annuler (outlined) + action principale (filled)
- Bouton principal désactivé tant que formulaire non valide / non modifié (`dirty`)

### 9.22 État vide

- Centré, `--fg-2`, 14 px, lh 1.5, padding `48px 32px`

### 9.23 État désactivé (option admin)

- Carte fond grisé, textes et contrôles `--neutral-mid`, interactions bloquées

---

## 10. Dégradés récurrents

| Usage | Dégradé |
|---|---|
| Bannière sans photo | `140deg, --deep → --primary 60% → mix(--primary 55%, --secondary)` |
| Voile bannière | bas → haut : `mix(--deep 86%) → mix(--deep 42%) → transparent` |
| Photo couverture formulaire | `135deg, --primary → mix(--primary 70%, --accent)` |
| FAB nav | `150deg, --primary → mix(--primary 78%, #000)` |
| Scrim speed-dial | `rgba(31,21,71,0.30)` + blur léger |

---

## 11. Mapping Flutter (agent)

| Token handoff | Accès Flutter |
|---|---|
| `--primary` | `Theme.of(context).colorScheme.primary` |
| `--accent` | `colorScheme.tertiary` |
| `--secondary` | `colorScheme.secondary` |
| `--deep` | `colorScheme.onSurface` |
| `--primary-soft` | `colorScheme.tertiaryContainer` |
| `--secondary-container` | `colorScheme.secondaryContainer` |
| `--success` / `--warning` | `context.planerzColors.*` |
| Scaffold | `Theme.of(context).scaffoldBackgroundColor` |

Les teintes `color-mix` doivent être pré-calculées dans `BrandPaletteData` ou via `Color.alphaBlend` / `Color.lerp` équivalent.

---

## 12. Fichiers sources par package (inventaire)

| Package ZIP | Dossier handoff | Fichiers tokens / styles clés |
|---|---|---|
| accountpage | `design_handoff_account` | `colors_and_type.css`, `lib/app-styles.css`, `lib/screens.css` |
| bottom menu | `design_handoff_bottom_nav` | `reference/colors_and_type.css`, `code-reference.md` |
| trip-create-neon-only | `design_handoff_trip_create` | `reference/colors_and_type.css` (Néon seule), `app-styles.css`, `screens.css` |
| join-code-popup | `templates/code-invitation` | `CodeInvitation.dc.html` (inline styles) |
| join-trip | `design_handoff_join_trip` | `reference/join.css`, `SharedControls.jsx` |
| my-trips | `design_handoff_trips_page` | `lib/screens.css`, README détaillé |
| overview | `design_handoff_trip_overview` | `lib/app-styles.css`, `lib/screens.css` |
| params-move | `design_handoff_trip_settings_move` | `reference/screens.css` |
| participants | `design_handoff_trip_participants` | `lib/screens.css` |
| participant-preferences | `design_handoff_member_preferences` | `reference/prefs.css`, `PrefsControls.jsx` |

Fichier tokens de référence : `colors_and_type.css` — palette **Néon seule** dans tous les packages (y compris `trip-create-neon-only`, qui remplace l’ancien `create_trip.v2`).

Kit CSS partagé : viser **un seul** `app-styles.css` + `screens.css` canoniques (superset version participants/trips) — voir arbitrage n° 9 dans [`DESIGN_CHARTER_INCOHERENCES.md`](DESIGN_CHARTER_INCOHERENCES.md).
