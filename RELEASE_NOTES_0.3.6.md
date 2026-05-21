# Release Notes — v0.3.6

## Pour les utilisateurs

L'application affiche un écran de maintenance et bloque toute interaction le temps d'une opération technique interne. Elle sera de retour très prochainement.

## Détails complémentaires (technique et exploitation)

Cette version est une version de transition destinée à protéger les données pendant la migration vers le nouveau système de gestion des participants (branche `work/feat-participants-rework`). L'écran de blocage est activé côté client via une constante (`kMaintenanceMode = true`). Il sera désactivé et remplacé par un mécanisme piloté depuis l'espace d'administration dans la version suivante (v0.3.7), publiée après la migration.
