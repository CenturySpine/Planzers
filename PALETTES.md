# Palettes de couleurs — Planzers

Définies dans `lib/app/theme/brand_palette.dart` · mappées dans `lib/app/theme/app_theme.dart` · palette active via `appPaletteProvider` (SharedPreferences `app_palette_id`).

**Règle de synchronisation :** toute modification de couleur ou ajout de champ dans `BrandPaletteData` / `PlanzersColors` doit être répercutée dans ce fichier.

> Les carrés de couleur sont rendus en HTML — ils s'affichent dans VS Code Markdown Preview et GitHub.

| Champ `BrandPaletteData` | Accesseur Flutter | Cupidon | Oligarch |
|---|---|---|---|
| `primary` | `colorScheme.primary` | <span style="display:inline-block;width:16px;height:16px;background:#97264E;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#97264E` | <span style="display:inline-block;width:16px;height:16px;background:#3A58F8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#3A58F8` |
| `primaryLight` | `colorScheme.primaryContainer` | <span style="display:inline-block;width:16px;height:16px;background:#E798DC;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E798DC` | <span style="display:inline-block;width:16px;height:16px;background:#BDE2F9;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#BDE2F9` |
| `primarySoft` | `colorScheme.tertiaryContainer` · `colorScheme.inversePrimary` | <span style="display:inline-block;width:16px;height:16px;background:#F3CDEE;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F3CDEE` | <span style="display:inline-block;width:16px;height:16px;background:#E5F2FD;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E5F2FD` |
| `accent` | `colorScheme.tertiary` | <span style="display:inline-block;width:16px;height:16px;background:#CF30B8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#CF30B8` | <span style="display:inline-block;width:16px;height:16px;background:#D44D00;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#D44D00` |
| `secondary` | `colorScheme.secondary` | <span style="display:inline-block;width:16px;height:16px;background:#7ECFDD;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#7ECFDD` | <span style="display:inline-block;width:16px;height:16px;background:#70CDC5;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#70CDC5` |
| `secondaryContainer` | `colorScheme.secondaryContainer` | <span style="display:inline-block;width:16px;height:16px;background:#CFEFF4;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#CFEFF4` | <span style="display:inline-block;width:16px;height:16px;background:#CFF5F0;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#CFF5F0` |
| `success` | `context.planzersColors.success` | <span style="display:inline-block;width:16px;height:16px;background:#4DC75E;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#4DC75E` | <span style="display:inline-block;width:16px;height:16px;background:#2EB37F;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#2EB37F` |
| `successContainer` | `context.planzersColors.successContainer` | <span style="display:inline-block;width:16px;height:16px;background:#E8F8EA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E8F8EA` | <span style="display:inline-block;width:16px;height:16px;background:#CCF5E4;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#CCF5E4` |
| `warning` | `context.planzersColors.warning` | <span style="display:inline-block;width:16px;height:16px;background:#AE8F56;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#AE8F56` | <span style="display:inline-block;width:16px;height:16px;background:#C49A00;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#C49A00` |
| `warningContainer` | `context.planzersColors.warningContainer` | <span style="display:inline-block;width:16px;height:16px;background:#F7EDDC;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F7EDDC` | <span style="display:inline-block;width:16px;height:16px;background:#FFF3CC;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFF3CC` |
| `deep` | `colorScheme.onSurface` | <span style="display:inline-block;width:16px;height:16px;background:#2E0B29;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#2E0B29` | <span style="display:inline-block;width:16px;height:16px;background:#2E206D;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#2E206D` |
| `surface` | `colorScheme.surface` | <span style="display:inline-block;width:16px;height:16px;background:#FFFBFE;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFFBFE` | <span style="display:inline-block;width:16px;height:16px;background:#FFFBFF;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FFFBFF` |
| `surfaceContainerHighest` | `colorScheme.surfaceContainerHighest` | <span style="display:inline-block;width:16px;height:16px;background:#E8D7E2;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E8D7E2` | <span style="display:inline-block;width:16px;height:16px;background:#DCE3FA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#DCE3FA` |
| `scaffoldBackground` | `Theme.of(ctx).scaffoldBackgroundColor` | <span style="display:inline-block;width:16px;height:16px;background:#F6EDF3;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F6EDF3` | <span style="display:inline-block;width:16px;height:16px;background:#F2F4FD;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#F2F4FD` |
| `appBarBackground` | `Theme.of(ctx).appBarTheme.backgroundColor` | <span style="display:inline-block;width:16px;height:16px;background:#E3D0DD;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#E3D0DD` | <span style="display:inline-block;width:16px;height:16px;background:#D2DAF8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#D2DAF8` |
| `onSurfaceVariant` | `colorScheme.onSurfaceVariant` | <span style="display:inline-block;width:16px;height:16px;background:#5C4B56;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#5C4B56` | <span style="display:inline-block;width:16px;height:16px;background:#483D6B;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#483D6B` |
| `outline` | `colorScheme.outline` | <span style="display:inline-block;width:16px;height:16px;background:#8A7582;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#8A7582` | <span style="display:inline-block;width:16px;height:16px;background:#6E6A8A;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#6E6A8A` |
| `outlineVariant` | `colorScheme.outlineVariant` | <span style="display:inline-block;width:16px;height:16px;background:#DCC8D4;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#DCC8D4` | <span style="display:inline-block;width:16px;height:16px;background:#C0BCDC;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#C0BCDC` |
| `inverseSurface` | `colorScheme.inverseSurface` | <span style="display:inline-block;width:16px;height:16px;background:#382D35;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#382D35` | <span style="display:inline-block;width:16px;height:16px;background:#2E206D;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#2E206D` |
| `onInverseSurface` | `colorScheme.onInverseSurface` | <span style="display:inline-block;width:16px;height:16px;background:#FDEEF8;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#FDEEF8` | <span style="display:inline-block;width:16px;height:16px;background:#EFF0FA;border-radius:3px;vertical-align:middle;border:1px solid #0002"></span> `#EFF0FA` |

---

## Accès dans le code

```dart
// ColorScheme standard
final cs = Theme.of(context).colorScheme;
cs.primary           // couleur principale
cs.tertiary          // accent
cs.secondaryContainer
cs.tertiaryContainer // = primarySoft
cs.surfaceContainerHighest

// Extension PlanzersColors (lib/app/theme/planzers_colors.dart)
final pz = context.planzersColors;
pz.success
pz.successContainer
pz.warning
pz.warningContainer

// Données brutes (pour construire le thème uniquement)
// AppPaletteId.cupidon.data  →  BrandPaletteData
```
