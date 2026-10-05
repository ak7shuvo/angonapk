# Roadmap

## COMPLETED V1
Each phase shipped with backend and Flutter tests; PostgreSQL 16 and a live-API client run were used to verify them.

- **01 Foundation**: Flutter app shell (theme, Bengali-ready typography, shared widgets, API client, typed errors, 5-tab navigation), FastAPI skeleton (settings, DB session, health, storage abstraction), CI, docs.
- **02 Authentication**: register, login, logout with server-side token revocation, Argon2 hashing, JWT; secure token storage; auth-aware routing; profile setup.
- **03 Home feed**: posts with keyset pagination, ownership rules, editorial post cards, loading/empty/error states.
- **04 Create post**: media upload with server-side image validation and re-encoding, tags, composer with drafts and upload progress.
- **05 Social**: likes, saves, comments, follow/unfollow, Following feed, optimistic UI reconciled to the server.
- **06 Stories**: story editor with drafts and inline photos, reader, discovery, related stories, saves.
- **07 Profiles**: public profiles, avatar/cover, followers/following, saved tabs.
- **08 Explore and search**: categories, trending, featured, popular places, search across everything.
- **09 Places**: curated places with admin create/update, place pages, tagging posts and stories to places.
- **10 Map**: nearby places and content, provider abstraction with a no-map fallback.
- **11 Notifications**: in-app like, comment and follow notifications with an unread badge; open type system for future kinds.
- **12 Moderation**: reporting with duplicate and spam protection; admin review endpoints; operator-only admin promotion.
- **13 Polish**: layout sweep (320dp, 2x text, light/dark, Bengali, keyboard), accessibility fixes, dark-mode contrast, Android back behaviour, duplicate-request test.
- **14 Bangladesh seed**: six `[Seed]` creators, 18 posts and 7 stories linked to 12 places, clearly marked and fact-free.
- **15 UX identity review**: every major screen reviewed from rendered screenshots; fixes applied; a screenshot tool added.
- **16 Security hardening**: rate limits, request size limits, security headers, strict production config checks, security tests.
- **17 Testing**: backend 98% line coverage (SQLite and PostgreSQL), Flutter 88%, live-API client tests.
- **18 CI/CD**: format, lint, tests (SQLite and PostgreSQL), migration checks, e2e job, advisory dependency audit, Android build workflow.
- **19 Documentation**: this documentation set.

## FUTURE V1.1 (hardening and gaps found while building V1)
- A real object-storage backend (S3/R2/GCS) behind `StorageBackend`, plus CDN URLs: production cannot serve uploads without it.
- Refresh tokens and shorter access-token lifetimes; password reset and email verification; account deletion and data export.
- Shared rate-limit store (Redis) or edge limits for multi-instance deployments.
- Edit posts and comments; delete/leave stories' orphaned media on a schedule (cleanup job exists as a function, not scheduled).
- Moderation tooling: remove content or suspend accounts from a review action; blocklists; a small admin web app on the existing `/admin/*` API.
- Push notifications and notification preferences (the in-app model is ready for them).
- Share (deep links), image zoom, video support, offline caching of the feed.
- Full-text search (PostgreSQL FTS or a search service) instead of substring matching; Bengali-aware ranking.
- Android release pipeline verified end to end: signing, Play Console internal track, crash reporting, analytics decisions; iOS build and Keychain/entitlement review.
- Localisation of UI strings (the UI is English with full Bengali content support).
- Observability: structured logs, metrics, tracing, uptime monitoring.

## FUTURE V2 (new product areas; not started, no schema yet)
- Community experiences and hosts; bookings and payments; reviews.
- Messaging and community spaces.
- Business and tourism-organisation accounts; verified creators.
- Recommendations and personalised feeds.
