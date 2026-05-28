# Notes de version — v0.4.0

> Période couverte : v0.3.9 → v0.4.0

## Pour les utilisateurs

### Dépenses

- **Groupes de participants avec parts :** plusieurs voyageurs peuvent être regroupés sous un même libellé (couple, famille…) avec un nombre de parts configurable. Ils sont traités comme une seule unité de facturation dans les dépenses, les soldes et les remboursements suggérés.
- **Verrouillage par poste :** un administrateur peut geler les dépenses d’un poste sans bloquer les autres postes du voyage. Une fois verrouillé, personne — y compris les administrateurs — ne peut plus ajouter, modifier ou supprimer des dépenses sur ce poste ; la création et la gestion des postes restent possibles.
- **Filtre « Tout » / « Moi » sur les opérations :** la liste des opérations peut être restreinte aux entrées où vous êtes payeur ou participant, tandis que les totaux du poste continuent de couvrir l’ensemble.
- **« Mon coût total » :** un nouveau indicateur au centre du bandeau récapitulatif affiche votre coût réel sur le poste, calculé à partir de vos parts dans les dépenses partagées (et non des soldes de remboursement).
- **Soldes plus lisibles :** tous les participants restent visibles dans chaque devise, y compris à l’équilibre (0 €) ; les micro-montants inférieurs à 0,50 € sont affichés comme neutres, en cohérence avec le seuil de suggestion de remboursement.
- **Remboursements plus stables :** valider ou annuler un remboursement ne redistribue plus les suggestions vers d’autres créanciers ; seules les créations, modifications ou suppressions de dépenses partagées déclenchent un recalcul complet (poste déverrouillé).
- **Encarts d’aide :** brèves explications sur le filtre des opérations ; pour les administrateurs, rappels sur le verrouillage, les notifications de remboursement et l’actualisation des soldes.

### Voyage

- **Participants enfants :** lors de l’ajout ou de la modification d’un voyageur prévu, l’organisateur peut le marquer comme enfant. Son nom est identifié par un emoji cohérent dans les listes ; un enfant ne peut pas rejoindre le voyage par invitation, conduire un covoiturage, ni être sélectionné comme payeur individuel d’une dépense. Lors de la composition d’un groupe de facturation, une part de 0,5 est suggérée par enfant (ajustable par l’administrateur).
- **Onglet Groupes :** nouvel onglet dans la page Participants pour créer, modifier et supprimer les groupes de facturation (libellé, membres, parts).
- **Encarts d’aide :** conseils sur les rôles administrateur (onglet Participants) et explication des groupes de facturation et des parts par défaut (onglet Groupes).
- **Ouverture d’itinéraire unifiée :** le même choix Google Maps ou Waze est proposé depuis la vue voyage, les activités et le covoiturage.

### Activités & planning

- **Itinéraire routier restauré :** le calcul du trajet en voiture est de nouveau disponible dans le détail d’une activité, avec possibilité de l’actualiser manuellement et retour visuel pendant le chargement.
- **Depuis ma position :** un bouton permet de calculer à la demande la distance et la durée depuis votre position actuelle vers l’activité, sans recalcul automatique à chaque déplacement.

### Repas

- **Enfants exclus du rôle de chef :** un participant marqué enfant ne peut pas être désigné chef de repas.

---

## Détails complémentaires (technique et exploitation)

### Dépenses

- **Modèle `ParticipantGroup` :** sous-collection Firestore `trips/{tripId}/participantGroups`, providers Riverpod (stream, libellés fusionnés, unité de facturation du viewer). Règles Firestore dédiées.
- **Cloud Functions :** la logique de règlement intègre les parts des groupes dans les soldes et remboursements suggérés ; les participants à l’équilibre conservent une entrée `net: 0` dans les soldes ; verrouillage et recalcul respectent l’état par poste (`expenses_states/{groupId}`) ; mark/unmark de remboursement met à jour soldes et suggestions en transaction atomique sans relancer l’algorithme glouton.
- **Suppression de membre :** bloquée si le voyageur appartient encore à un groupe de facturation.
- **Co-administrateurs :** le callable de recalcul des soldes reconnaît désormais les co-admins comme ailleurs dans le produit.

### Activités & planning

- **Callable `activityDrivingRoute` :** calcul via Routes API (région `europe-west9`), avec mode hébergement ou position actuelle ; tests unitaires associés.

### Voyage

- **Manifestes natifs :** déclarations de schémas `googlemaps`, `comgooglemaps`, `waze` (Android) et `LSApplicationQueriesSchemes` (iOS) pour l’ouverture fiable des applications de navigation.

### Exploitation

- **Script de maintenance :** `scripts/ensure_default_expense_group.js` — liste les voyages sans poste « Commun » par défaut et peut le recréer (dry-run par défaut, `--apply` pour écrire).
- **Déploiement requis après mise à jour :** `firebase deploy --only firestore:rules,functions --project <id>` (voir [`RELEASE.md`](RELEASE.md)), puis vérification IAM `roles/run.invoker` sur les callables modifiés ou redéployés si besoin.
