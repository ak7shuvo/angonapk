import unicodedata

MAX_TAGS = 8
MAX_TAG_LENGTH = 30


def normalize_tag(raw: str) -> str:
    """Lowercase, NFC-normalised, no leading '#'. Raises ValueError if unusable.

    Letters from any script are allowed (so Bengali tags work). Bengali vowel
    signs are combining marks (category M*), which str.isalnum() rejects, so
    they are allowed explicitly.
    """
    tag = unicodedata.normalize("NFC", raw.strip().lstrip("#").strip()).lower()
    if not 2 <= len(tag) <= MAX_TAG_LENGTH:
        raise ValueError(f"tags must be 2-{MAX_TAG_LENGTH} characters")
    for ch in tag:
        if not (ch.isalnum() or ch == "_" or unicodedata.category(ch).startswith("M")):
            raise ValueError("tags may only contain letters, digits and underscores")
    return tag


def normalize_tags(raw: list[str]) -> list[str]:
    seen: dict[str, None] = {}
    for item in raw:
        seen.setdefault(normalize_tag(item), None)
    tags = list(seen)
    if len(tags) > MAX_TAGS:
        raise ValueError(f"at most {MAX_TAGS} tags")
    return tags
