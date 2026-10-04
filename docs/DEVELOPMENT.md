# Development

## Backend
```bash
cd backend && cp .env.example .env && docker compose up -d db
python -m venv .venv && . .venv/bin/activate && pip install -r requirements-dev.txt
uvicorn app.main:app --reload
ruff format . && ruff check . && pytest
```

## Mobile
```bash
cd mobile && flutter pub get
dart format lib test && flutter analyze && flutter test
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```
`10.0.2.2` reaches the host from the Android emulator; use your LAN IP on a physical device. Android cleartext HTTP is enabled only in the debug manifest.

## Android builds
`flutter build apk --release` / `flutter build appbundle --release` require the Android SDK. Release currently uses the debug signing config; configure a real keystore (via untracked `key.properties`) before any distribution. These builds have **not** been verified in the CI/dev container used so far (no Android SDK).

## CI
`.github/workflows/ci.yml` runs format check, analyze and tests for both mobile and backend. Flutter is pinned to 3.47.6.
