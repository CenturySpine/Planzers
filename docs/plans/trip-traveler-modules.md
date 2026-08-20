# Modules "voyageur" (Ridgegear + Wallet) — structure, permissions, UI

## Contexte

Aujourd'hui, les modules de la page voyage (Planning, Hébergement,
Covoiturage, Jeux, Photos) sont tous **configurés par l'admin/créateur du
voyage** et visibles par tout le monde. On introduit une nouvelle catégorie :
les **modules "voyageur"** — activables par n'importe quel participant, pour
lui-même uniquement, indépendamment de la config admin du voyage, et
**visibles seulement par celui qui les a activés**.

Deux premiers modules voyageur :
- **Ridgegear** : une fois le compte connecté (mécanisme déjà existant,
  écran "Comptes externes connectés"), affiche le poids du sac dans le
  cartouche ; le tap ouvre la webapp Ridgegear dans un nouvel onglet.
- **Wallet** : espace personnel de documents (billets, QR codes, photos de
  réservation...) visible uniquement par son propriétaire ; le tap ouvre une
  page dédiée listant les documents.

**Décisions produit confirmées avec toi** :
- Le **wallet reste une maquette statique** ce chantier-ci (liste factice,
  pas d'upload/stockage réel — le vrai stockage sera pensé séparément).
- **Pas de sélecteur de projet Ridgegear** pour l'instant (question ouverte,
  non résolue : est-ce à Planerz d'implémenter un sélecteur par fournisseur,
  ou au fournisseur d'exposer son propre contrôle de sélection ? — à trancher
  au chantier d'intégration réelle). Le module affiche un projet fixe codé en
  dur.
- **La navigation au tap est réelle dès maintenant** : Ridgegear ouvre une
  URL en dur (`https://ridgegear.centuryspine.org`) dans un nouvel onglet ;
  Wallet navigue vers une vraie page (avec un contenu factice).
- Le poids du sac (Ridgegear) et le nombre de documents (Wallet) affichés
  dans les cartouches sont des **données en dur** — aucun branchement réel
  cette fois-ci.

**Portée** : structure de données, règles Firestore, activation/désactivation
réelle (ça, ce n'est pas du mock — c'est littéralement "la structure"), et
les contrôles visuels. Le *contenu* affiché par chaque module (poids,
documents) reste factice.

## Modèle de données

Nouvelle sous-collection, **par participant, illisible par les autres** (à
la différence de `participants/{id}` qui est lisible par tout le voyage) :

**`trips/{tripId}/travelerModules/{uid}`**
```
{
  ridgegearEnabled: bool,
  walletEnabled: bool,
  updatedAt: serverTimestamp,
}
```
Document absent = aucun module voyageur activé (état par défaut, pas besoin
de créer un doc vide à la création du voyage).

### Règles Firestore (`firestore.rules`, dans le bloc `match /trips/{tripId}`)

```
match /travelerModules/{uid} {
  allow read: if isTripMember(tripId) && uid == request.auth.uid;
  allow create, update: if isTripMember(tripId) && uid == request.auth.uid
    && request.resource.data.keys().hasOnly(
      ['ridgegearEnabled', 'walletEnabled', 'updatedAt']
    )
    && request.resource.data.ridgegearEnabled is bool
    && request.resource.data.walletEnabled is bool;
  allow delete: if false;
}
```
Écriture client directe (pas de callable) — comme `members/{memberId}`, pas
besoin de logique serveur pour un simple toggle self-service.

## Flutter — data layer

Nouveau fichier **`lib/features/trips/data/traveler_modules_repository.dart`**,
même style que `cupidon_repository.dart` :
- `TravelerModules { ridgegearEnabled, walletEnabled }` (modèle immuable,
  `fromMap`/valeurs par défaut `false`).
- `watchMyTravelerModules(tripId)` → `Stream<TravelerModules>` filtré sur
  `trips/{tripId}/travelerModules/{myUid}` (`snapshots().map(...)`, doc
  absent → `TravelerModules()` par défaut).
- `setModuleEnabled(tripId, {required bool? ridgegearEnabled, required bool? walletEnabled})`
  → `set(..., SetOptions(merge: true))` avec `updatedAt: FieldValue.serverTimestamp()`.
- Provider Riverpod `travelerModulesRepositoryProvider` +
  `myTravelerModulesStreamProvider(tripId)` (`StreamProvider.autoDispose.family`).

## Flutter — UI

### Widget partagé : sélecteur de modules voyageur

Nouveau **`_TravelerModulesToggleList`** (widget privé réutilisé aux deux
points d'entrée demandés), une colonne de lignes à bascule (icône + libellé +
`Switch`), une par module voyageur disponible (Ridgegear, Wallet), lisant
`myTravelerModulesStreamProvider` et écrivant via `setModuleEnabled` au
toggle. Style Néon (mêmes tokens que le reste de l'écran voyage).

**Point d'entrée 1 — carte "+" de l'aperçu voyage**
(`trip_overview_page.dart`, remplace le stub actuel lignes 1018-1031) :
- Visibilité : **tout participant** (`_trip.memberUserIds.contains(myUid)`),
  plus `canManageTripSettings` n'est plus la condition — un simple
  participant doit pouvoir ajouter ses modules personnels même s'il ne gère
  pas les réglages du voyage.
- Tap → `showModalBottomSheet` affichant `_TravelerModulesToggleList`.

**Point d'entrée 2 — réglages du voyage**
(`lib/features/trips/presentation/trip_member_preferences_page.dart`) :
nouvelle section "Mes modules personnels" avec le même
`_TravelerModulesToggleList`, en écriture immédiate (pas couplé au mécanisme
de brouillon/sauvegarde existant de Cupidon sur cette page — c'est un état
indépendant).

### Cartouches sur l'aperçu voyage

Ajoutées après le cartouche Photos, avant la carte "+"
(`trip_overview_page.dart`, style identique aux 5 cartouches existantes) :

```dart
if (myTravelerModules.ridgegearEnabled) ...[
  const SizedBox(height: 10),
  TripOverviewModuleCard(
    label: l10n.tripOverviewTileRidgegear,
    icon: Icons.backpack_outlined,
    count: 0,
    showCount: false,
    tileColor: NeonPalette.overviewModuleRidgegearTile,
    inkColor: NeonPalette.overviewModuleRidgegearInk,
    statusText: l10n.tripOverviewRidgegearPackWeight('12,4'), // en dur
    onTap: () => launchUrl(
      Uri.parse('https://ridgegear.centuryspine.org'),
      mode: LaunchMode.platformDefault,
    ),
  ),
],
if (myTravelerModules.walletEnabled) ...[
  const SizedBox(height: 10),
  TripOverviewModuleCard(
    label: l10n.tripOverviewTileWallet,
    icon: Icons.folder_special_outlined,
    count: 3, // en dur
    tileColor: NeonPalette.overviewModuleWalletTile,
    inkColor: NeonPalette.overviewModuleWalletInk,
    statusText: l10n.tripOverviewWalletDocumentCount(3), // en dur
    onTap: () => context.push('/trips/${_trip.id}/wallet'),
  ),
],
```
`myTravelerModules` vient de
`ref.watch(myTravelerModulesStreamProvider(_trip.id)).asData?.value ?? const TravelerModules()`,
ajouté au bloc de `ref.watch(...)` existant (lignes ~608-627).

Nouveaux tokens dans **`lib/app/theme/neon_palette.dart`** (à côté des
`overviewModule*` existants), suivant le même style `Color.lerp` :
```dart
static Color get overviewModuleRidgegearTile => Color.lerp(surface, secondary, 0.20)!;
static Color get overviewModuleRidgegearInk => Color.lerp(deep, secondary, 0.70)!;
static Color get overviewModuleWalletTile => Color.lerp(surface, accent, 0.12)!;
static Color get overviewModuleWalletInk => Color.lerp(accent, deep, 0.35)!;
```

### Page "Mes documents" (Wallet)

Nouvelle page **`lib/features/trips/presentation/trip_wallet_page.dart`**,
route `/trips/{tripId}/wallet` (ajoutée dans `lib/app/router.dart`, même
style que les autres routes `/trips/:tripId/...`). Contenu : liste factice
codée en dur (3 éléments avec icône selon type, nom, date), un bouton
"Ajouter un document" désactivé/stub affichant
`l10n.tripOverviewTileComingSoon` (clé déjà existante) au tap. Style Néon
(`Theme(data: NeonPalette.overlayOn(...))`), cohérent avec les autres pages
voyage.

## l10n

Nouvelles clés dans les 4 fichiers ARB de référence
(`app_fr.arb`/`app_fr_FR.arb`/`app_en.arb`/`app_en_US.arb`), style des clés
`tripOverviewTile*` existantes :
- `tripOverviewTileRidgegear` ("Ridgegear")
- `tripOverviewTileWallet` ("Mes documents")
- `tripOverviewRidgegearPackWeight` (placeholder `{weight}`, ex. "Poids du sac : {weight} kg")
- `tripOverviewWalletDocumentCount` (placeholder `{count}`, pluriel, ex. "{count} document(s)")
- `tripTravelerModulesSectionTitle` ("Mes modules personnels")
- `tripTravelerModulesRidgegearLabel` / `tripTravelerModulesWalletLabel`
- `tripWalletPageTitle` ("Mes documents")
- `tripWalletAddDocument` ("Ajouter un document")

Réutilisation de clés existantes : `tripOverviewAddModule`,
`tripOverviewTileComingSoon`.

## Vérification

- `flutter analyze` sur les fichiers touchés/ajoutés.
- Test manuel via la preview locale (émulateurs ou `planerz-preview`) :
  activer Ridgegear + Wallet depuis la carte "+", vérifier l'apparition des
  2 cartouches avec données en dur, vérifier le tap (nouvel onglet Ridgegear
  / navigation page Wallet), désactiver depuis les réglages du voyage,
  vérifier la disparition. Vérifier avec un 2ᵉ compte participant que ses
  modules personnels n'apparaissent pas chez le 1er utilisateur (et
  inversement) — le point clé de ce chantier (isolation par utilisateur).
- Pas de déploiement Firestore rules nécessaire pour tester en émulateur ;
  pour tester sur `planerz-preview` réel, déploiement des règles requis
  (`firebase deploy --only firestore:rules --project planerz-preview` — à
  faire par toi, comme toujours).
