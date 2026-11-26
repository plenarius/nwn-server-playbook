from bot.__main__ import Bot
from bot.controls import DashboardView, add_commands
from bot.settings import Settings


def settings(**over):
    base = dict(discord_token="x", guild_id=1, dashboard_channel_id=2, changelog_channel_id=3, staff_role_id=42,
                ops_api_url="http://10.77.0.1:8100", ops_api_key="k", server_name="S", refresh_seconds=60, sync_commands=False,
                discord_gateway=True, webhook_secret="s" * 32, webhook_port=9090, changelog_repos=(), changelog_skip_label="no-changelog",
                data_dir="/tmp")
    base.update(over)
    return Settings(**base)


async def test_commands_and_buttons_are_persistent():
    bot = Bot(settings())
    add_commands(bot)
    assert sorted(c.name for c in bot.tree.get_commands()) == ["cancel-restart", "restart"]
    view = DashboardView(bot)
    assert view.is_persistent()
    assert [b.custom_id for b in view.children] == ["dashboard:restart", "dashboard:cancel"]


def test_settings_need_a_webhook_secret(monkeypatch):
    for k, v in dict(DISCORD_TOKEN="x", GUILD_ID="1", DASHBOARD_CHANNEL_ID="2", STAFF_ROLE_ID="3", OPS_API_KEY="k",
                     CHANGELOG_CHANNEL_ID="4", GITHUB_WEBHOOK_SECRET="short").items():
        monkeypatch.setenv(k, v)
    try:
        Settings.from_env()
        raise AssertionError("accepted a short secret")
    except SystemExit as e:
        assert "GITHUB_WEBHOOK_SECRET" in str(e)
    monkeypatch.setenv("GITHUB_WEBHOOK_SECRET", "s" * 32)
    s = Settings.from_env()
    assert s.sync_commands and s.discord_gateway and s.refresh_seconds == 60


def test_tier3_parts_need_their_settings(monkeypatch):
    for k, v in dict(DISCORD_TOKEN="x", GUILD_ID="1", DASHBOARD_CHANNEL_ID="2", STAFF_ROLE_ID="3", OPS_API_KEY="k").items():
        monkeypatch.setenv(k, v)
    s = Settings.from_env()
    assert not (s.reports_channel_id or s.bridge_channel_id or s.roster_channel_id)  # all off until set
    monkeypatch.setenv("REPORTS_CHANNEL_ID", "5")
    for missing in ("REPORTS_REPO", "GITHUB_TOKEN"):
        try:
            Settings.from_env()
            raise AssertionError("reports without " + missing)
        except SystemExit as e:
            assert "REPORTS_REPO" in str(e)
        monkeypatch.setenv(missing, "you/reports" if missing == "REPORTS_REPO" else "t")
    monkeypatch.setenv("GITHUB_WEBHOOK_SECRET", "s" * 32)
    assert Settings.from_env().report_reply_prefix == "to reporter:"
    monkeypatch.setenv("BRIDGE_CHANNEL_ID", "6")
    try:
        Settings.from_env()
        raise AssertionError("a bridge without a database account")
    except SystemExit as e:
        assert "BRIDGE_DB_USER" in str(e)


async def test_only_the_bridge_asks_for_messages():
    assert not Bot(settings()).intents.message_content
    b = Bot(settings(bridge_channel_id=6))
    assert b.intents.message_content and b.intents.guild_messages
