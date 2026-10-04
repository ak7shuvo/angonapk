# ANGON

**Places. People. Stories.** — a mobile-first social platform for travel, culture and heritage storytelling, starting with Bangladesh.

| Part | Path | Stack |
|------|------|-------|
| Mobile app | `mobile/` | Flutter (Android first, iOS-ready), Riverpod, go_router |
| API | `backend/` | FastAPI, SQLAlchemy 2, PostgreSQL |
| Docs | `docs/` | Product, architecture, API, development, roadmap |

Status: **Phase 02 (Authentication) complete.** See [docs/ROADMAP.md](docs/ROADMAP.md).

## Quick start

```bash
# Backend (needs Python 3.11+, Docker optional for Postgres)
cd backend
cp .env.example .env            # then set SECRET_KEY
docker compose up -d db
python -m venv .venv && . .venv/bin/activate
pip install -r requirements-dev.txt
alembic upgrade head
uvicorn app.main:app --reload        # http://localhost:8000/docs

# Mobile (needs Flutter 3.47+)
cd mobile
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000   # Android emulator
```

More in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).
