#!/usr/bin/env bash
# Runs every check CI runs. Usage: tool/check.sh [backend|mobile]   (default: both)
#
# Backend tests use SQLite unless TEST_DATABASE_URL points at PostgreSQL, e.g.
#   TEST_DATABASE_URL=postgresql+psycopg://angon:angon@localhost:5432/angon_test tool/check.sh backend
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
what="${1:-all}"

backend() {
  echo "== backend: ruff format"; (cd "$root/backend" && ruff format --check .)
  echo "== backend: ruff check";  (cd "$root/backend" && ruff check .)
  echo "== backend: pytest";      (cd "$root/backend" && python -m pytest -q)
}

mobile() {
  echo "== mobile: dart format";  (cd "$root/mobile" && dart format --output=none --set-exit-if-changed lib test)
  echo "== mobile: flutter analyze"; (cd "$root/mobile" && flutter analyze)
  echo "== mobile: flutter test"; (cd "$root/mobile" && flutter test)
}

case "$what" in
  backend) backend ;;
  mobile) mobile ;;
  all) backend; mobile ;;
  *) echo "usage: $0 [backend|mobile]" >&2; exit 2 ;;
esac
echo "All checks passed."
