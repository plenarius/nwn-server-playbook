"""Every setting is an environment variable; .env.example lists them with what each does."""
import os
from dataclasses import dataclass


def _flag(name: str, default: bool) -> bool:
    value = os.environ.get(name, "").strip().lower()
    if not value:
        return default
    return value in ("1", "true", "yes", "on")


def _int(name: str, default: int = 0) -> int:
    value = os.environ.get(name, "").strip()
    return int(value) if value else default


@dataclass(frozen=True)
class Settings:
    discord_token: str
    guild_id: int
    dashboard_channel_id: int
    changelog_channel_id: int
    staff_role_id: int
    ops_api_url: str
    ops_api_key: str
    server_name: str
    refresh_seconds: int
    sync_commands: bool
    discord_gateway: bool
    webhook_secret: str
    webhook_port: int
    changelog_repos: tuple[str, ...]
    changelog_skip_label: str
    data_dir: str

    @classmethod
    def from_env(cls) -> "Settings":
        s = cls(
            discord_token=os.environ.get("DISCORD_TOKEN", "").strip(),
            guild_id=_int("GUILD_ID"),
            dashboard_channel_id=_int("DASHBOARD_CHANNEL_ID"),
            changelog_channel_id=_int("CHANGELOG_CHANNEL_ID"),
            staff_role_id=_int("STAFF_ROLE_ID"),
            ops_api_url=os.environ.get("OPS_API_URL", "http://10.77.0.1:8100").rstrip("/"),
            ops_api_key=os.environ.get("OPS_API_KEY", "").strip(),
            server_name=os.environ.get("SERVER_NAME", "Game server"),
            refresh_seconds=max(30, _int("REFRESH_SECONDS", 60)),
            sync_commands=_flag("SYNC_COMMANDS", True),
            discord_gateway=_flag("DISCORD_GATEWAY", True),
            webhook_secret=os.environ.get("GITHUB_WEBHOOK_SECRET", "").strip(),
            webhook_port=_int("WEBHOOK_PORT", 9090),
            changelog_repos=tuple(r.strip().lower() for r in os.environ.get("CHANGELOG_REPOS", "").split(",") if r.strip()),
            changelog_skip_label=os.environ.get("CHANGELOG_SKIP_LABEL", "no-changelog").strip().lower(),
            data_dir=os.environ.get("DATA_DIR", "/data"),
        )
        missing = [name for name, value in (
            ("DISCORD_TOKEN", s.discord_token), ("GUILD_ID", s.guild_id), ("DASHBOARD_CHANNEL_ID", s.dashboard_channel_id),
            ("STAFF_ROLE_ID", s.staff_role_id), ("OPS_API_KEY", s.ops_api_key),
        ) if not value]
        if missing:
            raise SystemExit("Missing settings: " + ", ".join(missing))
        if s.changelog_channel_id and len(s.webhook_secret) < 16:
            raise SystemExit("CHANGELOG_CHANNEL_ID is set, so GITHUB_WEBHOOK_SECRET must be too (16 characters or more)")
        return s
