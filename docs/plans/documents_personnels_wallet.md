---
name: Documents personnels (Wallet) — stockage réel, fichiers, codes-barres et hors-ligne
overview: Remplacer la maquette « Mes documents » par un vrai coffre personnel par voyage — import de fichiers (PDF, images), capture de QR codes / codes-barres à la caméra ou depuis une capture d'écran, nom + catégorie avec icône, consultation plein écran, téléchargement transparent pour un accès hors-ligne, visible uniquement par son propriétaire.
todos:
  - id: spike
    content: "Lot 0 — Spike technique : scan caméra sur web (PWA iOS/Android), décodage d'un code depuis une image sur web, formats Aztec/PDF417, stockage IndexedDB + persist(), lecteur PDF embarqué hors-ligne, service worker app shell"
    status: pending
  - id: data-rules
    content: "Lot 1 — Modèle Firestore walletDocuments + règles Firestore + règles Storage (owner-only) + repository/providers"
    status: completed
  - id: list-real-data
    content: "Lot 2 — Liste réelle sur TripWalletPage + compteur réel sur la tuile de l'aperçu + état vide"
    status: completed
  - id: add-file
    content: "Lot 3 — Écran d'ajout d'un fichier (nom, catégorie, fichier) avec upload et progression"
    status: completed
  - id: viewer-edit-delete
    content: "Lot 4 — Consultation (image plein écran, PDF via lecteur embarqué), menu d'actions, renommage/recatégorisation, suppression"
    status: completed
  - id: barcode-scan
    content: "Lot 5 — Scan caméra d'un QR code / code-barres, stockage du contenu, affichage plein écran régénéré"
    status: pending
  - id: barcode-from-image
    content: "Lot 6 — Détection d'un code dans une capture d'écran importée : on ne garde que le code, pas l'image"
    status: pending
  - id: offline-app-shell
    content: "Lot 7 — Démarrage de l'app hors-ligne (service worker app shell, cache Firestore web, démarrage tolérant au hors-ligne, purge à la déconnexion)"
    status: completed
  - id: offline-documents
    content: "Lot 8 — Stockage local transparent : Télécharger / Supprimer du téléphone, ouverture locale-puis-en-ligne, codes-barres automatiquement hors-ligne, purge à la déconnexion"
    status: pending
  - id: cleanup-functions
    content: "Lot 9 — Nettoyage Storage à la sortie / suppression du voyage (Cloud Functions)"
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
2. **Ajouter un QR code / code-barres**, soit en le scannant avec la caméra,
   soit en important une **capture d'écran** dans laquelle l'app détecte le
   code. Dans ce second cas, **seul le code est conservé**, pas l'image.
3. Chaque document porte au minimum un **nom** et une **catégorie** (billet
   d'avion, de train…), la catégorie donnant une **icône** dans la liste.
4. **Hors-ligne dès la V1** : chaque document a un menu d'actions
   (au minimum **Supprimer** et **Télécharger**). « Télécharger » range le
   document dans l'espace de stockage propre à l'app, **sans jamais demander
   d'emplacement à l'utilisateur** ; il est ensuite consultable sans réseau.
   À l'ouverture, l'app choisit seule la copie locale ou la version en ligne :
   c'est transparent pour l'utilisateur.
5. Le but : **avoir tous les documents du voyage sous la main**, y compris
   sans réseau.

## 2. Points de challenge et arbitrages retenus

### 2.1 Planerz est une **web app** d'abord
L'app Android native est décommissionnée (`AndroidSunsetGate`) : la cible
principale est la **PWA dans le navigateur mobile**.

- **Scan caméra dans un navigateur** : faisable (`getUserMedia`, HTTPS déjà
  en place) via `mobile_scanner`, mais moins fluide qu'en natif (permission
  caméra, comportement variable en PWA iOS installée). → Validé au spike.
- **Luminosité de l'écran** : impossible à forcer depuis un navigateur. On
  compense par un affichage noir sur blanc plein écran, grand format.

