---
name: Documents personnels (Wallet) — stockage réel, fichiers et codes-barres
overview: Remplacer la maquette « Mes documents » par un vrai coffre personnel par voyage — import de fichiers (PDF, images), capture de QR codes / codes-barres à la caméra, nom + catégorie avec icône, consultation plein écran, visible uniquement par son propriétaire.
todos:
  - id: spike-scan-web
    content: "Lot 0 — Spike technique : scan caméra sur web (PWA iOS/Android), décodage d'un code depuis une image sur web, formats Aztec/PDF417"
    status: pending
  - id: data-rules
    content: "Lot 1 — Modèle Firestore walletDocuments + règles Firestore + règles Storage (owner-only) + repository/providers"
    status: pending
  - id: list-real-data
    content: "Lot 2 — Liste réelle sur TripWalletPage + compteur réel sur la tuile de l'aperçu + état vide"
    status: pending
  - id: add-file
    content: "Lot 3 — Écran d'ajout d'un fichier (nom, catégorie, fichier) avec upload et progression"
    status: pending
  - id: viewer-edit-delete
    content: "Lot 4 — Consultation (image plein écran, PDF dans le navigateur), renommage/recatégorisation, suppression"
    status: pending
  - id: barcode-scan
    content: "Lot 5 — Scan caméra d'un QR code / code-barres, stockage du contenu, affichage plein écran régénéré"
    status: pending
  - id: barcode-from-image
    content: "Lot 6 (conditionnel au spike) — Extraction du code depuis une capture d'écran importée"
    status: pending
  - id: cleanup-functions
    content: "Lot 7 — Nettoyage Storage à la sortie / suppression du voyage (Cloud Functions)"
    status: pending
  - id: l10n-tests-analyze
    content: "Transverse — Clés l10n (4 ARB), suppression des clés maquette obsolètes, tests, flutter analyze"
    status: pending
isProject: false
---

# Documents personnels (Wallet) — plan d'implémentation

## 1. Reformulation de la demande

Aujourd'hui, le module voyageur **« Mes documents »** (activable par chaque
participant depuis l'aperçu du voyage, visible seulement par lui) ouvre
`TripWalletPage`, qui n'affiche que trois documents factices ; la tuile de
l'aperçu affiche un compteur codé en dur (`3`).

Objectif : en faire un **vrai coffre de documents de voyage personnel** :

