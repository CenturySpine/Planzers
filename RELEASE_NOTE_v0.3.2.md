# Notes de version — v0.3.2

> Période couverte : v0.3.1 → v0.3.2

---

## Analyse du delta (avant rédaction)

Sur la fenêtre `v0.3.1 → v0.3.2`, le delta livré est centré sur la **messagerie des voyages** : l’app introduit un canal dédié aux échanges entre administrateurs, avec une séparation plus claire dans l’interface et des notifications qui respectent ce périmètre. Le reste du produit ne change pas pour les utilisateurs sur cette release.

---

## 1) L'essentiel pour les utilisateurs

### Messagerie

- Les voyages disposent maintenant d’un canal **« Admins »** (en plus du canal principal) pour les échanges réservés aux administrateurs.
- Les messages du canal **« Admins »** et leurs notifications sont **limités aux administrateurs** du voyage.

## 2) Détails complémentaires (technique et exploitation)

- Les messages de voyage prennent en charge des champs de thread/visibilité pour distinguer **Principal** / **Admins** et contrôler l’accès en lecture/écriture.
- Les règles Firestore et les notifications push ont été ajustées pour garantir que les messages **« Admins »** ne soient ni lisibles ni notifiés aux non‑admins.

