# Modèles de voyage et modules

## Contexte

Planerz couvre désormais des usages très différents : le séjour entre amis
dans un chalet (l'usage d'origine), le voyage itinérant avec hébergements nuit
par nuit et carte du voyage, ou le voyage préparé par un organisateur. Toutes
les fonctions sont visibles partout, ce qui alourdit l'interface pour chacun
de ces usages.

Objectif : à la création d'un voyage, choisir un **modèle** qui prérègle les
modules et les permissions, et **masquer tout ce qui ne sert pas**. Rien n'est
figé : après la création, chaque module et chaque permission reste modifiable
comme aujourd'hui.

## Décisions produit

| Sujet | Décision |
|---|---|
| Rôle du modèle | Préremplissage **à la création uniquement**. Le modèle n'est pas enregistré et ne pilote aucun affichage ensuite. |
| Modèles retenus | Séjour entre amis, Voyage itinérant, Voyage organisé, Sortie à la journée. |
| Modèles écartés | Randonnée (c'est une activité, pas une forme de voyage : elle relève de la journée, du séjour, de l'itinérant ou de l'organisé). Événement / mariage (reporté : il demanderait un module Dépenses). |
| Présentation | Une carte par modèle : titre et accroche, puis le détail et les modules inclus quand la carte est sélectionnée. |
| Nouveaux modules | **Itinéraire**, **Repas maison**, **Courses**, sur le modèle des modules existants (Chambres, Covoiturage, Jeux). |
| Repas au restaurant | Toujours disponible, quel que soit le module Repas maison. |
| Nouvelles permissions | **Gérer les chambres** et **Modifier ses dates de présence**. |
| Organisateur | C'est un voyageur comme un autre (il compte dans l'effectif, les chambres, les dépenses). |
| Voyage organisé | Les voyageurs ne choisissent pas leurs dates et ne voient pas l'onglet Suggestions. |
| Barre du bas | Le 5e emplacement affiche Courses, sinon la Carte, sinon rien. Jamais d'onglet grisé. |
| Pastilles de nuit des chambres | Rendues discrètes (on verra ensuite s'il faut les masquer complètement). |

## Principes

Tout passe par **trois mécanismes qui existent déjà**, sans nouvelle notion :

| Mécanisme | Qui décide | Effet |
|---|---|---|
| Modules | L'organisateur, pour tout le voyage | La fonction existe ou non pour tout le monde. |
| Permissions | L'organisateur | Ce que chacun peut faire. L'interface masque ce qu'on n'a pas le droit de faire, y compris un onglet entier dont c'est le seul usage. |
| Automatique | Les données | Masqué quand il n'y a rien à voir **et** rien à ajouter. |

Règle de masquage : **on ne masque pas une section vide que la personne peut
remplir** (sinon la fonction devient introuvable). On masque quand le module
est désactivé, ou quand la personne ne peut rien y faire et qu'il n'y a rien à
voir. Un contenu existant reste visible : désactiver un module ne fait pas
disparaître des données déjà saisies là où elles s'affichent hors du module.

**Voyages existants** : les trois nouveaux modules sont considérés comme
**activés** quand le champ est absent, et les nouvelles permissions prennent
leur valeur par défaut (Participants). Rien ne change pour eux ; aucune
migration de données.

## Les quatre modèles

### Matrice

| | Séjour entre amis | Voyage itinérant | Voyage organisé | Sortie à la journée |
|---|---|---|---|---|
| Itinéraire | ❌ | ✅ | ✅ | ❌ |
| Repas maison | ✅ | ❌ | ❌ | ✅ |
| Repas au restaurant | toujours | toujours | toujours | toujours |
| Courses | ✅ | ❌ | ❌ | ✅ |
| Chambres | ✅ | ❌ | ✅ | n/a |
| Covoiturage | ✅ | ❌ | ❌ | ✅ |
| Jeux | ✅ | ❌ | ❌ | ✅ |
| Cupidon | ❌ | ❌ | ❌ | ❌ |
| « À la journée » | non | non | non | oui |
| Hébergement | même pour toutes les nuits | nuit par nuit | nuit par nuit | n/a |
| Permissions | par défaut | par défaut | verrouillées (voir lot 2) | par défaut |
| 5e onglet | Courses | Carte | Carte | Courses |
| Dates de présence | dates + matin / midi / soir | dates seules | aucune (fixées par l'organisateur) | aucune |

### Textes

Les textes tutoient, comme le reste de l'application. L'accroche est en
italique sur la carte ; la liste apparaît quand la carte est sélectionnée,
suivie des modules inclus en pastilles.

**Séjour entre amis**
*Tout le groupe au même endroit (un chalet, une maison, un gîte) pour un week-end ou des vacances.*
- Répartis les chambres et les lits, nuit par nuit si les arrivées s'étalent.
- Organise les repas : qui cuisine, qui ramène quoi, avec une liste de courses commune.
- Propose des activités, le groupe vote pour ses préférées.
- Partage les voitures pour venir et fais les comptes en fin de séjour.

**Voyage itinérant**
*Tu changes d'étape au fil du voyage, seul ou à plusieurs : road trip, tour en train, voyage sac au dos, trek de refuge en refuge.*
- Indique où tu dors chaque soir : les étapes s'enchaînent sur la carte du voyage.
- Planifie activités et restaurants jour par jour, et repère les trajets à prévoir entre deux lieux.
- Tes photos prennent place sur la carte, étape après étape.
- Partage les dépenses et échange avec tes compagnons de route.

**Voyage organisé**
*Un organisateur (agence, guide, association ou ami qui prend tout en main) prépare le voyage pour le groupe.*
- L'organisateur fixe les dates, les étapes, les hébergements, les chambres et le programme heure par heure.
- Les voyageurs consultent le programme et la carte, sans pouvoir les modifier.
- Chacun ajoute ses photos aux activités.
- Les voyageurs partagent leurs dépenses entre eux et discutent dans la messagerie.
- Seul l'organisateur invite de nouveaux voyageurs.

**Sortie à la journée**
*Une journée ensemble, sans nuit sur place : anniversaire, pique-nique, randonnée, journée à la plage.*
- Partage les voitures pour y aller.
- Organise le pique-nique : qui ramène quoi, avec une liste de courses commune.
- Propose des activités, le groupe vote pour ses préférées.
- Fais les comptes en fin de journée.

**Sous les cartes** : « Ce choix prépare ton voyage : tu pourras ensuite
activer ou désactiver chaque module et ajuster les permissions. »

---

## Lot 1 — Les briques : modules et permissions

À l'issue du lot 1, tout est réglable à la main (formulaire du voyage, « +
Ajouter un module », permissions). Le formulaire de création propose les trois
nouveaux modules **activés par défaut** jusqu'au lot 2, pour ne rien changer à
l'expérience actuelle.

### 1.1 Modèle de données des modules

`trips/{tripId}` reçoit trois booléens, lus `?? true` (absent = activé) comme
`carpoolModuleEnabled` :

| Champ | Module |
|---|---|
| `journeyModuleEnabled` | Itinéraire |
| `homeMealsModuleEnabled` | Repas maison |
| `shoppingModuleEnabled` | Courses |

- [`trip.dart`](../../lib/features/trips/data/trip.dart) : champs, `fromMap`, `toMap`.
- [`trips_repository.dart`](../../lib/features/trips/data/trips_repository.dart) :
  `TripGenericModule` gagne `journey`, `homeMeals`, `shopping` ; `createTrip`
  et `updateTrip` acceptent les trois valeurs.
- [`firestore.rules`](../../firestore.rules) : les trois champs rejoignent la
  liste des champs modifiables avec « Modifier les infos générales ».
- Interrupteurs : section modules du
  [formulaire du voyage](../../lib/features/trips/presentation/trip_create_page.dart)
  et section « Modules génériques » de
  [`traveler_modules_toggle_list.dart`](../../lib/features/trips/presentation/traveler_modules_toggle_list.dart).
- Export / import de voyage : les champs du voyage sont copiés sauf une liste
  d'exclusions ; rien à faire.

### 1.2 Module Itinéraire

Regroupe tout ce qui est calculé à partir du parcours
([`trip_journey.dart`](../../lib/features/activities/presentation/trip_journey.dart)).
Désactivé :

- Planning
  ([`trip_activities_page.dart`](../../lib/features/activities/presentation/trip_activities_page.dart)) :
  plus de bouton de carte dans la ligne de filtres, plus de filtres « Nuits »
  et « Trajets », plus de nuits en fin de journée dans l'agenda, plus de
  trajets à prévoir.
- Page d'un transport : plus d'« Ajouter une correspondance ».
- Carte du voyage : la route redirige vers le planning.
- Restent : le trajet en voiture depuis le logement sur la page d'une
  activité, les transports déjà saisis (affichés comme des activités).

### 1.3 Module Repas maison

Couvre la cuisine du groupe : repas cuisinés, auberges espagnoles, chef,
recettes, ingrédients, contributions, et les parties de journée (matin / midi /
soir). **Le repas au restaurant reste toujours disponible.** Désactivé :

- Création d'un repas
  ([`trip_meal_details_page.dart`](../../lib/features/meals/presentation/trip_meal_details_page.dart)) :
  le choix du type de repas disparaît, le repas est au restaurant. Un repas
  existant cuisiné ou en auberge espagnole garde sa page telle quelle.
- L'entrée « Repas » du « + » du planning reste : elle ouvre directement le
  repas au restaurant (choix du restaurant et de l'heure). C'est ce qui garantit
  qu'un restaurant se planifie et apparaît dans l'agenda et sur la carte (un
  restaurant n'est jamais daté seul : c'est le repas qui le place).
- Formulaire du voyage : la section « premier repas / dernier repas »
  disparaît ; les bornes enregistrées sont des journées complètes (matin du
  premier jour, soir du dernier).
- Dates de présence des participants
  ([`trip_member_stay_options_editor.dart`](../../lib/features/trips/presentation/trip_member_stay_options_editor.dart),
  utilisé en rejoignant le voyage, dans les préférences et dans les infos de
  voyage) : dates seules, enregistrées en journées complètes. Avec l'ancien
  défaut (arrivée le soir, départ le matin), un déjeuner au restaurant le
  premier jour ne pré-cocherait personne.
- Réactivé plus tard : les champs réapparaissent, préremplis ; désactivé plus
  tard : les valeurs existantes sont gardées, pas réécrites.
- Permissions des repas : les lignes « Contribuer » et « Gérer les recettes »
  sont masquées.

Les parties de journée ne servent qu'au calcul automatique des convives d'un
repas (vérifié : ni les chambres, ni les nuits, ni l'agenda, ni les dépenses ne
les utilisent).

### 1.4 Module Courses

Désactivé :

- L'onglet Courses quitte la barre du bas (voir 1.5) ; la route des courses
  redirige vers l'aperçu (aucune notification n'ouvre cet onglet).
- Covoiturage : plus de « va faire les courses » ni de point de rendez-vous
  courses.
- Permissions : la carte « Courses » est masquée.

Les ingrédients des repas n'arrivent dans les courses que par la page des
courses : rien d'autre à masquer côté repas.

### 1.5 Barre du bas et onglet Carte

La barre est construite autour de la capsule Planning au centre (deux onglets
de chaque côté). Le 5e emplacement devient celui du module principal :

1. **Courses** si le module Courses est activé ;
2. sinon **Carte** si le module Itinéraire est activé ;
3. sinon la barre passe à quatre onglets (cas rare, hors modèles).

- [`trip_shell_page.dart`](../../lib/features/trips/presentation/trip_shell_page.dart) :
  destinations calculées à partir du voyage (barre mobile et rail large).
- [`router.dart`](../../lib/app/router.dart) : nouvelle branche `map` dans le
  shell, affichant la carte sans sa barre de titre (elle garde son zoom et sa
  position d'un onglet à l'autre). La route `activities/map` reste pour
  l'ouverture depuis le planning.
- [`trip_journey_map_page.dart`](../../lib/features/activities/presentation/trip_journey_map_page.dart) :
  option pour s'afficher sans barre de titre.
- Quand la carte est dans la barre, son bouton disparaît de la ligne de
  filtres du planning.

### 1.6 Permission « Gérer les chambres »

- Firestore : `permissions.rooms.manageRooms`, défaut **Participants** (aucun
  changement pour les voyages existants).
- [`trip_permissions.dart`](../../lib/features/trips/data/trip_permissions.dart) :
  famille `TripRoomsPermissions` ; `Trip.roomsPermissions` ; aide
  `canManageRoomsForTrip`.
- [`firestore.rules`](../../firestore.rules) : l'écriture des chambres exige
  cette permission (aujourd'hui, tout membre peut écrire).
- Écrite à la création du voyage avec les autres permissions. Les voyages
  existants sans cette valeur suivent le défaut, dans l'application comme dans
  les règles ; la remise à niveau des anciens voyages
  (`backfillLegacyTripPermissions`) n'est pas concernée.
- Page des chambres : sans la permission, lecture seule (pas de création, pas
  de modification, pas de personnalisation de nuit).
- Nouvelle page de permissions « Chambres » (route
  `settings/permissions/rooms`) et sa carte dans la liste des permissions,
  masquée quand le module Chambres est désactivé.

### 1.7 Permission « Modifier ses dates de présence »

- Firestore : `permissions.participants.editOwnStay`, défaut **Participants**.
- `TripParticipantsPermissions.editOwnStayMinRole` ; une ligne dans la page des
  permissions des participants.
- Cloud Function `updateParticipantProfile` : un voyageur qui modifie ses
  propres dates doit avoir cette permission. Modifier les dates d'un autre
  relève toujours de « Gérer les participants » (l'organisateur fixe les dates
  de chacun).
- Cloud Function `getInviteJoinContext` : renvoie si les dates sont verrouillées
  et si Repas maison est activé, pour la page d'invitation.
- Dates masquées quand elles sont verrouillées : en rejoignant le voyage
  ([`invite_join_page.dart`](../../lib/features/trips/presentation/invite_join_page.dart)),
  dans les préférences
  ([`trip_member_preferences_page.dart`](../../lib/features/trips/presentation/trip_member_preferences_page.dart))
  et dans les infos de voyage de soi-même
  ([`trip_participant_travel_info_page.dart`](../../lib/features/trips/presentation/trip_participant_travel_info_page.dart)).
  Le voyageur garde les dates du voyage.

### 1.8 Permissions des modules désactivés

Dans la liste des permissions, les cartes Covoiturage, Courses et Chambres sont
masquées quand leur module est désactivé ; dans les permissions des repas, les
lignes propres à Repas maison aussi (1.3).

### 1.9 Localisation

Nouvelles clés dans `app_fr`, `app_fr_FR`, `app_en`, `app_en_US` : libellés et
descriptions des trois modules, libellé de l'onglet « Carte », permissions
« Gérer les chambres » et « Modifier ses dates de présence », page des
permissions des chambres.

### 1.10 Déploiement (par le product owner)

Preview d'abord (`develop` → `planerz-preview`), puis production :

```powershell
firebase deploy --only firestore:rules --project planerz-preview
firebase deploy --only functions:updateParticipantProfile,functions:getInviteJoinContext --project planerz-preview
```

Puis la vérification d'invocation publique de chaque fonction redéployée
(`gcloud run services get-iam-policy …`), comme indiqué dans les consignes du
dépôt.

Tant que les règles ne sont pas déployées, activer ou désactiver un nouveau
module depuis l'application est refusé.

### 1.11 Vérifications

- `flutter analyze` sans nouveau problème ; tests existants verts.
- Tests unitaires : lecture des nouveaux champs (absent = activé), valeurs par
  défaut des nouvelles permissions, règle du 5e onglet.
- Cloud Functions : tests existants verts, test de la clé de permission de
  `updateParticipantProfile`.

---

## Lot 2 — Le choix du modèle et les masquages

### 2.1 Écran de choix

- Premier écran de la création d'un voyage (pas de la modification) : les
  quatre cartes, les textes ci-dessus, un bouton pour continuer.
- Le formulaire s'ouvre prérempli ; on peut revenir changer de modèle tant que
  le voyage n'est pas enregistré. Changer de modèle réapplique ses réglages.
- L'option « à la journée » reste dans le formulaire (une excursion organisée
  à la journée reste possible).

### 2.2 Préréglages

Un fichier de définitions (`trip_templates.dart`) décrit, pour chaque modèle,
les modules, l'option « à la journée », l'hébergement par défaut (même pour
toutes les nuits / nuit par nuit) et les permissions. `createTrip` accepte les
permissions du modèle à la place des valeurs par défaut (la règle de création
du voyage ne limite pas ce champ).

Permissions du **voyage organisé** : tout passe à « Administrateurs », sauf les
dépenses (les voyageurs font leurs comptes entre eux) et ce qui est déjà réservé
au créateur.

| Famille | Action | Défaut | Voyage organisé |
|---|---|---|---|
| Voyage | Partager l'accès | Participants | **Administrateurs** |
| Voyage | Infos générales, bannière, annonces | Administrateurs | Administrateurs |
| Voyage | Réglages, suppression | Créateur | Créateur |
| Participants | Gérer les participants, rôle admin | Créateur | Créateur |
| Participants | Modifier ses dates de présence | Participants | **Administrateurs** |
| Activités | Proposer, modifier | Participants | **Administrateurs** |
| Activités | Planifier, supprimer | Administrateurs | Administrateurs |
| Repas | Contribuer | Participants | **Administrateurs** |
| Repas | Gérer les recettes | Chef | **Administrateurs** |
| Repas | Créer, modifier, supprimer, choisir le restaurant | Administrateurs | Administrateurs |
| Covoiturage | Proposer | Participants | **Administrateurs** |
| Covoiturage | Modifier, point de rendez-vous | Administrateurs | Administrateurs |
| Chambres | Gérer les chambres | Participants | **Administrateurs** |
| Courses | Supprimer les articles cochés | Administrateurs | Administrateurs |
| Dépenses | Toutes | Participants | Participants |

Les autres modèles gardent les permissions par défaut.

### 2.3 Masquages

- **Onglet Suggestions** : masqué pour qui ne peut pas proposer d'activité.
  L'organisateur le garde comme espace de brouillons.
- **Code d'invitation** dans l'aperçu : masqué pour qui ne peut pas partager
  l'accès. Corrige au passage le rechargement en boucle du code (aujourd'hui,
  ces personnes voient « ··· » et l'application redemande le code à chaque
  affichage).
- **Pastilles de nuit des chambres** : visibles seulement quand une nuit est
  déjà personnalisée ; sinon, une action « Personnaliser une nuit » (pour qui
  peut gérer les chambres) les fait apparaître.

### 2.4 Localisation et déploiement

- Clés des quatre modèles (titres, accroches, listes, phrase sous les cartes),
  de l'action « Personnaliser une nuit » et du bouton pour continuer.
- Aucune règle ni Cloud Function à déployer.

---

## Hors périmètre, pour plus tard

- Modèle **Événement** (mariage, cousinade) : demanderait un module Dépenses.
- **Dupliquer un voyage** pour un organisateur qui répète un même circuit
  (l'export / import existant peut servir de base).
- Votes sur les suggestions : la règle Firestore les laisse à tout membre ;
  l'onglet étant masqué pour qui ne peut pas proposer, ils ne sont plus
  accessibles depuis l'application.
- Code d'invitation : il reste lisible dans le document du voyage par tout
  membre ; la restriction « Partager l'accès » s'applique dans l'application.
- Modules personnels (Bagages, Ridgegear, documents) : non préréglables, chacun
  les active pour soi.
