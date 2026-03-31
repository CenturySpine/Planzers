# Firebase Data Model (proposition)

## Services utilises

- Firebase Authentication (email/password + providers ulterieurs)
- Cloud Firestore (coeur de donnees)
- Firebase Storage (pieces jointes)
- Cloud Messaging (notifications)

## Collections Firestore

```text
users/{userId}
trips/{tripId}
trips/{tripId}/members/{userId}
trips/{tripId}/carpoolRides/{rideId}
trips/{tripId}/groceryItems/{itemId}
trips/{tripId}/mealPlans/{mealId}
trips/{tripId}/expenses/{expenseId}
trips/{tripId}/settlements/{settlementId}
```

## Schemas resumes

### `users/{userId}`
- displayName: string
- email: string
- photoUrl: string?
- createdAt: timestamp

### `trips/{tripId}`
- title: string
- destination: string
- startDate: timestamp
- endDate: timestamp
- ownerId: string
- createdAt: timestamp
- currency: string (ex: EUR)

### `trips/{tripId}/members/{userId}`
- role: string (owner | member)
- status: string (invited | active)
- joinedAt: timestamp?

### `trips/{tripId}/carpoolRides/{rideId}`
- driverId: string
- from: string
- to: string
- departureAt: timestamp
- seatCount: number
- passengerIds: string[]

### `trips/{tripId}/groceryItems/{itemId}`
- label: string
- quantity: string
- checked: bool
- assignedTo: string?
- createdBy: string
- createdAt: timestamp

### `trips/{tripId}/mealPlans/{mealId}`
- date: timestamp
- type: string (breakfast | lunch | dinner)
- title: string
- assignedTo: string?
- notes: string?

### `trips/{tripId}/expenses/{expenseId}`
- title: string
- amount: number
- currency: string
- paidBy: string
- participantIds: string[]
- category: string (food | transport | lodging | other)
- createdAt: timestamp

### `trips/{tripId}/settlements/{settlementId}`
- fromUserId: string
- toUserId: string
- amount: number
- status: string (pending | paid)

## Indexation recommandee

- `expenses`: index sur `createdAt` desc
- `mealPlans`: index sur `date` asc + `type`
- `carpoolRides`: index sur `departureAt` asc

## Regles de securite (principes)

- utilisateur authentifie uniquement
- acces a un voyage si membre du voyage
- ecriture reservee aux membres actifs
- operations critiques restreintes au owner (suppression voyage, gestion roles)
