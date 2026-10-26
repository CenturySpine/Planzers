# Version 0.6.2

## Améliorations pour les utilisateurs

### Chambres

- **Des chambres par hébergement** — Quand le voyage compte plusieurs hébergements, la page des chambres présente un onglet par hébergement, chacun avec ses chambres. Un même hôtel utilisé pour plusieurs étapes (par exemple la première et la dernière nuit) n’a qu’un onglet. Un voyage avec un seul hébergement garde la page telle qu’elle était.
- **Saisies une seule fois** — Les chambres d’un hébergement valent pour toutes ses nuits.
- **Une nuit à part** — Pour un hébergement de plusieurs nuits, des pastilles permettent de choisir une nuit. « Personnaliser cette nuit » copie les chambres communes, qui se modifient alors pour cette nuit seulement (par exemple quand des voyageurs se succèdent dans les chambres) ; « Revenir aux chambres communes » annule la personnalisation. Les nuits personnalisées sont marquées d’un point.
- **Ma chambre** — L’aperçu du voyage indique la chambre de ce soir (celle de la première nuit avant le départ).

---

## Détails complémentaires (technique et exploitation)

### Chambres

- **Chambres existantes** — Les chambres créées avant cette version, comme celles d’un hébergement supprimé, sont rangées avec le premier hébergement du voyage ; aucune migration de données.
- **Répartition** — Un voyageur n’occupe qu’un lit parmi les chambres communes d’un hébergement, ou parmi celles d’une nuit personnalisée.

### Exploitation

- **Firebase** — Aucune règle ni Cloud Function à déployer.
