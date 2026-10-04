# Roadmap

## DONE
- **Phase 01 — Foundation**: Flutter app (theme, Bengali-ready typography, shared widgets, API client, error types, 5-tab navigation shell), FastAPI skeleton (settings, DB session, health endpoint, storage abstraction, CORS), CI, docs.
- **Phase 02 — Authentication**: User/Profile/RevokedToken models + Alembic migration `0001`; register, login, logout (server-side token revocation), `GET /users/me`, `PATCH /users/me/profile`; Argon2 hashing, JWT; Flutter secure token storage, Splash/Welcome/Login/Register/Profile-setup screens, auth-aware routing, minimal Profile tab with sign out.

## IN PROGRESS
- _(none)_

## NEXT
- **Phase 03 — Home feed**: post model + feed API; post cards with author, location, image, text, like/comment/save/share UI; loading, empty and error states.
- Then: 04 Create post · 05 Social interaction · 06 Stories · 07 Profiles · 08 Explore · 09 Places · 10 Map · 11 Notifications · 12 Moderation.
