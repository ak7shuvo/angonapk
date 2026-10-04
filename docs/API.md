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

### Posts (all require auth)
| Method | Path | Description |
|--------|------|-------------|
| POST | `/posts` | `{body?, location_text?, media?: [{type: image\|video, url, width?, height?, alt_text?}]}` → `201 Post`. Needs text or at least one media item. Body ≤ 2000 chars, location ≤ 120, ≤ 10 media. Media `url` must be `http(s)://…` or a storage path starting `/media/`. Unknown fields (e.g. `author_id`, `place_id`) → `422`; the author is always the token's user. |
| GET | `/posts?limit=20&cursor=` | Feed, newest first. `limit` 1–50. Returns `{items: [Post], next_cursor}`; `next_cursor` is null on the last page. Invalid cursor → `422`. Until follows exist (Phase 05) this is the global timeline. |
| GET | `/posts/{id}` | One post; `404` if missing. |
| DELETE | `/posts/{id}` | `204` for the author; `403` for anyone else; `404` if missing. |

`Post`: `{id, body, location_text, place_id (reserved, always null), media: [{id, type, url, width, height, alt_text}], author: {id, username, display_name}, created_at, updated_at}`.
The author summary never includes email. Timestamps are UTC ISO-8601.

Pagination is keyset-based on `(created_at, id)`: stable when new posts arrive between page requests, with no duplicates or gaps, including posts sharing a timestamp. The cursor is opaque.

Not yet implemented (UI shows them as "coming soon"): likes, comments, saves, share, media upload (media is referenced by URL until Phase 04), editing posts.

In development, locally stored files are served under `/media` (disabled in production).

## Tokens
HS256 JWT with `sub`, `jti`, `type=access`, `iat`, `exp`. Configured by `SECRET_KEY`, `JWT_ALGORITHM`,
`ACCESS_TOKEN_EXPIRE_MINUTES` (default 7 days). Only `type=access` tokens are accepted; revoked `jti`s are stored in `revoked_tokens`.

## Planned (by phase)
post editing/upload (04) · `/comments`, `/follows` (05) · `/stories` (06) · `/users/{username}` public profiles (07) · `/places` (09) · `/notifications` (11) · `/reports` (12).
