# Notification Center (channels)

## Contract (shared event)

Each trip notification event follows this contract:

- `channel`: logical channel (`messages`, `activities`, ...)
- `tripId`: trip identifier
- `actorId`: uid of the user who produced the event
- `type`: event type (example: `trip_message`, `trip_activity`)
- `title` / `body`: push text
- `targetPath`: deep-link path opened by app/web (`/trips/{tripId}/...`)
- `createdAt`: event timestamp
- `payload` (optional): extra key/value data

## Source of truth for unread

- Per-user per-trip aggregate: `users/{uid}/tripNotificationCounters/{tripId}`
- Shape:
  - `channels.messages: number`
  - `channels.activities: number`
  - `total: number`
  - `updatedAt: serverTimestamp`
- Read state remains: `trips/{tripId}/notificationReads/{uid}` with `channels.<name> = Timestamp`

Cloud Functions update counters:

- increment on new item for each channel (`messages`, `activities`)
- resync on `notificationReads` updates for multi-device consistency

## Read rules by channel

- **messages**: set read when `/messages` tab is actually visible, up to latest visible message timestamp.
- **activities**: currently same read model available via Notification Center API; UI marking can be added when activities screen visibility semantics are defined.

## Unread increment rules

- On new `messages/{messageId}`: increment all trip members except author.
- On new `activities/{activityId}`: increment all trip members except creator.
- Self-authored items do not count as unread for the actor.

## Exceptions / behavior

- If no counter exists yet for a channel, Flutter uses existing local fallback for messages badge.
- If push tokens are missing/invalid, unread counters still update.
- `targetPath` remains the primary deep-link on mobile and web service worker.

## Idempotence (`notificationQueue`)

La collection `notificationQueue` est la seule source d'idempotence pour l'envoi des pushes. La collection technique `functionEventLocks` n'est plus utilisée.

### Schéma d'IDs déterministes

| Type | ID document |
|------|-------------|
| `trip_message` | `trip_message__{tripId}__{messageId}` |
| `trip_activity` | `trip_activity__{tripId}__{activityId}` |
| `trip_announcement` | `trip_announcement__{tripId}__{announcementId}` |
| `cupidon_match` | `cupidon_match__{tripId}__{matchId}__{notifiedUid}` |
| `expense_reimbursement_paid` | `expense_reimbursement_paid__{tripId}__{expenseId}` |
| `expense_reimbursement_unpaid` | `expense_reimbursement_unpaid__{tripId}__{expenseId}` |

### Cycle de vie

1. **Enqueue** : les triggers/callables écrivent via `.create()` avec un ID déterministe. Si le document existe déjà (`ALREADY_EXISTS`), le retry upstream est ignoré sans doublon.
2. **Dispatch** : `dispatchNotificationQueue` supprime atomiquement le document en transaction (claim), puis traite les données sur la snapshot locale.
3. **État** : document présent = en attente de traitement ; document absent = déjà consommé (ou jamais créé).

### Choix at most once

Si la fonction crashe après la suppression du document et avant l'envoi FCM, la notification est perdue. Ce choix est assumé pour des notifications accessoires : aucun document stale, pas de collection fantôme, et les retries sont naturellement no-op.

### Collections exclues du nettoyage technique

Ne pas purger via le script de nettoyage infrastructure :

- `users/{uid}/tripNotificationCounters`
- `trips/{tripId}/notificationReads`
- `users/{uid}/fcmTokens`

Ces collections portent l'état produit (compteurs, lecture, tokens).

## Migration plan (2 steps)

1. Deploy backend + rules:
   - counters aggregation functions
   - activity notification function
   - new rules to read `tripNotificationCounters`
2. Roll out Flutter Notification Center:
   - switch messaging read write to generic API
   - consume backend counters for badges (with fallback)

## Manual test checklist

### Messages channel

- User A sends message in a trip with users A/B.
- Check user B:
  - receives push with `targetPath=/trips/{tripId}/messages`
  - `users/B/tripNotificationCounters/{tripId}.channels.messages` increments
  - badge on Messagerie tab increments
- Open messages tab as B and ensure read mark only occurs when tab is visible.
- After read mark, counter returns to 0 on all B devices.

### Activities channel

- User A creates an activity.
- Check user B:
  - receives push with `targetPath=/trips/{tripId}/activities`
  - `channels.activities` increments
- Update read timestamp for `activities` channel and verify counter sync to expected value.

### Cross-platform deep-link

- Mobile foreground/background/cold start: tapping push opens `targetPath`.
- Web/PWA notification click opens/focuses tab and navigates to `targetPath`.

