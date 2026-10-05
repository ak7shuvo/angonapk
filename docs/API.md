# API

Base path `/api/v1`. Interactive docs at `/docs` outside production (disabled in production). The table below was generated from the running app's OpenAPI document.

## Conventions
- **Auth**: `Authorization: Bearer <access_token>`. Everything except `/health`, `/auth/register` and `/auth/login` requires it. Missing or invalid token → `401`.
- **Errors**: FastAPI's `{"detail": ...}`. Validation and duplicate-account errors use `detail: [{"loc": ["body", "<field>"], "msg": "..."}]` so clients show per-field messages. `403` not allowed, `404` not found (also used to avoid leaking drafts/private content), `409` conflict, `413` too large, `415` unsupported media, `422` invalid input, `429` rate limited (with `Retry-After`).
- **Pagination**: list endpoints take `limit` (1–50) and an opaque `cursor`, and return `{items, next_cursor}` (`next_cursor` is null on the last page). Cursors are keyset-based, stable while new content arrives, and an invalid cursor is `422`. Places search, search and map use `limit`/`offset`.
- **Times** are UTC ISO-8601. **IDs** are UUIDs. Author summaries never include email.
- **Media**: clients upload with `POST /media`, then reference the returned asset id when creating posts, stories or profiles. Clients never send storage paths. Assets can only be attached once, by their owner. In development, stored files are served under `/media` (disabled in production).
- **Idempotent writes**: `PUT` like/save/follow twice leaves one record; `DELETE` is safe to repeat.
- **Rate limits** are per client IP or per user, in process (see [SECURITY](SECURITY.md)).

## Endpoints

### System

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/health` | – | `{status, environment, database}`; `degraded` if the database is unreachable. |

### Auth

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/auth/register` | – | `{email, username, password}` → `201` session. `409` if email/username taken, `422` invalid. Rate limited (10/hour/IP). |
| POST | `/auth/login` | – | `{identifier (email or username), password}` → session. One generic `401` for every failure. Rate limited (20/min/IP, 10/5 min/account). |
| POST | `/auth/logout` | yes | `204`; revokes the presented token server-side. |

### Users

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/users/me` | yes | The signed-in user with profile. |
| PATCH | `/users/me/profile` | yes | Partial update of `display_name`, `bio`, `location`, `creator_type`, `avatar_media_id`, `cover_media_id`. Unknown fields (e.g. `role`) → `422`. |
| GET | `/users/me/saved/posts` | yes | Posts you saved, most recently saved first. |
| GET | `/users/me/saved/stories` | yes | My Saved Stories |
| GET | `/users/{username}` | yes | Public Profile |
| GET | `/users/{username}/posts` | yes | A user's posts, newest first. |
| GET | `/users/{username}/places` | yes | Places this person has documented (posts or published stories). |
| PUT | `/users/{username}/follow` | yes | Idempotent: following twice leaves one follow. |
| DELETE | `/users/{username}/follow` | yes | Unfollow |
| GET | `/users/{username}/followers` | yes | Followers |
| GET | `/users/{username}/following` | yes | Following |

### Media

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/media` | yes | Multipart field `file`; JPEG/PNG/WebP, validated by decoding and re-encoded (EXIF stripped). `?purpose=avatar` crops to 512×512. 60 per 10 min per user. |
| DELETE | `/media/{asset_id}` | yes | Remove an uploaded image that has not been attached to anything yet. |

### Posts

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/posts` | yes | `{body?, location_text?, media?: [{asset_id, alt_text?}], tags?, place_id?}`. Needs text or media. Body ≤ 2000, ≤ 10 media, ≤ 20 tags. 30/hour per user. |
| GET | `/posts` | yes | Feed, newest first. `scope=all|following`, `tag=`. Keyset pagination. |
| GET | `/posts/{post_id}` | yes | Get Post |
| DELETE | `/posts/{post_id}` | yes | Delete Post |
| PUT | `/posts/{post_id}/like` | yes | Idempotent: liking twice leaves one like. |
| DELETE | `/posts/{post_id}/like` | yes | Unlike Post |
| PUT | `/posts/{post_id}/save` | yes | Save Post |
| DELETE | `/posts/{post_id}/save` | yes | Unsave Post |
| GET | `/posts/{post_id}/comments` | yes | List Comments |
| POST | `/posts/{post_id}/comments` | yes | `{body}` (≤ 1000). 60/hour per user. Notifies the post author. |

### Comments

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| DELETE | `/comments/{comment_id}` | yes | Authors can delete their own comments. |

### Stories

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/stories` | yes | `{title, content, cover_asset_id?, location_text?, tags?, place_id?, status: draft|published}`. 20/hour per user. |
| GET | `/stories` | yes | Published stories, newest first. |
| GET | `/stories/mine` | yes | Your own stories including drafts, most recently edited first. |
| GET | `/stories/{ref}` | yes | By id or slug. Drafts are visible only to their author. |
| GET | `/stories/{ref}/related` | yes | Related Stories |
| PATCH | `/stories/{story_id}` | yes | Update Story |
| DELETE | `/stories/{story_id}` | yes | Delete Story |
| POST | `/stories/{story_id}/publish` | yes | Publish Story |
| POST | `/stories/{story_id}/unpublish` | yes | Unpublish Story |
| PUT | `/stories/{story_id}/like` | yes | Like Story |
| DELETE | `/stories/{story_id}/like` | yes | Unlike Story |
| PUT | `/stories/{story_id}/save` | yes | Save Story |
| DELETE | `/stories/{story_id}/save` | yes | Unsave Story |

