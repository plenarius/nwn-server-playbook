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
    # Tier 3. Each part is off until its channel is set.
    reports_channel_id: int = 0
    reports_repo: str = ""
    github_token: str = ""
    report_reply_prefix: str = "to reporter:"
    report_cooldown_minutes: int = 10
    bridge_channel_id: int = 0
    bridge_db_host: str = ""
    bridge_db_port: int = 3306
    bridge_db_user: str = ""
    bridge_db_password: str = ""
    bridge_db_name: str = "nwn"
    roster_channel_id: int = 0
    # Chapter 14, tier 3: /dev for members with this role (and staff). 0: no /dev.
    dev_role_id: int = 0

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
            reports_channel_id=_int("REPORTS_CHANNEL_ID"),
            reports_repo=os.environ.get("REPORTS_REPO", "").strip().lower(),
            github_token=os.environ.get("GITHUB_TOKEN", "").strip(),
            report_reply_prefix=os.environ.get("REPORT_REPLY_PREFIX", "To reporter:").strip().lower(),
            report_cooldown_minutes=_int("REPORT_COOLDOWN_MINUTES", 10),
            bridge_channel_id=_int("BRIDGE_CHANNEL_ID"),
            bridge_db_host=os.environ.get("BRIDGE_DB_HOST", "10.77.0.2").strip(),
            bridge_db_port=_int("BRIDGE_DB_PORT", 3306),
            bridge_db_user=os.environ.get("BRIDGE_DB_USER", "").strip(),
            bridge_db_password=os.environ.get("BRIDGE_DB_PASSWORD", "").strip(),
            bridge_db_name=os.environ.get("BRIDGE_DB_NAME", "nwn").strip(),
            roster_channel_id=_int("ROSTER_CHANNEL_ID"),
            dev_role_id=_int("DEV_ROLE_ID"),
        )
        missing = [name for name, value in (
            ("DISCORD_TOKEN", s.discord_token), ("GUILD_ID", s.guild_id), ("DASHBOARD_CHANNEL_ID", s.dashboard_channel_id),
            ("STAFF_ROLE_ID", s.staff_role_id), ("OPS_API_KEY", s.ops_api_key),
        ) if not value]
        if missing:
            raise SystemExit("Missing settings: " + ", ".join(missing))
        if s.changelog_channel_id and len(s.webhook_secret) < 16:
            raise SystemExit("CHANGELOG_CHANNEL_ID is set, so GITHUB_WEBHOOK_SECRET must be too (16 characters or more)")
        if s.reports_channel_id and not (s.reports_repo.count("/") == 1 and s.github_token and len(s.webhook_secret) >= 16):
            raise SystemExit("REPORTS_CHANNEL_ID is set, so REPORTS_REPO (owner/name), GITHUB_TOKEN and GITHUB_WEBHOOK_SECRET must be too")
        if s.bridge_channel_id and not (s.bridge_db_user and s.bridge_db_password):
            raise SystemExit("BRIDGE_CHANNEL_ID is set, so BRIDGE_DB_USER and BRIDGE_DB_PASSWORD must be too")
        return s
