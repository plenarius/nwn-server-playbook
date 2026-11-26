"""The changelog: GitHub calls this webhook when something happens in a repository, and each merged pull request
becomes a short post in the changelog channel. A request whose signature doesn't match the shared secret is refused."""
import asyncio
import hashlib
import hmac
import json
import logging
from collections import OrderedDict

import discord
from aiohttp import web

log = logging.getLogger("bot.changelog")


def signature_ok(secret: str, body: bytes, header: str) -> bool:
    """GitHub signs the raw body with the secret (HMAC-SHA256) and sends it as `sha256=<hex>`."""
    if not secret or not header.startswith("sha256="):
        return False
    expected = "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, header)


def entry(payload: dict, repos: tuple[str, ...] = (), skip_label: str = "") -> dict | None:
    """The changelog entry for a pull_request event, or None when it isn't a merge we post."""
    pr = payload.get("pull_request") or {}
    repo = (payload.get("repository") or {}).get("full_name", "")
    if payload.get("action") != "closed" or not pr.get("merged"):
        return None
    if repos and repo.lower() not in repos:
        return None
    labels = [label.get("name", "") for label in pr.get("labels", [])]
    if skip_label and skip_label in (name.lower() for name in labels):
        return None
    return {
        "key": f"{repo}#{pr.get('number')}",
        "repo": repo.split("/")[-1],
        "number": pr.get("number"),
        "title": (pr.get("title") or "").strip()[:200],
        "url": pr.get("html_url"),
        "author": (pr.get("user") or {}).get("login", "someone"),
        "labels": [name for name in labels if name.lower() != skip_label],
    }


def embed_for(item: dict) -> discord.Embed:
    embed = discord.Embed(title=f"{item['repo']} #{item['number']}: {item['title']}"[:256], url=item["url"], colour=0x5865F2)
    text = f"by {item['author']}"
    if item["labels"]:
        text += " · " + ", ".join(item["labels"])
    embed.set_footer(text=text)
    return embed


class Changelog:
    def __init__(self, client: discord.Client, settings):
        self.client = client
        self.s = settings
        self.queue: asyncio.Queue = asyncio.Queue()
        self.seen: OrderedDict[str, None] = OrderedDict()  # a redelivered event is posted once

    def routes(self, app: web.Application) -> None:
        app.router.add_post("/github", self.handle)

    async def handle(self, request: web.Request) -> web.Response:
        body = await request.read()
        if not signature_ok(self.s.webhook_secret, body, request.headers.get("X-Hub-Signature-256", "")):
            log.warning("refused a webhook with a bad or missing signature from %s", request.remote)
            return web.Response(status=401, text="bad signature")
        event = request.headers.get("X-GitHub-Event", "")
        try:
            payload = json.loads(body)
        except ValueError:
            return web.Response(status=400, text="not JSON")
        if event == "ping":
            log.info("webhook ping from %s", (payload.get("repository") or {}).get("full_name", "?"))
            return web.Response(text="pong")
        item = entry(payload, self.s.changelog_repos, self.s.changelog_skip_label) if event == "pull_request" else None
        if item is None:
            return web.Response(status=202, text="ignored")
        if item["key"] in self.seen:
            return web.Response(status=202, text="already posted")
        self.seen[item["key"]] = None
        while len(self.seen) > 500:
            self.seen.popitem(last=False)
        # Answer GitHub at once (it gives up after 10 seconds); the post goes out from the queue.
        self.queue.put_nowait(item)
        return web.Response(text="queued")

    async def run(self) -> None:
        channel = self.client.get_partial_messageable(self.s.changelog_channel_id)
        while True:
            item = await self.queue.get()
            for attempt in range(3):
                try:
                    await channel.send(embed=embed_for(item))
                    log.info("changelog: posted %s", item["key"])
                    break
                except discord.HTTPException as e:
                    log.warning("changelog: posting %s failed (%s), attempt %d", item["key"], e, attempt + 1)
                    await asyncio.sleep(5 * (attempt + 1))