1. **Ajouter un fichier** : PDF, image (photo, capture d'écran)… stocké côté
   serveur (Firebase Storage) et référencé en base (Firestore).
2. **Ajouter un QR code** en le scannant avec la caméra du téléphone ; le code
   est ensuite consultable dans la page documents (pour le présenter à un
   contrôleur, à l'embarquement, à l'hôtel…).
3. Chaque document porte au minimum un **nom** et une **catégorie** (billet
   d'avion, de train…), la catégorie donnant une **icône** dans la liste.
4. Le but : **avoir tous les documents du voyage sous la main**, au même
   endroit, au moment où on en a besoin.

Ce que ça implique concrètement : un modèle de données, des règles de sécurité
Firestore **et** Storage, un flux d'ajout (fichier ou scan), une consultation
plein écran, l'édition/suppression, et le nettoyage des fichiers quand le
voyage disparaît ou que le participant le quitte.

## 2. Points de challenge (à lire avant de valider)

### 2.1 Planerz est désormais une **web app** d'abord
L'app Android native est décommissionnée (`AndroidSunsetGate`) : la cible
principale est la **PWA dans le navigateur mobile**. Ça change plusieurs
choses par rapport à une intuition « app native » :

- **Scan caméra dans un navigateur** : faisable (`getUserMedia`, HTTPS
  obligatoire — déjà le cas), via le package `mobile_scanner` qui a un support
  web. Mais c'est moins fluide qu'en natif (permission caméra redemandée selon
  le navigateur, comportement variable en PWA iOS installée). → **Spike
  obligatoire (Lot 0)** avant de s'engager.
- **Luminosité de l'écran** : en natif on pousse la luminosité au max quand on
  affiche un QR code ; **c'est impossible depuis un navigateur**. On compense
  par un affichage noir sur blanc plein écran, grand format.
- **Hors-ligne** : Firestore web n'a pas de persistance disque activée dans le
  projet, et les fichiers Storage ne sont pas mis en cache de façon fiable.
  Autrement dit, **à l'aéroport sans réseau, rien ne garantit que le document
  s'ouvre**. C'est le vrai point faible d'un « wallet » web. Recommandation :
  l'assumer en V1 (en ligne requis) et traiter le hors-ligne comme un chantier
  dédié (cache navigateur / IndexedDB), plutôt que de bricoler maintenant.

### 2.2 « Scanner un QR code » ≠ « stocker une image de QR code »
Scanner un code à la caméra récupère **son contenu** (une chaîne de
caractères), pas une photo. Pour le présenter ensuite, on **régénère** le code
à l'écran à partir de ce contenu (rendu net, parfaitement lisible par un
lecteur). C'est l'approche recommandée : légère (quelques octets en base),
nette, et lisible hors-ligne dès que le hors-ligne existera.

Attention aux formats : beaucoup de titres de transport **ne sont pas des QR
codes** — carte d'embarquement (PDF417 ou Aztec), billets SNCF/Eurostar
(Aztec), certains billets de concert (Code 128). Il faut donc gérer **les
codes-barres courants**, pas seulement le QR, et **mémoriser le format** pour
pouvoir le régénérer à l'identique. Le package `barcode_widget` sait dessiner
QR, Aztec, PDF417, DataMatrix, Code 128, EAN.

### 2.3 Le cas d'usage réel : le billet est **déjà dans le téléphone**
En pratique, le billet arrive par e-mail (PDF) ou dans une app de compagnie.
On ne peut pas scanner à la caméra l'écran du téléphone qu'on tient dans la
main. Les deux vrais parcours sont donc :

1. **Importer le PDF / la capture d'écran telle quelle** (Lot 3) — couvre
   100 % des cas, sans magie. C'est la priorité.
2. **Scanner à la caméra** un billet papier ou affiché sur un autre écran
   (Lot 5).
3. *(Bonus)* **Extraire le code d'une capture d'écran importée** (Lot 6) —
   très pratique, mais sur web le décodage depuis une image n'est pas couvert
   par `mobile_scanner` : il faudra une librairie de décodage (port Dart de
   ZXing ou librairie JS). Conditionné au spike.

Recommandation : livrer 1 puis 2 ; 3 seulement si le spike est concluant.

### 2.4 « À peu près n'importe quel document »
Recommandation : **liste blanche** en V1 — PDF, JPEG, PNG, WebP, HEIC —
avec une **taille max de 15 Mo par fichier** et un **plafond de documents par
voyage** (ex. 50). Raisons : un navigateur ne sait afficher que ces formats
sans app tierce, les règles Storage peuvent vérifier type et taille, et ça
évite de transformer le module en drive générique (coûts Storage). HEIC n'est
affichable que sur Safari : on l'accepte mais on le traite comme « fichier à
ouvrir » ailleurs. Les fichiers `.pkpass` (Apple/Google Wallet), `.docx`, etc.
sont hors périmètre V1.

### 2.5 Données sensibles
On parle de passeports, cartes d'identité, attestations d'assurance. Deux
points de vigilance :

- **Faille à éviter dans `storage.rules`** : la règle générique
  `match /trips/{tripId}/{allPaths=**}` autorise **tout participant** à lire
  tout ce qui est sous `trips/{tripId}/`. Les règles Storage s'additionnent
  (il suffit qu'une règle autorise) : ranger les documents perso sous
  `trips/{tripId}/wallet/...` les rendrait **lisibles par tout le voyage**,
  quelle que soit la règle spécifique ajoutée. → On range les fichiers sous
  **`users/{uid}/wallet/{tripId}/...`**, déjà limité au propriétaire.
- La règle actuelle `users/{uid}/{allPaths=**}` n'a **ni limite de taille ni
  de type**. Il faut la resserrer (photo de profil d'un côté, wallet de
  l'autre), sinon les contrôles du wallet sont contournables.
- Pas de chiffrement de bout en bout en V1 : les fichiers sont protégés par
  les règles d'accès Firebase (comme tout le reste de l'app), pas chiffrés
  côté client. Si le besoin existe, c'est un chantier à part entière.

### 2.6 Périmètre : documents **par voyage**
La demande et le module existant sont par voyage. Un passeport serait
pourtant utile dans tous les voyages. Recommandation : rester **par voyage**
en V1 (simple, cohérent avec le module voyageur) ; un futur « coffre
personnel global » réutilisable entre voyages pourra venir ensuite — le
chemin Storage `users/{uid}/...` ne l'empêche pas.

### 2.7 Partage avec d'autres participants
Hors périmètre : un document reste strictement personnel. Le cas « un billet
de groupe pour 4 personnes » n'est pas couvert en V1.

## 3. Décisions à confirmer par le product owner

| # | Question | Recommandation |
|---|----------|----------------|
| D1 | Permission dédiée pour les actions du wallet (ajout/suppression) ? | **Non** : module strictement personnel, seul le propriétaire agit. Pas d'entrée dans les permissions du voyage. |
| D2 | Liste des catégories | Fixe, définie dans le code : Avion, Train, Bus/car, Bateau, Hébergement, Location de véhicule, Activité/billet, Identité, Assurance/santé, Autre. |
| D3 | Champs d'un document | Nom (obligatoire), catégorie (obligatoire, « Autre » par défaut). **Date optionnelle** (date du trajet/de l'événement) pour trier la liste chronologiquement — à confirmer. |
| D4 | Types et taille de fichiers | Liste blanche PDF + images, 15 Mo max, 50 documents max par voyage. |
| D5 | Stratégie de sauvegarde | Écran d'ajout/édition avec **bouton de validation explicite** (pas d'enregistrement à la volée), comme les autres formulaires plein écran (covoiturage). |
| D6 | Hors-ligne | Hors V1, chantier dédié. |
| D7 | Extraction du code depuis une capture | Conditionnée au spike (Lot 0). |
| D8 | Désactivation du module | Désactiver le module **masque** les documents mais **ne les supprime pas** (réactivation = on les retrouve). |

