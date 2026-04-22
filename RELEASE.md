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

---

## 4. Vérification

- [ ] `planerz.centuryspine.org` charge correctement
- [ ] Connexion Google fonctionnelle
- [ ] Vercel dashboard : build "Production" vert
- [ ] Firebase console `planerz` : fonctions et règles à jour

---

## Notes

- Les deux projets Firebase sont totalement indépendants — un `deploy` sur `planerz-preview` n'affecte jamais `planerz`.
- Pour revenir en arrière : `git revert` sur `main` + `git push`, Vercel rebuilde automatiquement.
