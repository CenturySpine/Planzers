## Prompt final - Feature Repas (Trip)

Objectif: finaliser la feature `Meals` pour un voyage avec une UX claire:
- une liste des repas groupee par date;
- une page dediee pour creer, consulter et modifier un repas;
- une suppression securisee avec confirmation explicite.

## Contexte actuel

Des bases existent deja:
- `lib/features/meals/data/trip_meal.dart`
- `lib/features/meals/data/meals_repository.dart`
- `lib/features/meals/presentation/trip_meals_page.dart`

La demande consiste a terminer proprement le scope MVP, aligner les routes, fiabiliser les regles Firestore et ajouter les tests prioritaires.

## Scope fonctionnel attendu

1. **Modele Firestore**
   - Collection: `trips/{tripId}/meals/{mealId}`
   - Champs attendus: `name`, `mealDateKey`, `mealDayPart`, `participantIds`, `createdBy`, `createdAt`, `updatedAt`
   - `participantCount` reste derive cote app (pas obligatoire en stockage).

2. **Liste des repas (`TripMealsPage`)**
   - Regroupement par `mealDateKey` (sections par jour).
   - Tri des sections par date croissante.
   - Tri des repas par `mealDayPart` dans chaque section.
   - Tap sur un repas -> navigation vers page detail.
   - FAB `+` -> navigation vers creation.

3. **Page dediee (`TripMealDetailsPage`)**
   - Un ecran unique pour creation + edition (pas de modal).
   - Champs: nom, date, partie de journee, participants.
   - En mode edition: charger la donnee existante puis sauvegarder.
   - En mode creation: persister puis retour a la liste.
   - Suppression avec `AlertDialog` obligatoire.

4. **Participants**
   - Auto-calcul depuis `TripMemberStay` selon date (+ regle dayPart si applicable).
   - L'utilisateur peut ajuster manuellement la selection avant sauvegarde.

5. **Routing**
   - `trips/:tripId/meals` (liste)
   - `trips/:tripId/meals/new` (creation)
   - `trips/:tripId/meals/:mealId` (detail/edition)
   - Remplacer tout placeholder meals existant par ces ecrans.

6. **Securite Firestore**
   - Mettre a jour `firestore.rules` pour `trips/{tripId}/meals/{mealId}`.
   - Regle cible: seuls les membres du trip peuvent lire/ecrire, avec niveau de contrainte coherent avec les autres sous-collections du projet.

7. **Tests minimum**
   - Parsing/serialisation de `TripMeal`.
   - Tri/regroupement chronologique.
   - Calcul participants (bornes de sejour + dayPart).
   - Navigation liste -> detail.
   - Confirmation de suppression.

## Fichiers de reference

- `lib/features/trips/data/trip_member_stay.dart`
- `lib/features/trips/data/trip_day_part.dart`
- `lib/features/trips/presentation/trip_shell_page.dart`
- `lib/features/activities/data/activities_repository.dart`
- `lib/features/shopping/presentation/trip_shopping_page.dart`
- `lib/features/meals/data/trip_meal.dart`
- `lib/features/meals/data/meals_repository.dart`
- `lib/features/meals/presentation/trip_meals_page.dart`
- `lib/features/meals/presentation/trip_meal_details_page.dart`
- `firestore.rules`

## Definition of Done

- Le parcours complet creation -> edition -> suppression fonctionne en UI.
- Les routes meals sont accessibles et reliees au shell trip.
- Les donnees sont persistantes et la liste se rafraichit correctement.
- Les regles Firestore couvrent explicitement la sous-collection meals.
- Les tests cibles passent et `flutter analyze` est propre.

## Verification manuelle rapide

1. Ouvrir un trip > onglet repas > verifier affichage groupe par date.
2. Creer un repas via `+` > verifier retour liste + affichage immediat.
3. Ouvrir un repas > modifier champs > sauvegarder > verifier persistance.
4. Tenter suppression > verifier popup > confirmer > verifier disparition.
5. Verifier participants auto puis ajustement manuel possible.
6. Lancer `flutter analyze`.