# Promotion Preview → Prod

| | Preview | Prod |
|---|---|---|
| Branche | `develop` | `main` |
| Firebase | `planerz-preview` | `planerz` |
| URL | `preview.planerz.centuryspine.org` | `planerz.centuryspine.org` |

---

## 1. Bump de version *(si nécessaire)*

Dans `pubspec.yaml` :

```
version: X.Y.Z+N   # ex. 0.2.0+3
```

Commit sur `develop` avant de merger.

---

## 2. Merger develop → main

Via PR (recommandé) :

```bash
gh pr create --base main --head develop --title "release: vX.Y.Z"
gh pr merge --merge
```

Ou merge direct :

```bash
git checkout main
git merge develop --no-ff -m "release: vX.Y.Z"
git push origin main
```

**Vercel déploie automatiquement** sur `planerz.centuryspine.org`
(détecte `VERCEL_ENV=production` → build avec `main_prod.dart` + `FIREBASE_VAPID_KEY_PROD`).

---

## 3. Déployer Firebase sur prod *(seulement si modifié)*

### Règles Firestore / Storage / Index

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage --project planerz
```

### Cloud Functions

```bash
firebase deploy --only functions --project planerz
```

### Tout à la fois

```bash
firebase deploy --project planerz
```

### Sans poste local (GitHub Actions)

Workflow manuel **Deploy Cloud Functions** (`.github/workflows/deploy-functions.yml`) : onglet *Actions* du dépôt → *Run workflow*.

- Branche `develop` → `planerz-preview`, branche `main` → `planerz` (aucune autre branche acceptée).
- Champ *functions* : noms séparés par des virgules (ex. `extractTripActivityFromText,extractTripActivitiesFromDocuments`) ou `all`.
- Après le déploiement, vérifie l'IAM d'invocation Cloud Run des fonctions appelables et ajoute `allUsers` / `roles/run.invoker` si absent (récapitulatif dans le résumé du run).
- Secrets du dépôt requis : `GCP_SA_KEY_PREVIEW` et `GCP_SA_KEY_PROD` (clé JSON d'un compte de service par projet).
- Le fichier du workflow doit être présent sur `main` pour que *Run workflow* soit proposé.

---

## 4. Build APK / AAB Android *(release prod)*

```powershell
# APK (distribution directe)
flutter build apk --release --flavor prod --target lib/main_prod.dart

# AAB (Play Store)
flutter build appbundle --release --flavor prod --target lib/main_prod.dart
```

Sorties :
- APK : `build/app/outputs/flutter-apk/app-release.apk`
- AAB : `build/app/outputs/bundle/release/app-release.aab`

---

## 5. Vérification

- [ ] `planerz.centuryspine.org` charge correctement
- [ ] Connexion Google fonctionnelle
- [ ] Vercel dashboard : build "Production" vert
- [ ] Firebase console `planerz` : fonctions et règles à jour

---

## Notes

- Les deux projets Firebase sont totalement indépendants — un `deploy` sur `planerz-preview` n'affecte jamais `planerz`.
- Pour revenir en arrière : `git revert` sur `main` + `git push`, Vercel rebuilde automatiquement.

---

## Développement web local

### Port fixe

Toujours lancer Flutter web sur le port **47432** pour correspondre à la config CORS des buckets Storage.

```powershell
# Cible preview (Firebase planerz-preview)
flutter run -d chrome -t lib/main_preview.dart --web-port=47432

# Cible prod (Firebase planerz)
flutter run -d chrome -t lib/main_prod.dart --web-port=47432
```

### Config CORS Firebase Storage

Les deux buckets autorisent `http://localhost:47432` en plus de leur domaine de production.
À mettre à jour dans la console GCP (Storage → bucket → Modifier la conf CORS) si le port ou les domaines changent.

| Bucket | Origines autorisées |
|---|---|
| `planerz.firebasestorage.app` (prod) | `https://planerz.centuryspine.org,http://localhost:47432` |
| `planerz-preview.firebasestorage.app` (preview) | `https://preview.planerz.centuryspine.org,http://localhost:47432` |