### 2.2 « Scanner un QR code » ≠ « stocker une image de QR code »
Scanner (caméra ou capture) récupère **le contenu** du code ; on le
**régénère** à l'écran au format d'origine. Beaucoup de titres de transport
ne sont pas des QR codes (cartes d'embarquement en PDF417/Aztec, billets
SNCF/Eurostar en Aztec) : on gère **les codes-barres courants** et on
**mémorise le format**. Rendu via `barcode_widget` (QR, Aztec, PDF417,
DataMatrix, Code 128, EAN).

### 2.3 Parcours d'ajout retenus
Le billet est souvent **déjà dans le téléphone** (PDF reçu par mail, capture
d'écran d'une app de compagnie). Trois parcours, tous en V1 :

1. **Importer un fichier** (PDF, image) tel quel.
2. **Scanner à la caméra** (billet papier, autre écran).
3. **Importer une capture d'écran contenant un code** : l'app détecte le
   code et propose de l'enregistrer comme code ; **l'image n'est pas
   conservée** (décision produit, option A). Si aucun code n'est détecté,
   l'image est enregistrée comme un fichier classique.

Sur web, `mobile_scanner` ne décode pas depuis une image : il faut une
librairie de décodage (port Dart de ZXing ou librairie JS **embarquée dans
l'app**, pas chargée depuis un CDN). Choix au spike. Le décodage se fait à
l'import, donc en ligne : il n'impacte pas le hors-ligne.

### 2.4 « À peu près n'importe quel document »
**Liste blanche** en V1 — PDF, JPEG, PNG, WebP, HEIC — **15 Mo max par
fichier**, **50 documents max par voyage**. HEIC n'est affichable que sur
Safari : on l'accepte mais on le traite comme « fichier à ouvrir » ailleurs.
`.pkpass`, `.docx`, etc. hors périmètre V1.

### 2.5 Données sensibles
- **Faille à éviter dans `storage.rules`** : la règle générique
  `match /trips/{tripId}/{allPaths=**}` autorise **tout participant** à lire
  tout ce qui est sous `trips/{tripId}/`. Les règles Storage s'additionnent :
  ranger les documents perso sous `trips/{tripId}/wallet/...` les rendrait
  lisibles par tout le voyage. → Fichiers sous
  **`users/{uid}/wallet/{tripId}/...`**, déjà limité au propriétaire.
- La règle actuelle `users/{uid}/{allPaths=**}` n'a **ni limite de taille ni
  de type** : à resserrer (photo de profil d'un côté, wallet de l'autre).
- Les copies locales hors-ligne sont **purgées à la déconnexion** (appareil
  ou navigateur partagé).
- Pas de chiffrement de bout en bout en V1.

### 2.6 Hors-ligne en web : ce que ça implique vraiment
- **L'app doit d'abord démarrer sans réseau.** Aujourd'hui, `web/index.html`
  n'enregistre que le service worker de messagerie ; rien ne met l'app en
  cache. Il faut un **service worker « app shell »** et vérifier que les
  écrans de démarrage (mise à jour, maintenance, authentification) ne
  bloquent pas hors-ligne. Chantier **transverse** (Lot 7), à coordonner avec
  la détection de mise à jour (`docs/plans/preview_update_detection.md`) pour
  ne jamais bloquer un utilisateur sur une vieille version.
- **Le navigateur peut effacer les données locales.** Safari iOS purge le
  stockage d'un site non visité depuis ~7 jours, **sauf PWA installée sur
  l'écran d'accueil**. On demande `navigator.storage.persist()`, mais le
  navigateur décide. Risque **accepté** par le product owner. Conséquence
  technique : l'état « téléchargé » est **toujours vérifié contre le stockage
  réel**, jamais supposé.
- **Les données doivent aussi être disponibles hors-ligne.** Décision
  (option A) : **cache disque Firestore activé sur le web** pour toute l'app.
  Hors-ligne, l'utilisateur suit son parcours habituel (voyages → voyage →
  Mes documents) avec les dernières données connues ; seuls les **fichiers**
  sont stockés à part par le wallet.
