# Release Notes — v0.3.8-alpha2

## Pour les utilisateurs

- **Accès à l’application :** l’écran de blocage « maintenance en cours » est supprimé. L’application reste utilisable normalement, y compris sur Android, sans tenir compte du drapeau de maintenance en base.

---

## Détails complémentaires (technique et exploitation)

### Administration

- **Mode maintenance :** l’espace d’administration conserve les actions pour activer ou désactiver le drapeau `isMaintenanceOngoing` dans Firestore (`system/maintenance`). L’application cliente ne lit plus ce drapeau et n’y réagit plus.
