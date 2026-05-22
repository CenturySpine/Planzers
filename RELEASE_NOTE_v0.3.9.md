# Notes de version — v0.3.9

> Période couverte : v0.3.8-alpha2 → v0.3.9

## Pour les utilisateurs

### Dépenses

- **Soldes et remboursements fiables :** les soldes par devise, les remboursements suggérés et les totaux du poste (« Ma dépense », « Total du poste ») sont calculés côté serveur et se mettent à jour automatiquement après chaque dépense ou remboursement enregistré.
- **Marquer un remboursement comme payé :** depuis l’onglet Équilibres, chaque voyageur concerné peut confirmer un remboursement suggéré ; l’opération apparaît dans la liste des remboursements réglés et peut être annulée tant que le poste le permet.
- **Libellés plus clairs :** les cartes de remboursement mettent en avant ce que *vous* devez ou ce qu’on vous doit, avec un filtre « Moi » / « Tout le poste » pour se concentrer sur ses propres lignes ou voir l’ensemble du poste.
- **Petits soldes ignorés :** les micro-écarts proches de zéro ne génèrent plus de suggestions inutiles ; les administrateurs peuvent forcer un recalcul des soldes si besoin.
- **Notifications de remboursement :** lorsqu’un remboursement est confirmé ou annulé, la personne concernée reçoit une notification sur le canal Dépenses du voyage (sauf si un administrateur a désactivé ces alertes pour ce voyage).
- **Badge sur le voyage :** l’onglet Dépenses du voyage affiche un indicateur tant qu’il reste des notifications non lues ; l’ouverture de l’onglet Équilibres les efface.
- **Phase de clôture (administrateurs) :** un administrateur peut verrouiller les dépenses du voyage pour masquer l’ajout et la modification des dépenses aux autres voyageurs, tout en conservant la gestion côté admin. Les actions « marqué comme payé » et « annuler le remboursement » ne sont proposées **que** lorsque les dépenses sont verrouillées.
- **Couper les notifications de dépenses :** un administrateur peut désactiver les notifications push du canal Dépenses pour ce voyage, sans affecter les autres canaux (messages, activités, etc.).

---

## Détails complémentaires (technique et exploitation)

- **Cloud Functions (région `europe-west9`) :** recalcul des dérivés par poste (`balances`, `suggestedReimbursements`, `summary/current`) au fil des écritures dans `expenses` ; callables `markExpenseReimbursementPaid`, `unmarkExpenseReimbursementPaid`, `deleteExpenseGroup`. Les remboursements matérialisés utilisent `operationType: settlement` dans `trips/{tripId}/expenses` (création / suppression réservées aux callables).
- **État du voyage :** collection `trips/{tripId}/expenses_states/default` (verrouillage UI + drapeau `expensesNotificationsEnabled` pour le canal push dépenses).
- **Règles Firestore :** lecture des dérivés pour les membres ; écriture client des settlements interdite ; règles alignées sur `expenses_states` (admin, rang ≥ 2).
- **Déploiement requis après mise à jour :** `firebase deploy --only firestore:rules,functions --project <id>` (ou cibles équivalentes selon [`RELEASE.md`](RELEASE.md)), puis vérification IAM `roles/run.invoker` sur les callables concernés si besoin.
