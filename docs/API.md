# API

Base path: `/api/v1`. Interactive docs at `/docs` (non-production).

## Implemented
| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | `{status, environment, database}`; `status` is `degraded` if the DB is unreachable |

## Planned (by phase)
`/auth` (02) · `/users` (02/07) · `/posts` (03–04) · `/comments`, `/follows` (05) · `/stories` (06) · `/places` (09) · `/notifications` (11) · `/reports` (12).

Errors follow FastAPI's `{"detail": ...}` shape; the mobile client maps 401/403/404/422/5xx to typed exceptions.
