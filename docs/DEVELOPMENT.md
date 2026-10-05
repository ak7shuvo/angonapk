# Development

Run every check CI runs: `tool/check.sh` (or `tool/check.sh backend` / `tool/check.sh mobile`).

## Backend
```bash
cd backend
cp .env.example .env                 # set SECRET_KEY
docker compose up -d db              # local PostgreSQL 16 (development credentials)
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
python -m scripts.seed_dev           # optional sample content
uvicorn app.main:app --reload        # http://localhost:8000/docs
ruff format . && ruff check . && pytest
```

### Environment variables
| Variable | Default | Purpose |
|----------|---------|---------|
| `APP_ENV` | `development` | `development`, `staging` or `production`. Production enables the safety checks below and disables `/docs` and the `/media` mount. |
| `SECRET_KEY` | dev placeholder | JWT signing key. Generate with `python -c "import secrets; print(secrets.token_urlsafe(48))"`. Must be ≥ 32 random characters in production. |
| `JWT_ALGORITHM` | `HS256` | |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `10080` | Access-token lifetime (7 days; there are no refresh tokens yet). |
| `DATABASE_URL` | `postgresql+psycopg://angon:angon@localhost:5432/angon` | SQLAlchemy URL. |
| `CORS_ORIGINS` | `http://localhost:3000` | Comma-separated explicit origins (never `*` in production). The mobile app does not need CORS. |
| `ALLOWED_HOSTS` | empty | Comma-separated `Host` values the API answers to. |
| `STORAGE_PROVIDER` | `local` | `local` is development only. |
| `STORAGE_LOCAL_DIR` | `./var/uploads` | Where `local` stores files (served at `/media` in development). |
| `MAX_UPLOAD_BYTES` | `10485760` | Image upload limit. |
| `MAX_IMAGE_EDGE` / `MAX_IMAGE_PIXELS` | `4096` / `60000000` | Downscale target and decompression-bomb guard. |
| `MAX_REQUEST_BODY_BYTES` | `1048576` | Limit for non-upload request bodies. |
| `RATE_LIMIT_ENABLED` | `true` | In-process rate limits. Tests and the e2e run disable it. |
| `TEST_DATABASE_URL` | unset | Run pytest against PostgreSQL instead of SQLite. |

### PostgreSQL
```bash
docker compose up -d db
# tests against PostgreSQL (use a separate database)
TEST_DATABASE_URL=postgresql+psycopg://angon:angon@localhost:5432/angon_test pytest
```

### Migrations
`alembic upgrade head` applies; `alembic downgrade -1` rolls back one; `alembic revision --autogenerate -m "message"` creates one (review it, and run `alembic check` to confirm models and migrations agree). Migrations are written to work on SQLite (batch mode) and PostgreSQL.

### Seeding
- `python -m scripts.seed_dev` creates 12 places in Bangladesh, six `[Seed]` creators (`seed_rahim`, `seed_nusrat`, `seed_tanvir`, `seed_mitu`, `seed_arif`, `seed_sadia`; password `seed-password-123`), 18 posts and 7 stories (plus one draft) linked to those places. It is idempotent, replaces only its own content, and refuses to run when `APP_ENV=production`. All text is invented, non-factual placeholder content.
- `python -m scripts.create_admin <username-or-email>` makes an account an administrator (`--revoke` undoes it). This is the only way to grant the role.

### Starting the API for real
`uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips=<your proxy>` behind a TLS-terminating reverse proxy. A `Dockerfile` is provided (not built or run in the development environment; verify it in your pipeline).

## Mobile
```bash
cd mobile
flutter pub get
dart format lib test && flutter analyze && flutter test
flutter run --dart-define-from-file=config/dev.json    # copy config/dev.example.json first
```

### API and map configuration
Build-time values (`--dart-define`, or a JSON file passed with `--dart-define-from-file`; real config files are git-ignored):

| Define | Default | Purpose |
|--------|---------|---------|
| `API_BASE_URL` | `http://10.0.2.2:8000` | API origin. `10.0.2.2` is the Android emulator's alias for the host; use your LAN IP on a device. Release builds need `https`. |
| `APP_ENV` | `development` | `development` or `production`. |
| `MAP_PROVIDER` | `osm` | `osm` or `none` (list fallback). |
| `MAP_TILE_URL` | OpenStreetMap | Tile URL template. The public OSM server is for light development use only; use a tile provider for production. |
| `MAP_ATTRIBUTION` | © OpenStreetMap contributors | Shown on the map. |

### Tests
- `flutter test`: unit, controller and widget tests (about 200).
- Live-API client tests: start a migrated API, then
  `flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000`. Start that API with `RATE_LIMIT_ENABLED=false` because the tests register many accounts from one address. CI does this in its `e2e` job.
- Screenshots for design review: `flutter test test/tool/screenshots_test.dart --dart-define=SCREENSHOT_DIR=/tmp/shots` (loads the bundled fonts; photos appear as placeholders).

### Android builds
```bash
cd mobile
flutter build apk --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com
flutter build appbundle --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://api.example.com
```
Requires the Android SDK and JDK 17. **These builds have not been run in the environment this project was developed in (no Android SDK there), and nothing has been tested on a device or emulator.** The GitHub workflow `android.yml` builds both artifacts on a runner; confirm it is green before relying on it.

Signing: copy `android/key.properties.example` to `android/key.properties` (git-ignored), create an upload keystore with `keytool` (command in the example), and fill in the values. Without `key.properties` the release build is signed with the debug key, which is fine for local testing and must never be published.

## CI
`.github/workflows/ci.yml`: Flutter format, analyze and tests; backend ruff format/lint, pytest on SQLite and PostgreSQL 16, migration apply/rollback/re-apply and `alembic check`; an advisory `pip-audit`; and an `e2e` job that seeds a PostgreSQL-backed API and runs the Flutter client tests against it. `android.yml` builds the APK and AAB (no secrets required; optional signing secrets are documented in the file). Flutter is pinned to 3.47.6. Dependabot watches pip, pub and Actions.

## Production deployment considerations
See [SECURITY.md](SECURITY.md) for the full list. In short: HTTPS everywhere, an object-storage backend, a managed PostgreSQL with backups, secrets from a secret manager, a reverse proxy that sets forwarded headers and enforces edge rate limits, migrations run as a release step (`alembic upgrade head`), log aggregation and monitoring, and a tested restore procedure.
