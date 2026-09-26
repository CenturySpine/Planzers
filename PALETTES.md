# Palette de couleurs — Planerz « Riviera »

Définie dans `lib/app/theme/app_tokens.dart` (`AppTokens`, source unique) · exposée via `BrandPaletteData.riviera` (`lib/app/theme/brand_palette.dart`) · mappée dans `lib/app/theme/app_theme.dart`. Couleurs métier : `lib/app/theme/activity_filter_colors.dart`.

**Règle de synchronisation :** toute modification de couleur ou ajout de champ dans `BrandPaletteData` / `PlanerzColors` / `AppTokens` doit être répercutée dans ce fichier.

## Règle d’usage (palette contenue)

- **Chrome = Lagon uniquement** : boutons, focus, sélection, liens, onglets, navigation.
- **Soleil** = surlignage joyeux et rare : logo, badges de non-lus, repère « aujourd’hui ». Jamais comme couleur de texte sur fond clair (contraste insuffisant) ; sa déclinaison lisible est `colorScheme.tertiary` `#B36B00`.
- **4 teintes métier** (+ Présence) : n’apparaissent **que** pour coder une catégorie (icône, point, puce de filtre).
- Tout le reste = encre + neutres. Erreur/danger = `error` (jamais une teinte de marque).

## Palette de marque (`BrandPaletteData.riviera`)

| Champ `BrandPaletteData` | Accesseur Flutter | Riviera | Rôle |
|---|---|---|---|
| `primary` | `colorScheme.primary` | <span style="display:inline-block;width:16px;height:16px;background:#0B8579;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#0B8579` | Lagon — seule couleur de « chrome » (CTA, focus, sélection, liens, navigation) |
| `primaryLight` | `colorScheme.primaryContainer` | <span style="display:inline-block;width:16px;height:16px;background:#D5EFEB;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#D5EFEB` | Conteneur primaire (tuiles sélectionnées) |
| `primarySoft` | `—  (AppTokens.primaryTint)` | <span style="display:inline-block;width:16px;height:16px;background:#EAF6F4;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#EAF6F4` | Teinte très douce (fonds sélectionnés, pastilles) |
| `accent` | `AppTokens.accent · badges` | <span style="display:inline-block;width:16px;height:16px;background:#FFB938;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFB938` | Soleil — surlignage parcimonieux (logo, badges, « aujourd’hui »), jamais en texte |
| `secondary` | `colorScheme.secondary` | <span style="display:inline-block;width:16px;height:16px;background:#5FC7BA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#5FC7BA` | Teinte décorative dérivée de Lagon |
| `secondaryContainer` | `colorScheme.secondaryContainer` | <span style="display:inline-block;width:16px;height:16px;background:#E6F6F3;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E6F6F3` | Conteneur secondaire |
| `info` | `context.planerzColors.info` | <span style="display:inline-block;width:16px;height:16px;background:#1F84D6;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#1F84D6` | Information |
| `infoContainer` | `context.planerzColors.infoContainer` | <span style="display:inline-block;width:16px;height:16px;background:#E4F1FC;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E4F1FC` | Fond information |
| `success` | `context.planerzColors.success` | <span style="display:inline-block;width:16px;height:16px;background:#178A55;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#178A55` | Succès |
| `successContainer` | `context.planerzColors.successContainer` | <span style="display:inline-block;width:16px;height:16px;background:#E0F4EA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E0F4EA` | Fond succès |
| `warning` | `context.planerzColors.warning` | <span style="display:inline-block;width:16px;height:16px;background:#B77B00;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#B77B00` | Avertissement |
| `warningContainer` | `context.planerzColors.warningContainer` | <span style="display:inline-block;width:16px;height:16px;background:#FFF4D6;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFF4D6` | Fond avertissement |
| `deep` | `colorScheme.onSurface` | <span style="display:inline-block;width:16px;height:16px;background:#17213A;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#17213A` | Encre — texte principal et titres |
| `surface` | `colorScheme.surface` | <span style="display:inline-block;width:16px;height:16px;background:#FFFFFF;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFFFFF` | Cartes, barres, feuilles |
| `surfaceContainerHighest` | `colorScheme.surfaceContainerHighest` | <span style="display:inline-block;width:16px;height:16px;background:#EEF0F3;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#EEF0F3` | Surfaces neutres (capsules, pistes) |
| `scaffoldBackground` | `scaffoldBackgroundColor` | <span style="display:inline-block;width:16px;height:16px;background:#F5F6F8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F5F6F8` | Fond d’écran |
| `appBarBackground` | `appBarTheme.backgroundColor` | <span style="display:inline-block;width:16px;height:16px;background:#FFFFFF;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFFFFF` | En-têtes (filet bas #E2E5EA) |
| `onSurfaceVariant` | `colorScheme.onSurfaceVariant` | <span style="display:inline-block;width:16px;height:16px;background:#566074;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#566074` | Texte secondaire |
| `outline` | `colorScheme.outline` | <span style="display:inline-block;width:16px;height:16px;background:#8891A1;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#8891A1` | Texte tertiaire, icônes inactives |
| `outlineVariant` | `colorScheme.outlineVariant` | <span style="display:inline-block;width:16px;height:16px;background:#E2E5EA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E2E5EA` | Bordures et séparateurs |
| `inverseSurface` | `colorScheme.inverseSurface` | <span style="display:inline-block;width:16px;height:16px;background:#1E2840;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#1E2840` | SnackBars, tooltips |
| `onInverseSurface` | `colorScheme.onInverseSurface` | <span style="display:inline-block;width:16px;height:16px;background:#F2F4F8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F2F4F8` | Texte sur surface inverse |

