"""The server dashboard: one message in one channel, edited in place every minute from the operations API."""
import asyncio
import json
import logging
import os
import time
from datetime import datetime, timezone

import discord

from .ops_api import OpsApi, OpsApiError

log = logging.getLogger("bot.dashboard")

GREEN, AMBER, RED, GREY = 0x2ECC71, 0xF1C40F, 0xE74C3C, 0x95A5A6


def look(status: str | None) -> tuple[str, int]:
    """The ops API's container state ("running:healthy", "exited", ...) as a word and a colour."""
    if status is None:
        return "Not found", GREY
    if status == "running:healthy" or status == "running":
        return "Online", GREEN
    if status.startswith("running"):  # starting or unhealthy
        return ("Starting" if status.endswith("starting") else "Unhealthy"), AMBER
    if status.startswith("restarting"):
        return "Restarting", AMBER
    return "Offline", RED


def render(server_name: str, status: dict | None, progress: dict | None, error: str | None = None,
           now: float | None = None) -> discord.Embed:
    """The dashboard's embed. Pure, so the tests can check it without Discord."""
    now = now or time.time()
    stamp = datetime.fromtimestamp(now, tz=timezone.utc)
    if status is None:
        embed = discord.Embed(title=server_name, colour=GREY, timestamp=stamp,
                              description=f"Can't reach the operations API: {error or 'no answer'}")
        embed.set_footer(text="Updated every minute")
        return embed

    word, colour = look(status.get("status"))
    embed = discord.Embed(title=server_name, colour=colour, timestamp=stamp)
    embed.add_field(name="Server", value=word, inline=True)
    players = status.get("players", -1)
    if word == "Offline":
        players_text = "-"
    else:
        players_text = str(players) if isinstance(players, int) and players >= 0 else "?"
    embed.add_field(name="Players", value=players_text, inline=True)
    embed.add_field(name="Module", value=status.get("module") or "?", inline=True)
    if word in ("Online", "Starting", "Unhealthy"):
        since = started_at(status)
        embed.add_field(name="Last restart", value=f"<t:{int(since)}:R>" if since else "unknown", inline=True)
    embed.add_field(name="NWNX", value=status.get("nwnx_running") or "?", inline=True)

    pending = status.get("restart_pending") or (progress or {}).get("countdown")
    operations = (progress or {}).get("operations") or []
    if pending and pending.get("restart_at"):
        at = int(datetime.fromisoformat(pending["restart_at"]).timestamp())
        embed.add_field(name="Restart", value=f"<t:{at}:R> ({pending.get('reason', 'no reason given')})", inline=False)
    elif operations:
        embed.add_field(name="In progress", value=", ".join(operations), inline=False)
    embed.set_footer(text="Updated every minute")
    return embed


class Dashboard:
    """Keeps the id of the dashboard message in DATA_DIR, so a restart of the bot edits the same message."""

    def __init__(self, client: discord.Client, api: OpsApi, settings, view_factory=None):
        self.client = client
        self.api = api
        self.s = settings
        self.view_factory = view_factory  # None when the bot runs without the gateway: no buttons, they would do nothing
        self._file = os.path.join(settings.data_dir, "dashboard.json")
        self.message_id = self._load().get("message_id")
        self.last_ok = 0.0
        self._lock = asyncio.Lock()

    def _load(self) -> dict:
        try:
            with open(self._file) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {}

    def _save(self) -> None:
        tmp = self._file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"message_id": self.message_id}, f)
        os.replace(tmp, self._file)

    async def build(self) -> discord.Embed:
        try:
            status, progress = await asyncio.gather(self.api.status(), self.api.progress())
        except OpsApiError as e:
            log.warning("status: %s", e)
            return render(self.s.server_name, None, None, e.message)
        return render(self.s.server_name, status, progress)

    async def refresh(self) -> None:
        async with self._lock:
            embed = await self.build()
            channel = self.client.get_partial_messageable(self.s.dashboard_channel_id)
            view = self.view_factory() if self.view_factory else None
            if self.message_id:
                try:
                    await channel.get_partial_message(self.message_id).edit(embed=embed, view=view)
                    self._save()
                    self.last_ok = time.time()
                    return
                except discord.NotFound:
                    log.info("the dashboard message is gone; posting a new one")
            message = await channel.send(embed=embed, view=view)
            self.message_id = message.id
            self._save()
            self.last_ok = time.time()
            log.info("dashboard posted: message %s", message.id)

    async def run(self) -> None:
        while True:
            try:
                await self.refresh()
            except Exception:
                log.exception("dashboard refresh failed")
            await asyncio.sleep(self.s.refresh_seconds)


def started_at(status: dict | None) -> float | None:
    """When the game's container last started, from the ops API's `started_at` (ISO 8601 UTC, null when it can't tell)."""
    value = (status or {}).get("started_at")
    if not isinstance(value, str):
        return None
    try:
        when = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    return (when if when.tzinfo else when.replace(tzinfo=timezone.utc)).timestamp()