### Places

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/places` | yes | Search and filter places. `near_lat`+`near_lng` sorts by distance and returns |
| POST | `/places` | yes | Admin only. Places are curated, not user-generated. |
| PATCH | `/places/{place_id}` | yes | Admin only. |
| GET | `/places/{slug}` | yes | Get Place |
| GET | `/places/{slug}/posts` | yes | Place Posts |
| GET | `/places/{slug}/stories` | yes | Place Stories |
| GET | `/places/{slug}/photos` | yes | Place Photos |
| GET | `/places/{slug}/creators` | yes | People who have posted or published stories about this place. |

### Explore

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/explore` | yes | Home of discovery: categories, trending posts, featured stories, popular places |
| GET | `/search` | yes | Case-insensitive substring search across people, stories, posts and places. |

### Map

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/map/nearby` | yes | Places within `radius_km` (nearest first) and the latest posts and stories |

### Notifications

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/notifications` | yes | Your notifications, newest first. |
| GET | `/notifications/unread-count` | yes | Unread Count |
| POST | `/notifications/read-all` | yes | Mark All Read |
| POST | `/notifications/{notification_id}/read` | yes | Marks one of *your* notifications as read (idempotent). |

### Moderation

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| POST | `/reports` | yes | `{target_type: post|story|comment|user, target_id, reason: spam|harassment|hate|nudity|violence|misinformation|other, details?}` → `201` receipt. `409` duplicate, `400` own content, `404` unavailable target, `429` limit. |
| GET | `/admin/reports` | yes | Admin only. Filters `status`, `target_type`; each item carries a target preview and `report_count_for_target`. |
| GET | `/admin/reports/{report_id}` | yes | Get Report |
| PATCH | `/admin/reports/{report_id}` | yes | Admin only. `{status: open|reviewing|resolved|dismissed, resolution_note?}`; resolving/dismissing notifies the reporter. |

## Shapes worth knowing
- **Session** (`/auth/register`, `/auth/login`): `{access_token, token_type: "bearer", expires_at, user}`; `user.profile.is_complete` is computed by the server (display name and creator type set).
- **Post**: `{id, body, location_text, place_id, place, media[], tags[], author, created_at, updated_at, like_count, comment_count, liked_by_me, saved_by_me, following_author}`.
- **Story**: `{id, slug, title, summary, cover, location_text, place, tags[], status, published_at, reading_minutes, author, like_count, liked_by_me, saved_by_me, content, media[]}`. Content markup: paragraphs, `## heading`, `> quote`, `![caption](asset:<id>)`. Drafts are visible only to their author; `GET /stories/{ref}` takes an id or a slug.
- **Place**: `{id, slug, name, name_local, cover_url, latitude, longitude, division, district, upazila, country, description, metadata, post_count, story_count, distance_km}`. Seed places carry `metadata.seed = true`.
- **Notification**: `{id, type, actor, target_type, target_id, data, is_read, created_at}`. `type` is an open string: V1 produces `like`, `comment`, `follow` and `moderation`; clients render unknown types from `data.title` / `data.body`.
- **Report receipt** (what the reporter sees): `{id, target_type, target_id, reason, status}` only.

## Tokens
HS256 JWT with `sub`, `jti`, `type=access`, `iat`, `exp`; configured by `SECRET_KEY`, `JWT_ALGORITHM`, `ACCESS_TOKEN_EXPIRE_MINUTES` (default 7 days). Only `type=access` tokens are accepted; logout stores the `jti` in `revoked_tokens`. There are no refresh tokens yet (roadmap V1.1).

## Admin
Admin routes require `role = admin`. The role can only be set by an operator with database access (`python -m scripts.create_admin <username-or-email>`), never through the API.
