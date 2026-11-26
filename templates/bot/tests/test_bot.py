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
