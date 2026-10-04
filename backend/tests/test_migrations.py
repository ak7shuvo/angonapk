from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, inspect

from app.core.config import get_settings


def test_migrations_upgrade_and_downgrade(tmp_path, monkeypatch):
    url = f"sqlite:///{tmp_path / 'm.db'}"
    monkeypatch.setenv("DATABASE_URL", url)
    get_settings.cache_clear()
    try:
        cfg = Config("alembic.ini")
        command.upgrade(cfg, "head")
        tables = set(inspect(create_engine(url)).get_table_names())
        assert {"users", "profiles", "revoked_tokens"} <= tables
        command.downgrade(cfg, "base")
        assert "users" not in set(inspect(create_engine(url)).get_table_names())
    finally:
        get_settings.cache_clear()
