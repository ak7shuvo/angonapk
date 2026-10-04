# Development

## Backend
```bash
cd backend && cp .env.example .env && docker compose up -d db
python -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
alembic upgrade head          # apply migrations (uses DATABASE_URL)
uvicorn app.main:app --reload
ruff format . && ruff check . && pytest
```

Set `SECRET_KEY` in `.env` (`python -c "import secrets; print(secrets.token_urlsafe(48))"`). Tests use in-memory SQLite by default; run them against PostgreSQL with
`TEST_DATABASE_URL=postgresql+psycopg://angon:angon@localhost:5432/angon_test pytest`.
New migration: `alembic revision --autogenerate -m "message"` (review the result).

## Mobile
```bash
cd mobile && flutter pub get
dart format lib test && flutter analyze && flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
Real client-to-server check (needs a running, migrated API): `flutter test test/e2e --dart-define=E2E_API_BASE_URL=http://127.0.0.1:8000` (skipped otherwise).

`10.0.2.2` reaches the host from the Android emulator; use your LAN IP on a physical device. Android cleartext HTTP is enabled only in the debug manifest.

## Android builds
`flutter build apk --release` / `flutter build appbundle --release` require the Android SDK. Release currently uses the debug signing config; configure a real keystore (via untracked `key.properties`) before any distribution. These builds have **not** been verified in the CI/dev container used so far (no Android SDK).

## CI
`.github/workflows/ci.yml` runs format check, analyze and tests for mobile, and ruff + pytest (SQLite, then a PostgreSQL service) plus `alembic upgrade head` for the backend. Flutter is pinned to 3.47.6.
