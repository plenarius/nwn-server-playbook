"""The chat bridge: one Discord channel and the game's shout channel. Lines from the game come out of the chat_out table;
lines from Discord go in as "chat" jobs on the work queue (chapter 5, tier 3). Mentions are stripped both ways, and both
ways are rate-limited."""
import asyncio
import json
import logging
import os
import re
import time
from collections import defaultdict, deque

import discord

log = logging.getLogger("bot.bridge")

ZWSP = "​"  # after an @, it stops Discord reading a mention
COLOUR = re.compile(r"<c...>|</c>", re.S)  # the game's colour codes
USER = re.compile(r"<@!?(\d+)>")
ROLE = re.compile(r"<@&(\d+)>")
CHANNEL = re.compile(r"<#(\d+)>")
EMOJI = re.compile(r"<a?:(\w+):\d+>")
TO_GAME_LENGTH = 300
POST_LIMIT = 1900


def for_discord(text: str) -> str:
    """A line from the game, safe to post: no colour codes, no formatting, and no @ that Discord could read as a mention."""
    text = COLOUR.sub("", text)
    text = discord.utils.escape_markdown(text)
    return text.replace("@", "@" + ZWSP)


def for_game(message) -> str:
    """A Discord message as plain text for the game: mentions as names, custom emoji as :name:, no @everyone, one line."""
    text = message.content
    users = {str(m.id): getattr(m, "display_name", m.name) for m in message.mentions}
    roles = {str(r.id): r.name for r in getattr(message, "role_mentions", [])}
    text = USER.sub(lambda m: "@" + users.get(m.group(1), "someone"), text)
    text = ROLE.sub(lambda m: "@" + roles.get(m.group(1), "role"), text)
    text = CHANNEL.sub(lambda m: "#" + getattr(message.guild.get_channel(int(m.group(1))) if message.guild else None, "name", "channel"), text)
    text = EMOJI.sub(lambda m: f":{m.group(1)}:", text)
    text = text.replace("@everyone", "everyone").replace("@here", "here")
    text = COLOUR.sub("", text)
    text = " ".join(text.split())  # newlines and runs of spaces: one line
    if getattr(message, "attachments", None):
        text = (text + " [picture]").strip()
    return text[:TO_GAME_LENGTH]


def speaker_name(member) -> str:
    return " ".join(COLOUR.sub("", getattr(member, "display_name", "someone")).split())[:32] or "someone"


class RateLimit:
    """At most `count` events per `seconds` for each key, and `total` for everyone together."""

    def __init__(self, count: int, seconds: float, total: int):
        self.count, self.seconds, self.total = count, seconds, total
        self.by_key: dict[object, deque] = defaultdict(deque)
        self.everyone: deque = deque()

    def allow(self, key, now: float | None = None) -> bool:
        now = now if now is not None else time.monotonic()
        mine = self.by_key[key]
        for q in (mine, self.everyone):
            while q and now - q[0] >= self.seconds:
                q.popleft()
        if len(mine) >= self.count or len(self.everyone) >= self.total:
            return False
        mine.append(now)
        self.everyone.append(now)
        return True


def posts_for(rows: list[tuple[int, str, str]], limit: int = POST_LIMIT) -> list[str]:
    """chat_out rows (id, speaker, text) as posts, none longer than `limit`, a line never split between two."""
    posts, lines, size = [], [], 0
    for _, speaker, text in rows:
        line = f"**{for_discord(speaker)}**: {for_discord(text)}"[:limit]
        if lines and size + 1 + len(line) > limit:
            posts.append("\n".join(lines))
            lines, size = [], 0
        lines.append(line)
        size += len(line) + 1
    if lines:
        posts.append("\n".join(lines))
    return posts


class Bridge:
    POLL_SECONDS = 3
    MAX_POSTS_PER_POLL = 3  # with 3 seconds between polls, well inside Discord's 5 posts in 5 seconds per channel

    def __init__(self, client: discord.Client, settings, pool):
        self.client = client
        self.s = settings
        self.pool = pool  # aiomysql pool, as the bot's database account (chapter 5's db-accounts.sh bot)
        self.to_game = RateLimit(count=5, seconds=30, total=30)
        self._file = os.path.join(settings.data_dir, "bridge.json")
        self.last_id = self._load()
        self.last_ok = 0.0

    def _load(self) -> int | None:
        try:
            with open(self._file) as f:
                return int(json.load(f)["last_id"])
        except (OSError, ValueError, KeyError, TypeError):
            return None

    def _save(self) -> None:
        tmp = self._file + ".tmp"
        with open(tmp, "w") as f:
            json.dump({"last_id": self.last_id}, f)
        os.replace(tmp, self._file)

    async def query(self, sql: str, args=()) -> list[tuple]:
        async with self.pool.acquire() as conn:
            async with conn.cursor() as cur:
                await cur.execute(sql, args)
                return list(await cur.fetchall())

    async def on_message(self, message) -> bool:
        """A message in the bridge channel: a "chat" job for the game. Returns True when one was added."""
        if message.channel.id != self.s.bridge_channel_id or message.author.bot or message.webhook_id:
            return False
        text = for_game(message)
        if not text:
            return False
        if not self.to_game.allow(message.author.id):
            try:
                await message.add_reaction("⏳")  # an hourglass: not sent, too many at once
            except discord.HTTPException:
                pass
            return False
        await self.query("INSERT INTO work_queue (kind, args, added_by) VALUES ('chat', %s, 'discord')",
                         (speaker_name(message.author) + "\n" + text,))
        return True

    async def from_game(self) -> int:
        """Posts the lines the game added since last time; returns how many."""
        if self.last_id is None:  # the first start: begin at the newest line, don't replay the past
            rows = await self.query("SELECT COALESCE(MAX(id), 0) FROM chat_out")
            self.last_id = int(rows[0][0])
            self._save()
            return 0
        rows = await self.query("SELECT id, speaker, text FROM chat_out WHERE id > %s ORDER BY id LIMIT 200", (self.last_id,))
        if not rows:
            return 0
        posts = posts_for(rows)
        dropped = len(posts) - self.MAX_POSTS_PER_POLL
        posts = posts[: self.MAX_POSTS_PER_POLL]
        if dropped > 0:
            posts[-1] += f"\n*(and more: {dropped} post{'s' if dropped != 1 else ''} left out, the game was very busy)*"
        channel = self.client.get_partial_messageable(self.s.bridge_channel_id)
        for post in posts:
            await channel.send(post, allowed_mentions=discord.AllowedMentions.none())
        self.last_id = int(rows[-1][0])
        self._save()
        return len(rows)

    async def run(self) -> None:
        while True:
            try:
                await self.from_game()
                self.last_ok = time.time()
            except Exception as e:  # the database restarting, Discord busy: try again next time, nothing is lost
                log.warning("bridge: %s: %s", type(e).__name__, e)
            await asyncio.sleep(self.POLL_SECONDS)
