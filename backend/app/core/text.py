import unicodedata


def slugify(title: str) -> str:
    """Unicode-aware slug: keeps Bengali letters (and their vowel signs)."""
    text = unicodedata.normalize("NFC", title).lower()
    out = []
    for ch in text:
        if ch.isalnum() or unicodedata.category(ch).startswith("M"):
            out.append(ch)
        elif out and out[-1] != "-":
            out.append("-")
    slug = "".join(out).strip("-")[:60].strip("-")
    return slug or "story"
