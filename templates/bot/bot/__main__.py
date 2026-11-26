"""The bot: `python -m bot`. One process: the Discord client, the dashboard loop and the webhook receiver."""
import asyncio
import logging
import os
import time

import aiohttp
import discord
from aiohttp import web
from discord import app_commands

from .changelog import Changelog
from .controls import DashboardView, add_commands
from .dashboard import Dashboard
from .ops_api import OpsApi
from .settings import Settings

log = logging.getLogger("bot")


class Bot(discord.Client):
    def __init__(self, settings: Settings):
        # No privileged intents: the bot reads no messages. `guilds` lets it see members' roles in interactions.
        super().__init__(intents=discord.Intents(guilds=True))
        self.s = settings
        self.tree = app_commands.CommandTree(self)
        self.started = time.time()

    async def setup_hook(self) -> None:
        # discord.py runs this right after logging in, before the gateway (if any) connects.
        os.makedirs(self.s.data_dir, exist_ok=True)
        self.http_session = aiohttp.ClientSession()
        self.api = OpsApi(self.s.ops_api_url, self.s.ops_api_key, self.http_session)
        gateway = self.s.discord_gateway
        self.dashboard = Dashboard(self, self.api, self.s, (lambda: DashboardView(self)) if gateway else None)
        if gateway:
            self.add_view(DashboardView(self))  # the buttons of messages posted before a restart keep working
            add_commands(self)
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
        if self.s.changelog_channel_id:
            self.changelog = Changelog(self, self.s)
            self.changelog.routes(app)
            self.loop.create_task(self.changelog.run())
        self.runner = web.AppRunner(app, access_log=None)
        await self.runner.setup()
        await web.TCPSite(self.runner, "0.0.0.0", self.s.webhook_port).start()
        log.info("webhook receiver on port %d", self.s.webhook_port)
        self.loop.create_task(self.dashboard.run())

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
