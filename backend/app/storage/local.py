from pathlib import Path

from app.storage.base import StoredObject


class LocalStorage:
    """Filesystem storage for local development only."""

    def __init__(self, root: str, public_prefix: str = "/media") -> None:
        self._root = Path(root).resolve()
        self._prefix = public_prefix.rstrip("/")
        self._root.mkdir(parents=True, exist_ok=True)

    def _path(self, key: str) -> Path:
        path = (self._root / key).resolve()
        if self._root not in path.parents:
            raise ValueError("invalid storage key")  # blocks path traversal
        return path

    def save(self, key: str, data: bytes, content_type: str) -> StoredObject:
        path = self._path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        return StoredObject(key, self.url_for(key), content_type, len(data))

    def delete(self, key: str) -> None:
        self._path(key).unlink(missing_ok=True)

    def url_for(self, key: str) -> str:
        return f"{self._prefix}/{key}"
