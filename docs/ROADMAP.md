# Roadmap

## DONE
- **Phase 01 — Foundation**: Flutter app (theme, Bengali-ready typography, shared widgets, API client, error types, 5-tab navigation shell), FastAPI skeleton (settings, DB session, health endpoint, storage abstraction, CORS), CI, docs.
- **Phase 02 — Authentication**: User/Profile/RevokedToken models + Alembic migration `0001`; register, login, logout (server-side token revocation), `GET /users/me`, `PATCH /users/me/profile`; Argon2 hashing, JWT; Flutter secure token storage, Splash/Welcome/Login/Register/Profile-setup screens, auth-aware routing, minimal Profile tab with sign out.
- **Phase 03 — Home feed**: `Post`/`PostMedia` models + migration `0002`; create / feed (keyset pagination) / get / delete-own endpoints with ownership checks; dev seed script; Flutter Home feed with editorial post cards, media gallery, Bengali support, loading/empty/error/retry, pull-to-refresh, infinite scroll, profile entry point. Like/comment/save/share are visible placeholders only.

## IN PROGRESS
- _(none)_

## NEXT
- **Phase 04 — Create post**: composer, image upload via the storage abstraction, tags, draft-friendly state.
- Then: 05 Social interaction · 06 Stories · 07 Profiles · 08 Explore · 09 Places · 10 Map · 11 Notifications · 12 Moderation.
