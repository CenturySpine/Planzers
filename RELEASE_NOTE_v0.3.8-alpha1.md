# Release Notes — v0.3.8-alpha1

## Pour les utilisateurs

Correctif de la version alpha suivant la v0.3.7.

- **Application Android :** lorsque la maintenance est désactivée depuis l’espace d’administration (comme sur le web), l’écran de blocage disparaît à nouveau et l’application redevient accessible. Auparavant, l’app Android pouvait rester bloquée alors que le drapeau Firestore était déjà à « maintenance terminée ».

---

## Détails complémentaires (technique et exploitation)

### Administration

- **Mode maintenance :** la lecture du drapeau `system/maintenance` privilégie désormais la valeur serveur Firestore et ignore un cache local obsolète sur mobile (persistance Android), ce qui aligne le comportement avec le web après levée de maintenance.
