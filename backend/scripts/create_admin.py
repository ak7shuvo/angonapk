"""Promote (or demote) an existing account to administrator.

The role can only be changed here, by someone with database access: no API
endpoint sets it, so a compromised client can never escalate itself.

    cd backend && python -m scripts.create_admin <username-or-email>
    cd backend && python -m scripts.create_admin <username-or-email> --revoke
"""

import argparse
import sys

from sqlalchemy.orm import Session

from app.db.session import get_session_factory
from app.repositories.user_repository import UserRepository


def set_role(db: Session, identifier: str, role: str) -> int:
    user = UserRepository(db).get_by_identifier(identifier)
    if user is None:
        print(f"No account matches {identifier!r}.", file=sys.stderr)
        return 1
    user.role = role
    db.commit()
    print(f"{user.username} is now {role!r}.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("identifier", help="username or email of an existing account")
    parser.add_argument("--revoke", action="store_true", help="return the account to a normal user")
    args = parser.parse_args(argv)
    with get_session_factory()() as db:
        return set_role(db, args.identifier, "user" if args.revoke else "admin")


if __name__ == "__main__":
    raise SystemExit(main())
