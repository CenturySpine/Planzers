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