## 4. Modèle de données

### Firestore — sous-collection sous le doc du module voyageur

**`trips/{tripId}/travelerModules/{uid}/walletDocuments/{documentId}`**

```
{
  name: string,                 // 1..80 caractères, obligatoire
  category: string,             // enum : plane | train | bus | boat | lodging |
                                //        vehicleRental | activity | identity |
                                //        insurance | other
  kind: string,                 // 'file' | 'barcode'
  eventDate: timestamp?,        // optionnel (D3)

  // si kind == 'file'
  file: {
    storagePath: string,        // users/{uid}/wallet/{tripId}/{documentId}.{ext}
    contentType: string,        // application/pdf, image/jpeg, ...
    sizeBytes: number,
    originalFileName: string,
  },

  // si kind == 'barcode'
  barcode: {
    format: string,             // qrCode | aztec | pdf417 | dataMatrix | code128 | ean13 | ...
    payload: string,            // contenu brut du code (max ~4 Ko)
  },

  createdAt: serverTimestamp,
  updatedAt: serverTimestamp,
}
```

Pourquoi sous `travelerModules/{uid}` : les règles « propriétaire uniquement »
existent déjà à ce niveau, et `recursiveDelete` de `deleteTripCascade` efface
automatiquement la sous-collection à la suppression du voyage.

Pas d'URL de téléchargement stockée en base : on la demande à Storage au
moment de l'affichage (`getDownloadURL`), ce qui évite de figer un jeton
d'accès dans Firestore.

### Storage

**`users/{uid}/wallet/{tripId}/{documentId}.{ext}`**, avec métadonnées
`tripId` et `documentId`.

### Règles Firestore (`firestore.rules`, dans `match /travelerModules/{uid}`)

```
match /walletDocuments/{documentId} {
  allow read, delete: if isTripMember(tripId) && uid == request.auth.uid;
  allow create, update: if isTripMember(tripId) && uid == request.auth.uid
    && isValidWalletDocument(request.resource.data);
}
```