- **PDF hors-ligne** : ouvrir un blob dans un nouvel onglet est peu fiable en
  PWA iOS. → **Lecteur PDF embarqué** dans l'app, avec ses ressources
  empaquetées (pas de chargement CDN à l'exécution). Choix au spike.

## 3. Décisions produit validées

| # | Sujet | Décision |
|---|-------|----------|
| D1 | Permission dédiée | **Non** : module strictement personnel, seul le propriétaire agit. |
| D2 | Catégories | Liste fixe dans le code : Avion, Train, Bus/car, Bateau, Hébergement, Location de véhicule, Activité/billet, Identité, Assurance/santé, Autre. |
| D3 | Champs | Nom (obligatoire), catégorie (obligatoire, « Autre » par défaut), date optionnelle (tri chronologique). |
| D4 | Fichiers | Liste blanche PDF + images, 15 Mo max, 50 documents max par voyage. |
| D5 | Sauvegarde | Formulaire plein écran avec validation explicite. |
| D6 | Hors-ligne | **Dans la V1**, via stockage local transparent (section 5.4). |
| D7 | Code depuis une capture | **Dans la V1** ; on ne garde **que le code**, pas l'image. |
| D8 | Désactivation du module | Masque les documents sans les supprimer. |
| D9 | Démarrage hors-ligne | Lot séparé (service worker app shell). |
| D10 | Purge navigateur Safari | Risque accepté ; état « téléchargé » vérifié en temps réel. |
| D11 | Copie locale | Menu « Supprimer du téléphone » + purge automatique à la déconnexion, à la suppression du document et à la sortie du voyage. |
| D12 | « Voir en ligne » | **Pas d'option explicite** : bascule automatique vers la version en ligne si la copie locale manque ou est corrompue (les fichiers ne sont jamais remplacés, la copie locale est identique). |
| D13 | Codes-barres | **Toujours disponibles hors-ligne automatiquement**, sans action « Télécharger » (leur contenu est dans Firestore, donc dans le cache). |
| D14 | Données hors-ligne | **Option A** : cache disque Firestore activé sur le web pour toute l'app ; parcours de navigation inchangé hors-ligne. |

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
  eventDate: timestamp?,        // optionnel

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

Sous `travelerModules/{uid}` : règles « propriétaire uniquement » déjà en
place, et `recursiveDelete` de `deleteTripCascade` efface la sous-collection.
Pas d'URL de téléchargement stockée en base (`getDownloadURL` à la demande).

### Storage

**`users/{uid}/wallet/{tripId}/{documentId}.{ext}`**, métadonnées `tripId`
et `documentId`.

### Stockage local (appareil)

Aucune donnée Firestore ne trace l'état « téléchargé » : c'est un état propre
à l'appareil. Les métadonnées et les codes-barres viennent du cache Firestore
(option A) ; seul le **contenu des fichiers** est stocké par le wallet
(IndexedDB sur web, dossier privé de l'app via `path_provider` en natif),
clé = `uid/tripId/documentId` :

```
{ uid, tripId, documentId, contentType, sizeBytes, bytes, savedAt }
```

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
`kind`, `file` et `barcode` sont **immuables**.

### Règles Storage (`storage.rules`)

- Remplacer `match /users/{uid}/{allPaths=**}` par deux règles ciblées :
  - `users/{uid}/{fileName}` (photos de profil `profile_*`, cf.
    `account_repository.dart`) : comportement inchangé + limite image/taille.
  - `users/{uid}/wallet/{tripId}/{fileName}` :
    - `read`, `delete` : propriétaire uniquement ;
    - `create` : propriétaire **et** membre du voyage, `size < 15 Mo`,
      `contentType` dans la liste blanche, nom `[A-Za-z0-9._-]+` ;
    - `update` : interdit.

## 5. Flutter

### 5.1 Dépendances à ajouter (versions et choix finaux au spike)
- `file_picker` — sélection de PDF/fichiers.
- `mobile_scanner` — scan caméra.
- `barcode_widget` — rendu des codes.
- Décodage de code depuis une image sur web (port Dart ZXing ou JS embarqué).
- Lecteur PDF embarqué fonctionnant hors-ligne sur web (ex. `pdfrx` avec
  ressources pdf.js empaquetées).
- Accès IndexedDB (ex. `idb_shim`/`sembast_web`) — une seule abstraction de
  stockage local pour web et natif.

Natif (si iOS reste un canal) : `NSCameraUsageDescription` dans
`ios/Runner/Info.plist`.

### 5.2 Arborescence

```
lib/features/wallet/
  data/
    wallet_document.dart             // modèle immuable + fromMap/toMap
    wallet_document_category.dart    // enum + icône + clé l10n
    wallet_repository.dart           // CRUD Firestore + Storage
    wallet_local_store.dart          // interface stockage local
    wallet_local_store_web.dart      // IndexedDB + navigator.storage.persist()
    wallet_local_store_io.dart       // dossier privé de l'app (path_provider)
    wallet_barcode_decoder.dart      // détection de code dans une image
  presentation/
    trip_wallet_page.dart            // liste (déplacée depuis trips/presentation)
    wallet_document_form_page.dart   // ajout/édition (plein écran)
    wallet_barcode_scan_page.dart    // caméra
    wallet_document_viewer_page.dart // image / PDF / code plein écran
    wallet_document_actions.dart     // menu d'actions d'un document
```

L'ancien `trips/presentation/trip_wallet_page.dart` est supprimé ; la route
`wallet` de `router.dart` pointe vers la nouvelle page.

### 5.3 Repository / providers
- `walletRepositoryProvider`, `walletLocalStoreProvider`.
- `myWalletDocumentsProvider(tripId)` : stream Firestore (servi par le cache
  hors-ligne), enrichi d'un indicateur « disponible hors-ligne » vérifié dans
  le stockage local.
- `addFileDocument(...)` : id Firestore généré, upload Storage (`putData`,
  progression), puis écriture Firestore ; suppression du fichier si
  l'écriture échoue.
- `addBarcodeDocument(...)` : écriture Firestore (disponible hors-ligne via
  le cache, D13).
- `updateDocumentMetadata(...)` : Firestore.
- `deleteDocument(...)` : Firestore, Storage (best effort), copie locale.
- `downloadForOffline(document)` / `removeFromDevice(document)`.
- `openDocument(document)` : copie locale si présente et lisible, sinon
  téléchargement en ligne ; en cas de copie locale corrompue, suppression de
  celle-ci et bascule en ligne (D12).
- Synchronisation au retour en ligne : copies locales de documents supprimés
  ailleurs retirées.

### 5.4 UI
- **Liste** (`TripWalletPage`) : cartes existantes (icône de catégorie, nom,
  date/type). Petit indicateur « disponible hors-ligne » sur les documents
  concernés. État vide. Bouton `+` → « Importer un fichier » / « Scanner un
  code ». Hors-ligne : bouton `+` masqué ; un fichier non téléchargé reste
  listé mais son ouverture affiche « document indisponible hors-ligne ».
- **Menu d'actions** (bouton `⋮` sur chaque carte) :
  - fichier non téléchargé : **Télécharger**, Modifier, Supprimer ;
  - fichier téléchargé : **Supprimer du téléphone**, Modifier, Supprimer ;
  - code-barres : Modifier, Supprimer (toujours hors-ligne, pas d'action de
    téléchargement) ;
  - hors-ligne : seules les actions locales restent visibles (règle « masquer
    plutôt que désactiver »).
  - « Télécharger » affiche une progression puis un SnackBar de confirmation ;
    aucun sélecteur d'emplacement, aucun fichier visible hors de l'app.
- **Tuile aperçu** (`trip_overview_page.dart`) : compteur réel.
- **Formulaire** (plein écran, validation explicite) : nom, catégorie
  (sélecteur avec icônes), date optionnelle, aperçu du fichier ou du code.
  Nom pré-rempli avec le nom du fichier importé.
- **Import d'une image** : détection de code automatique ; si un code est
  trouvé, demande « enregistrer comme code ? » → oui : document `barcode`,
  image abandonnée ; non : document `file`.
- **Consultation** (tap sur la carte), source locale ou en ligne sans
  distinction visible :
  - image → plein écran zoomable (`InteractiveViewer`) ;
  - PDF → lecteur embarqué ;
  - code-barres → plein écran fond blanc, code régénéré, nom au-dessus,
    contenu texte copiable en dessous.
- Suppression avec confirmation.
- Aucun texte d'aide ou d'astuce au-delà des libellés nécessaires.

### 5.5 Purges locales
- **Déconnexion** : purge complète du stockage local wallet (tous voyages),
  en plus de la purge du cache Firestore déjà en place (Lot 7).
- **Suppression d'un document** : copie locale supprimée.
- **Sortie du voyage / voyage supprimé** : copies locales du voyage supprimées
  (immédiatement si l'action est faite sur l'appareil ; sinon à la prochaine
  synchronisation en ligne, quand le voyage n'est plus accessible).
- **Changement d'utilisateur sur le même navigateur** : les clés locales
  étant préfixées par `uid`, on ne lit jamais les documents d'un autre compte.

## 6. Démarrage hors-ligne (Lot 7 — livré)

- **`web/sw.js`** : service worker « app shell » à la racine, cohabitant avec
  `firebase-messaging-sw.js` (scope distinct).
  - Fichiers de l'app (même origine, noms non versionnés) : **réseau
    d'abord**, cache si hors-ligne ou réponse > 6 s. Un utilisateur en ligne
    reçoit toujours la dernière version déployée.
  - Firebase JS SDK, polices Google, cdnjs (URLs versionnées) : **cache
    d'abord**.
  - APIs Firebase (Firestore, Auth, Storage, Functions) : jamais interceptées.
  - La page transmet au worker les fichiers chargés avant sa prise de
    contrôle : une seule visite en ligne suffit.
- **`web/flutter_bootstrap.js`** personnalisé : n'enregistre plus le service
  worker Flutter (déprécié, il se désinstallait et aurait évincé `sw.js`).
- **Build** : `--no-web-resources-cdn` (moteur CanvasKit et polices de secours
  servis par l'app plutôt que par gstatic, donc mis en cache et mis à jour
  avec elle). En-tête `Cache-Control: no-cache` sur `/sw.js` (`vercel.json`).
- **Cache Firestore web** activé (IndexedDB, multi-onglets) au démarrage.
- **Démarrage** : la synchronisation du profil au login attend au plus 6 s
  puis laisse passer (avant : écran d'erreur hors-ligne). Hors-ligne sans
  profil en cache, on ne redemande pas le nom.
- **Déconnexion (web)** : cache Firestore effacé puis page rechargée.
- Vérifié en navigateur headless : prise de contrôle du worker, mise en cache
  (app, moteur, polices), redémarrage hors-ligne depuis le cache. **À valider
  sur téléphone** (Firebase SDK non joignable depuis l'environnement de
  l'agent) : iPhone Safari, PWA installée, Chrome Android, en mode avion.
- Limites connues : les images servies par Firebase Storage (bannières,
  avatars) et les actions serveur (callables, envois) ne fonctionnent pas
  hors-ligne ; les écritures Firestore simples sont mises en file et
  envoyées au retour du réseau.

## 6 bis. Lots 1 à 4 — état livré

- Données, règles Firestore et Storage, dépôt, liste réelle, compteur de la
  tuile, ajout de fichier (PDF, JPEG, PNG, WebP, HEIC ; 15 Mo ; 50 par
  voyage), consultation, menu d'actions (Modifier, Supprimer), édition du
  nom / de la catégorie / de la date.
- Consultation : images affichées dans l'app (zoom). **PDF ouverts dans un
  nouvel onglet** en attendant le lecteur embarqué du Lot 8 (le lien est
  préparé avant le tap pour ne pas être bloqué comme pop-up par Safari).
- Règles testées dans les émulateurs Firebase (19 cas Firestore, 9 cas
  Storage). Limite de l'émulateur Storage : il ne lit pas Firestore dans les
  règles, la condition « membre du voyage » est donc à valider sur la
  preview.
- La règle Storage `users/{uid}/**` est réduite à un seul segment
  (`users/{uid}/{fileName}`, photos de profil) pour ne pas court-circuiter
  les contrôles du wallet.

## 7. Cloud Functions (région `europe-west9`)

- **`deleteTripCascade`** : suppression Storage des préfixes
  `users/{memberUid}/wallet/{tripId}/` pour chaque membre.
- **`leaveTrip`** (et retrait d'un participant par un admin) : suppression des
  documents wallet Firestore + Storage du participant.
- **Suppression de compte** : vérifier la purge du préfixe `users/{uid}/`.
- Tests unitaires Jest à côté des tests existants.

## 8. Découpage en lots

| Lot | Contenu | Livrable visible |
|-----|---------|------------------|
| 0 | **Spike** : `mobile_scanner` sur PWA iOS Safari + Chrome Android (QR, Aztec, PDF417) ; décodage depuis une image sur web ; rendu relu par une vraie appli de contrôle ; IndexedDB + `persist()` sur Safari/Chrome ; lecteur PDF embarqué hors-ligne ; faisabilité du service worker app shell | Note de conclusion ajoutée à ce plan |
| 1 | Modèle, règles Firestore + Storage, repository, providers | — |
| 2 | Liste réelle, état vide, compteur de la tuile | Page réelle |
| 3 | Import fichier + formulaire + upload avec progression | Ajout de PDF/images |
| 4 | Consultation, menu d'actions, édition, suppression | Cycle de vie complet |
| 5 | Scan caméra + affichage plein écran du code | QR / codes-barres |
| 6 | Détection de code dans une capture importée | Import de capture |
| 7 | Démarrage de l'app hors-ligne | App ouvrable sans réseau |
| 8 | Stockage local : Télécharger / Supprimer du téléphone, lecture locale transparente, codes auto hors-ligne, purges | Documents hors-ligne |
| 9 | Nettoyage via Cloud Functions + tests Jest | — |

Chaque lot se termine par `flutter analyze` sans nouvelle alerte. Les lots
7 et 8 sont testés en conditions réelles (mode avion) sur iPhone (Safari et
PWA installée) et Android (Chrome).

## 9. Localisation

- Nouvelles clés dans `app_fr`, `app_fr_FR`, `app_en`, `app_en_US` :
  catégories, actions (importer, scanner, télécharger, supprimer du
  téléphone, modifier, supprimer, enregistrer comme code), titres d'écrans,
  confirmations, erreurs (fichier trop lourd, type non supporté, limite
  atteinte, caméra refusée, code non reconnu, document indisponible
  hors-ligne, espace de stockage insuffisant), état vide, état hors connexion.
- Clés de la maquette devenues inutiles : supprimées des 4 ARB.
  `tripWalletPageTitle`, `tripWalletAddDocument` et
  `tripOverviewWalletDocumentCount` restent utilisées.

## 10. Déploiement (à lancer par le product owner)

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

Vérification IAM Cloud Run des callables redéployées :
```powershell
gcloud run services get-iam-policy deletetripcascade --region=europe-west9 --project=planerz
gcloud run services get-iam-policy leavetrip --region=europe-west9 --project=planerz
```

Le service worker app shell est livré avec le build web (Vercel), sans
déploiement Firebase.

## 11. Hors périmètre V1

- Hors-ligne des autres pages de l'app.
- Partage d'un document avec d'autres participants.
- Coffre global réutilisable entre voyages.
- Import `.pkpass` / ajout à Apple Wallet / Google Wallet.
- Lecture automatique des infos du billet (OCR, IA) pour pré-remplir nom,
  catégorie et date.
- Chiffrement côté client (y compris des copies locales).
