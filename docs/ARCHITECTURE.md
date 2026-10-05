# Architecture

Two deployables share one REST contract: a Flutter app (`mobile/`) and a FastAPI service (`backend/`) on PostgreSQL. A future admin web app will use the same API and the existing role checks.

## Backend (`backend/app`)
Layering, outermost to innermost: `api/v1` routers → `services` (business rules) → `repositories` (queries) → `models` (SQLAlchemy 2). `schemas/` are the Pydantic request/response types; `core/` holds settings, security, pagination, geo, text, rate limiting and middleware; `storage/` is the object-storage abstraction; `db/` the engine, session and declarative base (with a constraint naming convention so migrations are reversible).

- **Dependencies** are wired in `api/deps.py` with `Annotated` aliases (`CurrentUser`, `AdminUser`, `Posts`, `Stories`, …). Services receive their repositories and collaborators (e.g. `NotificationService`), so they are easy to test.
- **Config** comes from the environment (`.env.example`). Production startup refuses unsafe settings (see [SECURITY](SECURITY.md)).
- **Pagination** is keyset-based over `(timestamp, uuid)` with opaque cursors (`core/pagination.py`); engagement counts are loaded in batched queries (no N+1).
- **Media**: `MediaService` validates uploads by decoding with Pillow, re-encodes (dropping EXIF/GPS and appended payloads), and stores through `StorageBackend`. Assets have an owner and can be attached once; unattached assets can be removed and orphans cleaned up. `StorageBackend` has one implementation today (`LocalStorage`, development only); object storage is the V1.1 production requirement.
- **Notifications** are produced by the services that cause them and are best effort: a failure is logged and never breaks the like/comment/follow. `type` is an open string, so new kinds need no migration.
- **Moderation**: `reports` rows are one per reporter per target (unique constraint), the target may be any of four tables so it is not a foreign key, and reports outlive deleted targets.
- **Admin**: role is a column set only by an operator script; routes use the `AdminUser` dependency.
- **Rate limiting** is an in-process sliding window (`core/rate_limit.py`): correct for one instance, not shared across workers.

### Data model (Alembic migrations `0001`–`0009`)
| Migration | Tables |
|-----------|--------|
| 0001 | `users`, `profiles`, `revoked_tokens` |
| 0002 | `posts`, `post_media` |
| 0003 | `media_assets`, `tags`, `post_tags` |
| 0004 | `post_likes`, `post_saves`, `comments`, `follows` |
| 0005 | `stories`, `story_media`, `story_tags`, `story_likes`, `story_saves` |
| 0006 | profile avatar and cover columns |
| 0007 | `places`; `posts.place_id` and `stories.place_id` become foreign keys |
| 0008 | `notifications` |
| 0009 | `reports` |

Migrations run on SQLite (default test database) and PostgreSQL 16; CI also checks they roll back and that `alembic check` reports no drift.

## Mobile (`mobile/lib`)
`config/` build-time configuration (`--dart-define`) · `core/` theme, errors, network (`ApiClient` interface + `HttpApiClient`), maps abstraction, utils · `models/` plain data classes · `repositories/` API ↔ models · `services/` providers and platform services (secure storage, image picker, drafts) · `features/<name>/` screens and controllers · `shared/` reusable widgets and the generic paged list · `routing/` go_router with a 5-tab `StatefulShellRoute`.

Rules: UI → controllers (Riverpod `Notifier`s) → repositories → `ApiClient`; the UI never touches HTTP; the server is authoritative.

- **State**: `AuthController` (`AuthChecking → Unauthenticated | Authenticated | AuthCheckFailed`) is the single source of session truth; the token lives only in secure storage and a 401 signs the user out. `PagedController<T>` is the generic cursor-paginated list (loading/error/empty, refresh, load more, de-duplication, stale-response guard).
- **Optimistic UI**: likes, saves and follows apply instantly and are reconciled to the server's answer (and reverted on failure). Engagement overlays are shared so a post looks the same everywhere.
- **Maps**: `MapProviderAdapter` hides the provider; OpenStreetMap tiles by default, configurable tile URL and attribution, and `MAP_PROVIDER=none` shows a list instead.
- **Notifications**: an unread count provider refreshes on open, return from the inbox and a slow timer (no push in V1); the inbox renders known types and falls back to `data.title/body`.
- **Design system**: colour tokens (`AppColors`), spacing, typography with Newsreader/Inter and Noto Bengali fallbacks, theme-aware neutrals via `context.inkSoft` / `context.placeholder`, a light and a dark theme.
- **Accessibility and layout** are enforced by tests: a sweep renders every screen at 320dp, up to 2x text, light and dark, with Bengali and keyboard; tap-target and label guidelines; contrast ratios of the colour pairs.

## Testing strategy
- Backend: pytest, in-memory SQLite by default and PostgreSQL 16 through `TEST_DATABASE_URL`; dependency-overridden database and temporary storage.
- Flutter: unit, controller and widget tests against `FakeBackend` (an in-memory double of the API contract), plus `test/e2e/*` which drive the real Dart client, controllers and repositories against a live API and PostgreSQL (skipped unless `E2E_API_BASE_URL` is set).
- `test/tool/screenshots_test.dart` renders screens to PNG for design review (dev tool, off by default).

## Extensibility
The following are intentionally not implemented and have no schema: Experience, Host, Booking, Business, Community, Review, Payment, messaging. They will arrive as new modules; notifications, moderation and storage abstractions were shaped to accommodate them.
