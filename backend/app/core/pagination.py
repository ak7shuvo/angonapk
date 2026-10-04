"""Opaque keyset cursors over (timestamp, uuid)."""

import base64
import binascii
import uuid
from datetime import datetime


class InvalidCursorError(Exception):
    pass


def encode_cursor(stamp: datetime, ident: uuid.UUID) -> str:
    raw = f"{stamp.isoformat()}|{ident}"
    return base64.urlsafe_b64encode(raw.encode()).decode().rstrip("=")


def decode_cursor(cursor: str) -> tuple[datetime, uuid.UUID]:
    try:
        padded = cursor + "=" * (-len(cursor) % 4)
        stamp, ident = base64.urlsafe_b64decode(padded.encode()).decode().split("|")
        return datetime.fromisoformat(stamp), uuid.UUID(ident)
    except (ValueError, binascii.Error, UnicodeDecodeError) as exc:
        raise InvalidCursorError from exc
