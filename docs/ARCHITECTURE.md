# Architecture

## Mobile (`mobile/lib`)
- `config/` build-time configuration via `--dart-define` (`API_BASE_URL`, `APP_ENV`).
- `core/` theme (colour tokens, typography, spacing), errors (`AppException` hierarchy), network (`ApiClient` interface + `HttpApiClient`).
- `models/` plain data classes; `repositories/` translate API ↔ models; `services/` Riverpod providers / wiring.
- `features/<name>/` screens and feature state; `shared/widgets/` reusable UI (loading, empty, error states, wordmark).
- `routing/` go_router with a 5-tab `StatefulShellRoute` (HOME · EXPLORE · CREATE · STORIES · PROFILE).

Rule: UI → providers → repositories → `ApiClient`. UI never touches HTTP. Server state is authoritative.

Typography: variable fonts bundled in `assets/fonts` (Newsreader, Inter, Noto Serif/Sans Bengali). Bengali is provided via `fontFamilyFallback` so mixed-script text renders with one style.

## Backend (`backend/app`)
`api/` routers (versioned `/api/v1`) · `core/` settings · `db/` engine/session/base · `models/` ORM · `schemas/` Pydantic · `services/` business logic · `repositories/` data access · `storage/` object-storage abstraction.

- Settings from environment (`.env.example`); production refuses the default `SECRET_KEY`.
- Engine is created lazily; PostgreSQL by default.
- `StorageBackend` protocol with a local dev implementation; S3/R2/GCS can be added behind `STORAGE_PROVIDER`.
- Admin panel: a separate web app will consume the same REST API, using future admin-only routers and role checks.

## Extensibility
Future entities (Experience, Host, Booking, Business, Community, Review, Payment) are intentionally not implemented; models will be added in their own modules.

## Authentication (Phase 02)
**Backend:** `models/` (`User`, `Profile`, `RevokedToken`) → `repositories/user_repository.py` → `services/auth_service.py` (register/login/authenticate/logout/profile) → `api/v1/auth.py`, `users.py`. `api/deps.py` provides `CurrentUser` (bearer token → active user, else 401). `core/security.py` holds Argon2 hashing and JWT encode/decode. Login verifies against a dummy hash for unknown users so timing does not reveal which accounts exist. Schema changes go through Alembic (`backend/migrations`); `env.py` reads `DATABASE_URL`.

**Mobile:** `AuthController` (Riverpod `Notifier`) is the single source of truth: `AuthChecking → Unauthenticated | Authenticated(user) | AuthCheckFailed`. `Authenticated` is entered only after the server confirms a session. The token lives only in `flutter_secure_storage` (`TokenStorage`); `HttpApiClient` attaches it and calls back on a 401 so an expired/revoked session signs the user out. Routing uses a pure `authRedirect(state, location)` rule: signed-out → auth screens, incomplete profile → profile setup, otherwise the tab shell.

## Home feed (Phase 03)
**Data model** (migration `0002`): `posts` (`id`, `author_id → users`, `body`, `location_text`, `place_id`, timestamps) and `post_media` (`post_id → posts`, `media_type`, `url`, `width`, `height`, `alt_text`, `position`; cascade-deleted with the post). `place_id` is a reserved nullable column with no foreign key: Phase 09 adds the `places` table and the constraint, so posts can reference a real Place without reshaping this table. Indexes: `(created_at, id)` for the feed, `author_id`, `place_id`.
**Backend flow:** `api/v1/posts.py` → `services/post_service.py` (ownership check, cursor encode/decode) → `repositories/post_repository.py` (keyset query; author and media are eager-loaded, no N+1). Posts can only be deleted by their author (403 otherwise).
**Mobile:** `models/post.dart` → `repositories/post_repository.dart` → `FeedController` (Riverpod `Notifier`; loading / ready / error, pagination, pull-to-refresh, stale-response guard, reset when the signed-in user changes) → `features/home/home_screen.dart` and `features/feed/widgets/` (`PostCard`, `PostMediaView`). Widgets never call the API. Storage-relative media paths are resolved against the API origin in the model layer.
**Interactions:** Like / Comment / Save / Share buttons are rendered but only show a "coming soon" message; nothing is sent to the server and no state flips locally.
**Seed data:** `backend/scripts/seed_dev.py` creates `seed_*` accounts (display names start with "[Seed]") and sample English and Bengali posts with flat-colour placeholder images. It refuses to run when `APP_ENV=production`.
