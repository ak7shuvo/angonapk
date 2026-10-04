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
