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
