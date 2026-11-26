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


def render(server_name: str, status: dict | None, progress: dict | None, up_since: float | None, error: str | None = None,
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
    if word in ("Online", "Starting", "Unhealthy") and up_since:
        embed.add_field(name="Last restart", value=f"<t:{int(up_since)}:R>", inline=True)
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
        self.up_since = self._load().get("up_since")
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
            json.dump({"message_id": self.message_id, "up_since": self.up_since}, f)
        os.replace(tmp, self._file)

    async def build(self) -> discord.Embed:
        try:
            status, progress = await asyncio.gather(self.api.status(), self.api.progress())
        except OpsApiError as e:
            log.warning("status: %s", e)
            return render(self.s.server_name, None, None, None, e.message)
        running = (status.get("status") or "").startswith("running")
        if running:
            # The log's time when there is one; otherwise the first refresh that saw the game running.
            self.up_since = started_at(progress) or self.up_since or time.time()
        else:
            self.up_since = None
        return render(self.s.server_name, status, progress, self.up_since)

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


def started_at(progress: dict | None, now: float | None = None) -> float | None:
    """When the running game last loaded its module, from the line the ops API finds in the game's log:
    `[Thu Nov 26 15:57:24] Loading Module: mymodule`. The game writes its container's time, which is UTC."""
    line = ((progress or {}).get("markers") or {}).get("module") or ""
    if not (line.startswith("[") and "]" in line):
        return None
    now = now or time.time()
    try:
        when = datetime.strptime(line[1:line.index("]")], "%a %b %d %H:%M:%S")
    except ValueError:
        return None
    year = datetime.fromtimestamp(now, tz=timezone.utc).year
    stamp = when.replace(year=year, tzinfo=timezone.utc).timestamp()
    if stamp > now + 86400:  # a start on 31 December, read in January
        stamp = when.replace(year=year - 1, tzinfo=timezone.utc).timestamp()
    return stamp
