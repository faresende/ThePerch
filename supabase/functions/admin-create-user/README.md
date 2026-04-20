# admin-create-user

Edge Function that creates new Supabase Auth users on behalf of an allowlisted admin caller.

## Why this exists

`auth.admin.createUser` requires the service-role key. Putting the service-role key anywhere near the iOS client is unsafe (it was the root cause of the 2026-04-20 incident). This function keeps the key inside Supabase's edge runtime and gates access to the `createUser` call behind a JWT allowlist.

## Who calls it

Claudinho (the home Mac mini agent), server-to-server. The iOS app does NOT call this function. If that ever changes, audit the allowlist and the threat model first.

## Prerequisites

### 1. Required function secrets

Set these via `supabase secrets set`. The `admin-create-user` function needs all four.

| Secret | Notes |
|---|---|
| `SUPABASE_URL` | Already present for other functions. |
| `SUPABASE_ANON_KEY` | Used to validate the caller's JWT. Safe to share. |
| `SUPABASE_SERVICE_ROLE_KEY` | Privileged key that actually creates the user. Never leaves the function. |
| `ADMIN_USER_UUIDS` | Comma-separated list of user UUIDs allowed to call this function. Empty means deny all. |

Example (do not commit real values):

```sh
supabase secrets set \
  --project-ref <project-ref> \
  ADMIN_USER_UUIDS="00000000-0000-0000-0000-000000000000,11111111-1111-1111-1111-111111111111"
```

### 2. Supabase CLI config

In `supabase/config.toml` (add if the file does not exist), declare the function:

```toml
[functions.admin-create-user]
verify_jwt = true
```

`verify_jwt = true` is the Supabase default, but declaring it explicitly makes the security posture of this function auditable. The function also re-validates the JWT inside its handler with `supabase.auth.getUser(jwt)` as defence in depth.

## Adding your user UUID to the allowlist

You need the UUID of the Supabase Auth user that Claudinho signs in as. To find it:

1. Open the Supabase Dashboard for project `cgmaotzmeoiueyzlchaz`.
2. Go to **Authentication → Users**.
3. Find Claudinho's row (or whichever account you use for server-to-server admin calls).
4. Copy the value in the **UID** column (it is a UUID v4 string like `ab12cd34-5678-90ef-1234-567890abcdef`).

Then add the UUID to the allowlist:

```sh
# First time (set the whole list):
supabase secrets set \
  --project-ref <project-ref> \
  ADMIN_USER_UUIDS="<claudinho-uuid>"

# Adding a second admin (get current, append, reset):
CURRENT="$(supabase secrets list --project-ref <project-ref> | awk '/ADMIN_USER_UUIDS/{print $2}')"
supabase secrets set \
  --project-ref <project-ref> \
  ADMIN_USER_UUIDS="${CURRENT},<new-uuid>"
```

The function re-reads `ADMIN_USER_UUIDS` on every invocation, so changes take effect without a redeploy.

## Deployment

```sh
supabase functions deploy admin-create-user --project-ref <project-ref>
```

## Invocation

Claudinho first signs in as an admin user (any valid Supabase Auth flow: password, OAuth, magic link). That produces a JWT. Then:

```sh
curl -X POST \
  "https://<project-ref>.supabase.co/functions/v1/admin-create-user" \
  -H "Authorization: Bearer ${ADMIN_JWT}" \
  -H "Content-Type: application/json" \
  --data '{
    "email": "new.user@example.com",
    "password": "a-long-random-passphrase-at-least-12",
    "user_metadata": { "display_name": "New User" },
    "email_confirm": true
  }'
```

Successful response (HTTP 201):

```json
{
  "user": {
    "id": "cf2b7e0c-...",
    "email": "new.user@example.com",
    "created_at": "2026-04-20T22:00:00.000Z"
  }
}
```

All error responses have the shape `{ "error": "<message>" }`.

## Request schema

| Field | Type | Required | Notes |
|---|---|---|---|
| `email` | string | yes | Must contain `@`. |
| `password` | string | no | Minimum 12 characters. If omitted, Supabase generates a random one (user will need magic link or password reset to log in). |
| `user_metadata` | object | no | Stored on the user row, exposed to the client. |
| `app_metadata` | object | no | Stored on the user row, NOT exposed to the client. Use for role flags. |
| `email_confirm` | boolean | no | Defaults `true`. When `true`, user can log in immediately without email verification. |

## Response status codes

| Status | Meaning |
|---|---|
| 201 | User created successfully. |
| 400 | Bad request body. |
| 401 | Missing, malformed, or expired JWT. |
| 403 | Caller's UUID is not on `ADMIN_USER_UUIDS`. |
| 405 | Method not allowed (only POST + OPTIONS). |
| 409 | Email already registered. |
| 500 | Internal error or required env var missing. |
| 503 | `ADMIN_USER_UUIDS` is unset or empty. Fails closed by design. |

## Security notes

- Never add an end-user UUID to `ADMIN_USER_UUIDS`. This allowlist is for server-side agents only.
- The JWT used by Claudinho should be short-lived. Refresh tokens belong in the agent's secret store, not in git.
- When rotating the service-role key, redeploy this function (its `SUPABASE_SERVICE_ROLE_KEY` secret must be updated) before revoking the old key.
- The function logs caller UUID and created user UUID to stdout. Deny events log the caller UUID and email. Treat those logs as potentially sensitive.
- Rate limiting is provided by Supabase's gateway. This function does not add its own.

## Local testing

```sh
supabase functions serve admin-create-user --env-file supabase/functions/admin-create-user/.env.local
```

Create `.env.local` (gitignored by `.env*` pattern) with:

```
SUPABASE_URL=http://localhost:54321
SUPABASE_ANON_KEY=<local-anon-key>
SUPABASE_SERVICE_ROLE_KEY=<local-service-role-key>
ADMIN_USER_UUIDS=<your-local-test-uuid>
```
