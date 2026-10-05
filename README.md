# ANGON

**Places. People. Stories.** A mobile-first social platform for travel, culture and heritage storytelling, starting with Bangladesh. English and Bengali are both first-class.

| Part | Path | Stack |
|------|------|-------|
| Mobile app | `mobile/` | Flutter (Android first, iOS-ready), Riverpod, go_router |
| API | `backend/` | FastAPI, SQLAlchemy 2, Alembic, PostgreSQL |
| Docs | `docs/` | Product, architecture, API, development, security, roadmap |
| Tooling | `tool/`, `.github/` | `tool/check.sh`, CI, Android build workflow |

**Status: V1 feature scope is implemented** (accounts, feed, posts, social, stories, profiles, explore and search, places, map, notifications, moderation). It is a development-complete V1, **not production-ready**: see [docs/SECURITY.md](docs/SECURITY.md) for what a real deployment still needs, and [docs/ROADMAP.md](docs/ROADMAP.md) for what is done and what is next.

Honest limits: the Android APK/AAB build and on-device behaviour have not been exercised (the development environment had no Android SDK); everything was verified with automated tests and a Flutter client run against a live API and PostgreSQL.

## Quick start

```bash
# Backend (Python 3.11+; Docker optional for PostgreSQL)
cd backend
cp .env.example .env            # then set SECRET_KEY
docker compose up -d db
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
python -m scripts.seed_dev      # optional: clearly marked Bangladesh sample content
uvicorn app.main:app --reload   # http://localhost:8000/docs

# Mobile (Flutter 3.47+)
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```

Run every check CI runs with `tool/check.sh`. Full instructions, environment variables, migrations, seeding, Android builds and storage configuration: [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Documentation
- [Product](docs/PRODUCT.md): what ANGON is and what V1 contains
- [Architecture](docs/ARCHITECTURE.md): structure, data model, conventions
- [API](docs/API.md): every endpoint
- [Development](docs/DEVELOPMENT.md): setup, config, testing, builds, deployment notes
- [Security](docs/SECURITY.md): protections in place and production requirements
- [Roadmap](docs/ROADMAP.md): completed V1, future V1.1, future V2

Seed data (`scripts/seed_dev.py`) is invented placeholder content, always labelled `[Seed]`, and the script refuses to run in production.
