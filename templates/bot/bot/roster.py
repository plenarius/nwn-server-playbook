"""Who's online: one message, edited every minute from the operations API's roster (GET /server/online)."""
import asyncio
import json
import logging
import os
import time
from datetime import datetime, timezone

import discord

from .bridge import for_discord
from .ops_api import OpsApiError

log = logging.getLogger("bot.roster")

GREEN, GREY = 0x2ECC71, 0x95A5A6


def render(answer: dict | None, error: str | None = None, now: float | None = None) -> discord.Embed:
    stamp = datetime.fromtimestamp(now or time.time(), tz=timezone.utc)
    if answer is None:
        embed = discord.Embed(title="Who's online", colour=GREY, timestamp=stamp,
                              description=f"Can't tell right now: {error or 'no answer'}")
    else:
        names = [for_discord(c.get("name", "?")) for c in answer.get("characters", [])]
        if not names:
            text = "Nobody is in the game right now."
        else:
            text, shown = "", 0
            for name in names:
                if len(text) + len(name) + 3 > 3900:
                    break
                text += (" · " if text else "") + name
                shown += 1
            if shown < len(names):
                text += f" · and {len(names) - shown} more"
        embed = discord.Embed(title=f"Who's online ({answer.get('count', len(names))})", colour=GREEN if names else GREY,
                              timestamp=stamp, description=text)
    embed.set_footer(text="Updated every minute")
    return embed


class Roster:
    def __init__(self, client: discord.Client, api, settings):
        self.client = client
        self.api = api
        self.s = settings
        self._file = os.path.join(settings.data_dir, "roster.json")
        try:
            with open(self._file) as f:
                self.message_id = json.load(f).get("message_id")
        except (OSError, ValueError):
            self.message_id = None

    async def build(self) -> discord.Embed:
        try:
            return render(await self.api.online())
        except OpsApiError as e:
            log.warning("roster: %s", e)
            return render(None, e.message)

    async def refresh(self) -> None:
        embed = await self.build()
        channel = self.client.get_partial_messageable(self.s.roster_channel_id)
        if self.message_id:
            try:
                await channel.get_partial_message(self.message_id).edit(embed=embed)
                return
            except discord.NotFound:
                log.info("the roster message is gone; posting a new one")
        message = await channel.send(embed=embed)
        self.message_id = message.id
        tmp = self._file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"message_id": message.id}, f)
        os.replace(tmp, self._file)
        log.info("roster posted: message %s", message.id)

    async def run(self) -> None:
        while True:
            try:
                await self.refresh()
            except Exception:
                log.exception("roster refresh failed")
            await asyncio.sleep(self.s.refresh_seconds)
