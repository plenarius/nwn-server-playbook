"""The bot: `python -m bot`. One process: the Discord client, the dashboard loop and the webhook receiver."""
import asyncio
import logging
import os
import time

import aiohttp
import discord
from aiohttp import web
from discord import app_commands

from .bridge import Bridge
from .changelog import Changelog
from .controls import DashboardView, add_commands
from .dashboard import Dashboard
from .dev import add_dev_commands
from .ops_api import OpsApi
from .reports import GitHub, Reports, Store, add_report_command
from .roster import Roster
from .settings import Settings

log = logging.getLogger("bot")


class Bot(discord.Client):
    def __init__(self, settings: Settings):
        # `guilds` lets it see members' roles in interactions. Only the chat bridge reads messages, and only then does the bot ask
        # for them: Message Content is a privileged intent, switched on in the Developer Portal.
        intents = discord.Intents(guilds=True)
        if settings.bridge_channel_id:
            intents.guild_messages = intents.message_content = True
        super().__init__(intents=intents)
        self.s = settings
        self.tree = app_commands.CommandTree(self)
        self.started = time.time()
        self.tasks: set = set()

    async def setup_hook(self) -> None:
        # discord.py runs this right after logging in, before the gateway (if any) connects.
        os.makedirs(self.s.data_dir, exist_ok=True)
        self.http_session = aiohttp.ClientSession()
        self.api = OpsApi(self.s.ops_api_url, self.s.ops_api_key, self.http_session)
        gateway = self.s.discord_gateway
        self.reports = self.bridge = self.roster = None
        if self.s.reports_channel_id:
            self.reports = Reports(self, self.s, GitHub(self.s.github_token, self.http_session),
                                   Store(os.path.join(self.s.data_dir, "reports.db")))
            self.background(self.reports.run())
        if self.s.bridge_channel_id:
            import aiomysql
            pool = await aiomysql.create_pool(host=self.s.bridge_db_host, port=self.s.bridge_db_port, user=self.s.bridge_db_user,
                                              password=self.s.bridge_db_password, db=self.s.bridge_db_name, minsize=0, maxsize=2,
                                              connect_timeout=5, autocommit=True, charset="utf8mb4")
            self.bridge = Bridge(self, self.s, pool)
            self.background(self.bridge.run())
            log.info("chat bridge on")
        if self.s.roster_channel_id:
            self.roster = Roster(self, self.api, self.s)
            self.background(self.roster.run())
        self.dashboard = Dashboard(self, self.api, self.s, (lambda: DashboardView(self)) if gateway else None)
        if gateway:
            self.add_view(DashboardView(self))  # the buttons of messages posted before a restart keep working
            add_commands(self)
            if self.reports:
                add_report_command(self)
            if self.s.dev_role_id:
                add_dev_commands(self)
            guild = discord.Object(id=self.s.guild_id)
            self.tree.copy_global_to(guild=guild)
            if self.s.sync_commands:
                # This replaces every command this application has in the guild with this bot's two.
                synced = await self.tree.sync(guild=guild)
                log.info("commands synced to the guild: %s", ", ".join(c.name for c in synced))
            else:
                log.info("SYNC_COMMANDS=false: commands not sent to Discord")
        else:
            log.info("DISCORD_GATEWAY=false: posting only, no buttons or commands")

        app = web.Application(client_max_size=5 * 1024 * 1024)
        app.router.add_get("/health", self.health)
        if self.s.changelog_channel_id or self.reports:
            others = {"issue_comment": self.reports.on_github, "issues": self.reports.on_github} if self.reports else {}
            self.changelog = Changelog(self, self.s, others)
            self.changelog.routes(app)
            if self.s.changelog_channel_id:
                self.background(self.changelog.run())
        self.runner = web.AppRunner(app, access_log=None)
        await self.runner.setup()
        await web.TCPSite(self.runner, "0.0.0.0", self.s.webhook_port).start()
        log.info("webhook receiver on port %d", self.s.webhook_port)
        self.background(self.dashboard.run())

    def background(self, coro) -> None:
        # asyncio keeps only a weak reference to a task: without this one, a loop waiting on the network can vanish.
        self.tasks.add(self.loop.create_task(coro))

    async def on_message(self, message: discord.Message) -> None:
        if self.bridge:
            try:
                await self.bridge.on_message(message)
            except Exception:
                log.exception("bridge: a message from Discord was not sent to the game")

    async def health(self, request: web.Request) -> web.Response:
        # Healthy while the dashboard got edited recently, which also means Discord and the bot's loop are fine.
        fresh = time.time() - max(self.dashboard.last_ok, self.started) < 3 * self.s.refresh_seconds
        return web.json_response({"ok": fresh, "dashboard_updated": int(self.dashboard.last_ok)}, status=200 if fresh else 503)

    async def close(self) -> None:
        if getattr(self, "runner", None):
            await self.runner.cleanup()
        if getattr(self, "http_session", None):
            await self.http_session.close()
        await super().close()


async def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    settings = Settings.from_env()
    bot = Bot(settings)
    async with bot:
        if settings.discord_gateway:
            await bot.start(settings.discord_token)
        else:
            await bot.login(settings.discord_token)
            await asyncio.Event().wait()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except discord.LoginFailure:
        raise SystemExit("Discord refused the token: check DISCORD_TOKEN")
    except KeyboardInterrupt:
        pass
