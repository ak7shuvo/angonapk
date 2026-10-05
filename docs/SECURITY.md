# Security and production readiness

ANGON V1 has been reviewed and hardened for development and staging use. **It is not production-ready.** This page lists what exists, what is tested, and what a real deployment still has to add.

## Protections in place
| Area | What is done | Tested by |
|------|--------------|-----------|
| Passwords | Argon2id; 8–128 characters; login verifies against a dummy hash for unknown accounts so timing does not reveal which exist; one generic login error. | `test_auth.py` |
| Tokens | HS256 JWT with `exp`, `jti`, `type`; only access tokens accepted; logout revokes the `jti`; deactivated users lose access immediately. Stored on the device in Keystore/Keychain via `flutter_secure_storage`. | `test_auth.py`, `test_security.py` (wrong signature, expired, wrong type, `alg=none`, malformed), `test_edge_cases.py` |
| Authorisation | Ownership checks on every write (posts, comments, stories, media); drafts and unattached media are private; admin routes need `role=admin`, which no API endpoint can set; unknown request fields are rejected (`extra="forbid"`), so clients cannot send `author_id` or `role`. | feature tests, `test_reports.py` |
| Abuse limits | In-process sliding-window limits: login (per IP and per account), registration, uploads, posts, stories, comments, reports; daily report cap; duplicate and self-report rejection. `429` with `Retry-After`. | `test_security.py`, `test_reports.py` |
| Request size | Body limits enforced from `Content-Length` and while streaming (`413`); a larger limit for uploads. | `test_security.py` |
| Uploads | Validated by decoding (not by filename or `Content-Type`), JPEG/PNG/WebP only, size and pixel limits, EXIF/GPS and appended payloads removed by re-encoding, server-generated storage keys. | `test_media.py`, `test_security.py` |
| Path traversal | Storage keys are server-generated and `LocalStorage` rejects any path outside its root; the static `/media` mount (development only) does not serve outside it. | `test_security.py` |
| SQL injection | ORM parameter binding everywhere; `LIKE` wildcards escaped; NUL bytes (rejected by PostgreSQL) answer `422`. | `test_security.py` (hostile strings on search, filters, login, paths) |
| Headers and CORS | `nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, HSTS in production; CORS limited to configured origins, no credentials, explicit methods and headers; optional trusted-host list. | `test_security.py` |
| Production config | Startup refuses the default secret key, wildcard CORS, development database credentials, local storage and disabled rate limiting; `/docs` and `/media` are off in production. | `test_security.py` |
| Secrets | None in the repository; `.env`, keystores and `key.properties` are git-ignored; CI needs no secrets. | review |
| Dependencies | `pip-audit` reported no known vulnerabilities when run; CI runs it advisorily and Dependabot is enabled. | CI |
| Android | `allowBackup=false`; cleartext HTTP only in the debug manifest; release signing from an untracked `key.properties`. | review (not built here) |

## Known limitations
- **Tokens are long-lived (7 days) and there are no refresh tokens.** A stolen token is usable until it expires or the user logs out.
- **Rate limits are per process and in memory.** They reset on restart and are not shared across workers or instances, and they key on the client IP the server sees (set up `--proxy-headers` correctly or every user shares the proxy's address).
- Request body limits rely on `Content-Length` or streamed bytes seen by the app; the reverse proxy should enforce limits too.
- Registration reveals whether an email or username is taken (normal for a username-based social app).
- No email verification, password reset, account deletion/export, or two-factor authentication.
- No audit log of moderation actions beyond the reviewer id and time on each report; moderation does not yet remove content or suspend accounts.
- Image content is not scanned (no malware or NSFW detection).
- All public content is readable by any signed-in user; there are no private accounts or blocking yet.
- The Android release build and the Dockerfile have not been built in the development environment, and the `android.yml` workflow had not run when this was written.

## Required before real users
1. **Object storage** (S3/R2/GCS) behind `StorageBackend`, private bucket plus CDN, and scheduled orphan-media cleanup. Without it uploads cannot be served in production.
2. **TLS** end to end; an API gateway or reverse proxy with edge rate limiting (or a shared Redis limiter), request size limits and DDoS protection.
3. **Secrets management**: a random `SECRET_KEY`, rotated on a schedule; managed database credentials; no `.env` on servers.
4. **Authentication upgrades**: refresh tokens with short-lived access tokens, email verification, password reset, session/device management, account deletion.
5. **Database**: managed PostgreSQL with backups and a tested restore, least-privilege application user, migrations run as a release step, connection pooling.
6. **Moderation operations**: staff process and tooling for the `/admin/reports` queue, content takedown and account suspension, community guidelines, and a legal/privacy review (terms, privacy policy, data protection, takedown requests).
7. **Observability**: structured logging without personal data, error tracking, metrics, alerting, uptime checks.
8. **Release engineering**: a verified signed Android release, Play Console setup, crash reporting, and an iOS build with its own review.
9. **Independent security review / penetration test** of the deployed system.
