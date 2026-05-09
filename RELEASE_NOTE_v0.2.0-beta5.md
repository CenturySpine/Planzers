# Notes de version — v0.2.0-beta5

## Pour les utilisateurs

### Repas

**Génération automatique d'ingrédients par IA**

Les chefs de repas, les admins du voyage et le créateur du voyage peuvent désormais générer automatiquement la liste d'ingrédients d'un composant repas directement depuis l'éditeur. La génération s'adapte à la langue de l'application (français ou anglais) et rapproche les ingrédients produits du catalogue existant.

Le dialogue de génération s'ouvre en mode « ingrédients uniquement » par défaut. Remplacer les étapes de préparation en même temps n'est pas proposé lorsque des étapes existent déjà sur le composant.

Un bandeau d'information dans le dialogue précise que les appels IA sont facturés au créateur de l'application et invite à le soutenir via Ko-fi.

**Quotas d'utilisation visibles**

Le nombre de générations restantes est affiché en temps réel dans le dialogue ; le bouton de génération se désactive automatiquement lorsque le quota est atteint.

Lorsque la limite globale de la journée est atteinte (tous utilisateurs confondus), le bouton de génération disparaît silencieusement et réapparaît automatiquement le lendemain.

### Compte

La reconnexion au compte par numéro de téléphone ne réinitialise plus les champs du profil : le nom affiché, l'adresse e-mail et le numéro de téléphone sont désormais préservés d'une reconnexion à l'autre. Les suppressions volontaires sont respectées.

Pour les pays européens et nord-africains courants (ex. +33, +32, +212…), le numéro de téléphone est automatiquement découpé entre indicatif et numéro local lors de la première connexion par téléphone.

---

## Détails techniques et opérationnels

### IA — Système de quotas et garde-fous

Un système de quotas atomiques protège les deux fonctionnalités IA d'une utilisation excessive. Chaque réservation est effectuée en transaction Firestore (vérification + incrément atomiques) et est automatiquement annulée en cas d'erreur IA.

Quotas de lancement retenus :
- Génération d'ingrédients : 5 / utilisateur / jour · 10 / voyage / jour · 30 / voyage à vie.
- Consolidation des courses : 2 / utilisateur / jour · 3 / voyage / jour · 10 / voyage à vie.

Un disjoncteur global se déclenche à 50 appels de grounding Google Search par jour. Quand il est actif, les fonctionnalités IA sont masquées (non désactivées) pour tous les utilisateurs ; elles réapparaissent automatiquement le lendemain. Les *application owners* contournent l'ensemble des quotas.

Un délai de 5 secondes entre deux tentatives consécutives s'applique aux utilisateurs non-*owners*.

### IA — Consolidation des courses (POC limité)

Un bouton de consolidation IA est présent sur la liste des courses pour les organisateurs. Les utilisateurs qui ne sont pas *application owners* voient un dialogue explicatif indiquant que la fonctionnalité n'est pas encore disponible ; seuls les *application owners* peuvent déclencher la consolidation.

### Authentification

Correction : la reconnexion par téléphone ne provoquait pas de ré-écriture partielle du document profil dans Firestore. Les champs `displayName`, `email` et `phoneNumber` sont maintenant préservés de façon sélective selon qu'ils ont été renseignés ou effacés volontairement.
