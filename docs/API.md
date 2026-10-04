# API

Base path: `/api/v1`. Interactive docs at `/docs` (non-production).

Auth: `Authorization: Bearer <access_token>`. Errors use FastAPI's `{"detail": ...}`; validation and
duplicate-account errors use `detail: [{"loc": ["body", "<field>"], "msg": "..."}]` so clients can show
per-field messages.

## Implemented
| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | `/health` | – | `{status, environment, database}`; `degraded` if the DB is unreachable |
| POST | `/auth/register` | – | `{email, username, password}` → `201 {access_token, token_type, expires_at, user}`; `409` if email/username taken (case-insensitive), `422` on invalid input |
| POST | `/auth/login` | – | `{identifier (email or username), password}` → `200` same body; `401` with one generic message for unknown user, wrong password or disabled account |
| POST | `/auth/logout` | yes | `204`; revokes the presented token's `jti` server-side |
| GET | `/users/me` | yes | Current user with profile |
| PATCH | `/users/me/profile` | yes | Partial update of `display_name`, `bio`, `location`, `creator_type`; unknown fields (e.g. `role`, `username`) are rejected with `422` |

Rules: username `[a-z0-9_]{3,30}` (stored lowercase); password 8–128 chars (Argon2id hashed); email stored lowercase.
`profile.is_complete` is computed by the server (display name + creator type set) and drives the app's profile-setup step.
`creator_type`: traveler, storyteller, blogger, photographer, videographer, local_storyteller, researcher, tourism_business, guide, community_organization.

## Tokens
HS256 JWT with `sub`, `jti`, `type=access`, `iat`, `exp`. Configured by `SECRET_KEY`, `JWT_ALGORITHM`,
`ACCESS_TOKEN_EXPIRE_MINUTES` (default 7 days). Only `type=access` tokens are accepted; revoked `jti`s are stored in `revoked_tokens`.

## Planned (by phase)
`/posts` (03–04) · `/comments`, `/follows` (05) · `/stories` (06) · `/users/{username}` public profiles (07) · `/places` (09) · `/notifications` (11) · `/reports` (12).