`isValidWalletDocument` vérifie : clés autorisées (`hasOnly`), `name` string
1..80, `category` dans l'enum, `kind` dans `['file', 'barcode']`, présence du
bon sous-objet selon `kind`, `barcode.payload` ≤ 4096 caractères,
`file.storagePath` commençant par `users/<uid>/wallet/<tripId>/`. En `update`,
`kind`, `file` et `barcode` sont **immuables** (on ne remplace pas le fichier
d'un document ; on en crée un autre).

### Règles Storage (`storage.rules`)

- Remplacer `match /users/{uid}/{allPaths=**}` par deux règles ciblées :
  - `users/{uid}/{fileName}` (photos de profil actuelles, `profile_*`) :
    comportement inchangé pour le propriétaire, + limite image/taille.
  - `users/{uid}/wallet/{tripId}/{fileName}` :
    - `read`, `delete` : propriétaire uniquement ;
    - `create` : propriétaire **et** membre du voyage (`isTripMember(tripId)`),
      `size < 15 Mo`, `contentType` dans la liste blanche, nom de fichier
      `[A-Za-z0-9._-]+` ;
    - `update` : interdit (un fichier ne se remplace pas).
- **Vérifier avant de toucher la règle `users/`** l'arborescence réellement
  utilisée par les photos de profil (`account_repository.dart`) pour ne rien
  casser.

## 5. Flutter

### Dépendances à ajouter
- `file_picker` — sélection de PDF/fichiers (web + mobile ; `image_picker`
  déjà présent ne gère que les images).
- `mobile_scanner` — scan caméra (web + mobile).
- `barcode_widget` — rendu des codes QR/Aztec/PDF417/… à l'écran.
- *(Lot 6, si retenu)* une librairie de décodage depuis image, choisie au
  spike.

Natif (si iOS reste un canal) : `NSCameraUsageDescription` dans
`ios/Runner/Info.plist`. Android étant décommissionné, pas de permission
caméra à ajouter côté Android.

### Arborescence
Nouveau dossier **`lib/features/wallet/`** (le module grossit trop pour rester
dans `trips/presentation`) :

```
lib/features/wallet/
  data/
    wallet_document.dart            // modèle immuable + fromMap/toMap
    wallet_document_category.dart   // enum + icône + clé l10n
    wallet_repository.dart          // CRUD Firestore + upload/suppression Storage
  presentation/
    trip_wallet_page.dart           // liste (déplacée depuis trips/presentation)
    wallet_document_form_page.dart  // ajout/édition (plein écran)
    wallet_barcode_scan_page.dart   // caméra
    wallet_document_viewer_page.dart// image / code-barres plein écran
```

`trip_wallet_page.dart` actuel est supprimé (et la route `wallet` dans
`router.dart` repointe vers la nouvelle page).

### Repository / providers (même style que `traveler_modules_repository.dart`)
- `walletRepositoryProvider`
- `myWalletDocumentsStreamProvider(tripId)` — `StreamProvider.autoDispose.family`,
  trié par `eventDate` puis `createdAt`.
- `addFileDocument(tripId, name, category, eventDate?, bytes, fileName, contentType)` :
  génère l'id Firestore, upload Storage (`putData`, progression exposée),
  puis écrit le doc Firestore. En cas d'échec de l'écriture Firestore, on
  supprime le fichier uploadé (pas d'orphelin).
- `addBarcodeDocument(tripId, name, category, eventDate?, format, payload)`.
- `updateDocumentMetadata(tripId, documentId, name, category, eventDate?)`.
- `deleteDocument(tripId, document)` : suppression Firestore puis Storage
  (best effort).

### UI
- **Liste** (`TripWalletPage`) : cartes existantes conservées (icône de
  catégorie dans le cercle, nom en titre, date / type en sous-titre). État
  vide. Bouton `+` → petit menu : « Importer un fichier » / « Scanner un
  code ».
- **Tuile aperçu** (`trip_overview_page.dart`) : compteur réel à partir du
  stream (remplace le `3` codé en dur).
- **Formulaire** (plein écran, validation explicite — D5) : nom, catégorie
  (sélecteur avec icônes), date optionnelle, aperçu du fichier ou du code
  scanné. Pré-remplissage du nom avec le nom du fichier importé.
- **Consultation** :
  - image → plein écran zoomable (`InteractiveViewer`) ;
  - PDF → ouverture dans un nouvel onglet via `url_launcher` (le navigateur
    affiche le PDF nativement ; pas de lecteur PDF embarqué en V1) ;
  - code-barres → plein écran fond blanc, code régénéré au format d'origine,
    nom du document au-dessus, contenu texte copiable en dessous.
- Tap sur une carte → consultation ; édition et suppression depuis l'écran de
  consultation (cohérent avec le covoiturage : pas de suppression directe en
  liste), suppression avec confirmation.
- Aucun texte d'aide ou d'astuce ajouté au-delà des libellés nécessaires
  (règle « UI copy scope »).

## 6. Cloud Functions (région `europe-west9`)

- **`deleteTripCascade`** : Firestore déjà couvert par `recursiveDelete`.
  Ajouter la suppression Storage des préfixes
  `users/{memberUid}/wallet/{tripId}/` pour chaque membre du voyage.
- **`leaveTrip`** : supprimer les documents wallet du participant qui part
  (Firestore `travelerModules/{uid}/walletDocuments` + Storage
  `users/{uid}/wallet/{tripId}/`). Même traitement si un admin retire un
  participant (vérifier le chemin de retrait existant).
- **Suppression de compte** : vérifier que le préfixe `users/{uid}/` est bien
  purgé (sinon l'ajouter).
- Tests unitaires Jest à côté des tests existants.

## 7. Découpage en lots

| Lot | Contenu | Livrable visible |
|-----|---------|------------------|
| 0 | **Spike** : `mobile_scanner` sur PWA iOS Safari + Chrome Android (QR, Aztec, PDF417) ; décodage depuis une image sur web ; rendu `barcode_widget` relu par une vraie douchette / appli de contrôle | Note de conclusion ajoutée à ce plan |
| 1 | Modèle, règles Firestore + Storage, repository, providers, tests unitaires du modèle | — |
| 2 | Liste réelle, état vide, compteur de la tuile | Page vide mais réelle |
| 3 | Import fichier + formulaire + upload avec progression | Ajout de PDF/images |
| 4 | Consultation, édition nom/catégorie/date, suppression | Cycle de vie complet |
| 5 | Scan caméra + affichage plein écran du code | QR / codes-barres |
| 6 | *(conditionnel)* Extraction du code depuis une capture importée | Bonus |
| 7 | Nettoyage via Cloud Functions + tests Jest | — |

Chaque lot se termine par `flutter analyze` sans nouvelle alerte.

## 8. Localisation

- Nouvelles clés dans `app_fr`, `app_fr_FR`, `app_en`, `app_en_US` : libellés
  des catégories, actions (importer, scanner, enregistrer, supprimer,
  confirmer), titres d'écrans, messages d'erreur (fichier trop lourd, type
  non supporté, limite atteinte, caméra refusée, code non reconnu), état vide.
- Clés de la maquette devenues inutiles : les supprimer des 4 ARB (règle de
  nettoyage). `tripWalletPageTitle`, `tripWalletAddDocument` et
  `tripOverviewWalletDocumentCount` restent utilisées.

## 9. Déploiement (à lancer par le product owner)

Preview :
```powershell
firebase deploy --only firestore:rules,storage --project planerz-preview
firebase deploy --only functions:deleteTripCascade,functions:leaveTrip --project planerz-preview
```

Production :
```powershell
firebase deploy --only firestore:rules,storage --project planerz
firebase deploy --only functions:deleteTripCascade,functions:leaveTrip --project planerz
```

Les fonctions modifiées étant des callables v2, vérifier ensuite l'IAM
Cloud Run (`allUsers` / `roles/run.invoker`) :
```powershell
gcloud run services get-iam-policy deletetripcascade --region=europe-west9 --project=planerz
gcloud run services get-iam-policy leavetrip --region=europe-west9 --project=planerz
```

## 10. Hors périmètre V1

- Consultation hors-ligne garantie.
- Partage d'un document avec d'autres participants.
- Coffre global réutilisable entre voyages.
- Import `.pkpass` / ajout à Apple Wallet / Google Wallet.
- Lecture automatique des infos du billet (OCR, IA) pour pré-remplir nom,
  catégorie et date.
- Chiffrement côté client.