## Sémantiques hors palette

| Token | Valeur | Rôle |
|---|---|---|
| `AppTokens.error` / `colorScheme.error` | <span style="display:inline-block;width:16px;height:16px;background:#D0334A;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#D0334A` | Erreurs, actions destructrices |
| `AppTokens.errorContainer` | <span style="display:inline-block;width:16px;height:16px;background:#FDE7EA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FDE7EA` | Fond erreur |
| `colorScheme.tertiary` | <span style="display:inline-block;width:16px;height:16px;background:#B36B00;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#B36B00` | Déclinaison lisible de Soleil (icônes/texte) |

## Couleurs métier (`ActivityFilterGroup`)

| Catégorie | `filterColor` | `filterLightBgColor` | `filterInkColor` | Icône |
|---|---|---|---|---|
| Repas | <span style="display:inline-block;width:16px;height:16px;background:#F2891F;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F2891F` | <span style="display:inline-block;width:16px;height:16px;background:#FFF1E2;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFF1E2` | <span style="display:inline-block;width:16px;height:16px;background:#A35200;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#A35200` | `restaurant_rounded` |
| Nuits | <span style="display:inline-block;width:16px;height:16px;background:#5B5BD6;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#5B5BD6` | <span style="display:inline-block;width:16px;height:16px;background:#ECECFB;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#ECECFB` | <span style="display:inline-block;width:16px;height:16px;background:#4343B8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#4343B8` | `bedtime_rounded` |
| Loisirs | <span style="display:inline-block;width:16px;height:16px;background:#DB3F76;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#DB3F76` | <span style="display:inline-block;width:16px;height:16px;background:#FCE8EF;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FCE8EF` | <span style="display:inline-block;width:16px;height:16px;background:#B42A5C;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#B42A5C` | `local_activity_rounded` |
| Trajets | <span style="display:inline-block;width:16px;height:16px;background:#1F84D6;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#1F84D6` | <span style="display:inline-block;width:16px;height:16px;background:#E4F1FC;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E4F1FC` | <span style="display:inline-block;width:16px;height:16px;background:#1667A8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#1667A8` | `commute_rounded` |
| Présence (`PresenceCategoryColors`) | <span style="display:inline-block;width:16px;height:16px;background:#0B8579;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#0B8579` | <span style="display:inline-block;width:16px;height:16px;background:#EAF6F4;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#EAF6F4` | <span style="display:inline-block;width:16px;height:16px;background:#086B61;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#086B61` | `groups_rounded` |

> Les carrés de couleur sont rendus en HTML — ils s’affichent dans VS Code Markdown Preview et GitHub.

## Accès dans le code

```dart
// Tokens bruts (couleurs, rayons, densité)
AppTokens.primary; AppTokens.deep; AppTokens.radiusMd;

// ColorScheme standard
final cs = Theme.of(context).colorScheme;
cs.primary; cs.primaryContainer; cs.surfaceContainerHighest; cs.error;

// Extension PlanerzColors
final pz = context.planerzColors;
pz.info; pz.success; pz.warning;

// Couleurs métier
ActivityFilterGroup.repas.filterColor;
```
