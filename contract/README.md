# SDK API contract

The one source of truth for how apps talk to Unolink. The backend's contract tests and every SDK's tests run against
these files, so they can't drift apart. **Changes must stay backward compatible**: SDK versions already in the app
stores keep calling the API for years.

- `openapi.yaml`: the endpoints.
- `schemas/`: JSON Schema (draft 2020-12) for every request and response body.
- `scenarios/`: scripted request/response sequences. The backend replays them against a real API, and the SDKs use
  them to check their own requests and their handling of each response.
- `responses/`: canned server responses for SDK tests (retries, re-installs, quota, disabled).

## Basics

| | |
|---|---|
| Base URL | `https://api.unolink.dev/v1` (testing: `https://api-uat.unolink.dev/v1`) |
| Auth | `X-Unolink-Key: ulk_…`, the app's SDK key. Keys are publishable: they ship inside apps and only reach that app's data. |
| Format | JSON in, JSON out, UTF-8. Request bodies at most 256 KB. |
| User-Agent | `Unolink-Android/<version>`, `Unolink-iOS/<version>`, `Unolink-ReactNative/<version>`, `Unolink-Flutter/<version>`. Never a generic HTTP-client agent. |
| Errors | [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem details with a stable `code`. SDKs branch on `code`, never on text. |

## Endpoints

### `POST /v1/install`: first open

Sent once per install, at the first launch, before any event. **Idempotent per `installId`**: resending returns the
same attribution, so SDKs retry it freely until they get a 2xx.

- `installId`: a random UUID the SDK creates on first launch and keeps in the app's own storage. Never derived from
  the device.
- `playReferrer.raw`: the exact string Google Play's Install Referrer API returned (Android only), plus
  `clickAt`/`installBeginAt` in Unix seconds as Play reports them.

Attribution rules:
- **attributed**: the referrer has a `unolink_click_id` from this app's links, and no earlier install used it.
- **uncertain**: that click was already credited to another install (a reinstall, or a shared referrer).
- **unattributed**: everything else, including every iOS install. There is no fingerprinting, ever.

The response carries the link's current deep link and params. SDKs pass them to the app's deferred deep link
callback (Android).

### `POST /v1/events`: a batch of events

At most 100 events per request. Every event has a random `id` (UUID), so **resending a batch is always safe**:
already-stored IDs count as duplicates.

- Answer: `202 { accepted, duplicates, rejected: [{ id, code, message }] }`. A rejected event is dropped by the SDK,
  never retried.
- `409` with `install_required`: the server doesn't know this `installId`. Send `/v1/install` again, then the batch.
- Timestamps more than 7 days old or more than 1 hour ahead are replaced with the time the server received them.

### User ID (optional)

`userId` on `/v1/install` or `/v1/events` tells Unolink the app's own user ID for this install, e.g. the RevenueCat
app user ID. It lets server-side purchase data (RevenueCat webhooks: renewals, cancellations, refunds) join the
install that came from a link. **Unolink never stores it**: the server keeps only an HMAC-SHA256 of it under a
per-app secret, and hashes webhook IDs the same way to match. Send it once known (and again if it changes); `null`
or absent leaves the stored value unchanged.

### `GET /v1/clicks/{clickId}`

Looks up a click ID from the Play referrer: its link, deep link, params and UTM tags.

## Events

Names match `^[A-Za-z][A-Za-z0-9_.]{0,63}$`. Properties are a flat object of at most 20 keys; values are strings (at
most 200 characters), numbers or booleans; 4 KB in total.

| Name | Sent by | Counts toward quota |
|---|---|---|
| `first_open` | SDK, once per install | no |
| `session_start` | SDK, on launch or after 30 minutes in the background | no |
| `app_background` | SDK | no |
| `onboarding_step` | app: an onboarding screen **appeared**; properties `step`, `index`, `flow` only (see below) | no |
| `onboarding_skipped` | app: the user tapped Skip; `step` is the screen they tapped it on (see below) | no |
| `onboarding_completed` | app: the user finished the onboarding questions/screens (before any paywall or sign-up that follows them); optional `flow` | yes |
| `paywall_viewed`, `paywall_skipped` | app; property `placement` says where: `onboarding`, `feature_gate`, or the app's own name | yes |
| `sign_up` | app: an account was created (often after the paywall) | yes |
| `sign_in` | app: someone signed in to an account they already had (a returning user) | yes |
| `trial_started` | app | yes |
| `purchase` | app; **must** carry `revenue: { amount: "49.99", currency: "USD" }` | yes |
| `purchase_cancelled`, `purchase_failed` | app: the user closed the store sheet / the payment failed | yes |
| anything else | app (`track`) | yes |

Funnel steps are per app and configurable in the dashboard (any of these names, custom ones included), so apps whose
screens come in a different order still get a meaningful funnel. Each step counts installs that sent the event at any
time: the order never affects whether data is collected.
`onboarding_step` and `onboarding_skipped` are not funnel steps: the dashboard's Onboarding view orders them.

### Onboarding progress

One `onboarding_step` per onboarding screen, sent when the screen appears (not when its button is tapped), one
`onboarding_skipped` if the user taps Skip, and `onboarding_completed` at the end. They are **free**, so an onboarding
costs one quota event (its `onboarding_completed`) however many screens it has. Because they are free, their
properties are fixed:

| Property | | |
|---|---|---|
| `step` | required | A stable screen ID such as `goal` or `notifications`, same pattern as event names. |
| `index` | optional | The screen's position, an integer from 0 to 999. Lets the dashboard show the furthest screen reached. |
| `flow` | optional | Which onboarding this is (an A/B variant, a remote-config version, re-onboarding), same pattern as event names. |

- Any other property rejects the event with `validation`. So does a missing `step`.
- **Never put user data in `step` or `flow`**: they are screen and variant IDs, shown to everyone on the dashboard.
  The pattern allows no spaces and no `@`.
- Per install, at most 100 of these events and at most 40 different (`flow`, `step`) pairs. Events past that are
  rejected with `validation`.
- Accepted even above the quota's hard cap, like the funnel events.
- No "left the app" event is needed. The server works out each install's status: **completed**
  (`onboarding_completed`), **skipped** at the screen in `onboarding_skipped`, **dropped** at the last screen if
  nothing followed for 24 hours, **in progress** before that, and **not tracked** if the app sent no steps.
  Back navigation, branches (give each screen its own ID), app kills and relaunches need no special handling.

`revenue.amount` is a decimal **string**, never a float, so prices don't round. Only `purchase` carries revenue.

## Error codes

| Status | `code` | SDK behaviour |
|---|---|---|
| 400 | `validation` | Drop the request (it will never succeed). Log once. |
| 401 | `invalid_key` | Stop sending until the next app launch. Log loudly: the key is wrong or revoked. |
| 403 | `sdk_disabled` | The owner's plan has no SDK. Stop sending until the next app launch; keep nothing queued. |
| 409 | `install_required` | Re-send `/v1/install`, then the batch. |
| 202 with rejected `quota_exceeded` | | Drop those events. |
| 408, 429, 5xx, network errors | | Keep the batch and retry with exponential backoff (1 s up to 5 min, with jitter). |

## Versioning

The path carries the major version (`/v1`). Fields may be added to requests and responses at any time; SDKs must
ignore unknown response fields, and the server ignores unknown request fields. Removing or changing a field means
`/v2`.
