"""Player reports: /report opens a form; the bot files it as an issue in a private GitHub repository and opens a private
thread for the reporter. A comment on the issue that starts with the reply prefix ("To reporter:") is posted in that
thread, and so is the issue being closed. The reporter's Discord id stays in the bot's own file, never in the issue."""
import asyncio
import logging
import sqlite3
import time

import aiohttp
import discord
from discord import app_commands

log = logging.getLogger("bot.reports")

KINDS = {"bug": "Something is broken", "idea": "An idea for the game"}


class GitHubError(Exception):
    pass


class GitHub:
    """The one call the reports make: open an issue. The token needs Issues (read and write) on that one repository."""

    def __init__(self, token: str, session: aiohttp.ClientSession):
        self._headers = {"Authorization": f"Bearer {token}", "Accept": "application/vnd.github+json",
                         "X-GitHub-Api-Version": "2022-11-28"}
        self._session = session

    async def create_issue(self, repo: str, title: str, body: str, labels: list[str]) -> int:
        async with self._session.post(f"https://api.github.com/repos/{repo}/issues", headers=self._headers,
                                      json={"title": title, "body": body, "labels": labels},
                                      timeout=aiohttp.ClientTimeout(total=20)) as r:
            data = await r.json(content_type=None)
            if r.status != 201:
                raise GitHubError(f"{r.status}: {(data or {}).get('message', r.reason)}")
            return data["number"]


class Store:
    """issue number -> (thread, reporter), and the comments already posted, in SQLite on the bot's volume."""

    def __init__(self, path: str):
        self.db = sqlite3.connect(path)
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS reports (issue INTEGER PRIMARY KEY, thread_id INTEGER NOT NULL,
                                                reporter_id INTEGER NOT NULL, created_at INTEGER NOT NULL);
            CREATE TABLE IF NOT EXISTS posted (event TEXT PRIMARY KEY);
        """)

    def add(self, issue: int, thread_id: int, reporter_id: int) -> None:
        with self.db:
            self.db.execute("INSERT OR REPLACE INTO reports VALUES (?, ?, ?, ?)", (issue, thread_id, reporter_id, int(time.time())))

    def get(self, issue: int) -> tuple[int, int] | None:
        return self.db.execute("SELECT thread_id, reporter_id FROM reports WHERE issue = ?", (issue,)).fetchone()

    def last_report_by(self, reporter_id: int) -> int:
        row = self.db.execute("SELECT MAX(created_at) FROM reports WHERE reporter_id = ?", (reporter_id,)).fetchone()
        return row[0] or 0

    def first_time(self, event: str) -> bool:
        """True once per event key: GitHub's Redeliver doesn't post twice."""
        with self.db:
            return self.db.execute("INSERT OR IGNORE INTO posted VALUES (?)", (event,)).rowcount == 1


def issue_body(kind: str, details: str) -> str:
    """What the team reads on GitHub. Nothing in it says who the reporter is: the bot keeps that."""
    return (f"{details.strip()}\n\n---\nA {kind} report from Discord. To answer the reporter, start a comment with "
            "`To reporter:`; the bot posts the rest in their private thread. Other comments stay here.")


def reply_text(body: str, prefix: str) -> str | None:
    """The part of a comment meant for the reporter, or None when the comment is for the team only."""
    text = (body or "").strip()
    if not text.lower().startswith(prefix):
        return None
    return text[len(prefix):].strip()[:1800] or None


class Reports:
    def __init__(self, client: discord.Client, settings, github: GitHub, store: Store):
        self.client = client
        self.s = settings
        self.github = github
        self.store = store
        self.queue: asyncio.Queue = asyncio.Queue()

    def wait_left(self, reporter_id: int, now: float | None = None) -> int:
        """Minutes until this person may file another report (0: now)."""
        since = (now or time.time()) - self.store.last_report_by(reporter_id)
        return max(0, int((self.s.report_cooldown_minutes * 60 - since + 59) // 60))

    async def file(self, user, kind: str, title: str, details: str) -> str:
        """Files one report; returns what to tell the reporter."""
        wait = self.wait_left(user.id)
        if wait:
            return f"Thanks! You can send another report in {wait} minute{'s' if wait != 1 else ''}."
        try:
            number = await self.github.create_issue(self.s.reports_repo, title.strip()[:120], issue_body(kind, details),
                                                    [kind, "from-discord"])
        except (GitHubError, aiohttp.ClientError, TimeoutError) as e:
            log.warning("report: GitHub refused the issue: %s", e)
            return "Sorry, I couldn't file that just now. Please try again in a few minutes."
        log.info("report: filed issue %d", number)
        try:
            channel = await self.client.fetch_channel(self.s.reports_channel_id)
            thread = await channel.create_thread(name=f"#{number} {title}"[:100], type=discord.ChannelType.private_thread,
                                                 invitable=False, auto_archive_duration=10080)
            try:
                await thread.add_user(discord.Object(id=user.id))
            except discord.HTTPException as e:
                log.warning("report %d: could not add the reporter to the thread: %s", number, e)
            await thread.send(f"<@{user.id}> thank you! The team has your report (number {number}):\n> **{title.strip()[:120]}**\n"
                              "Their answers will appear here.", allowed_mentions=discord.AllowedMentions(users=[discord.Object(id=user.id)]))
        except discord.HTTPException as e:
            log.warning("report %d: no thread: %s", number, e)
            self.store.add(number, 0, user.id)
            return f"Thanks! The team has it as report {number}."
        self.store.add(number, thread.id, user.id)
        return f"Thanks! The team has it as report {number}, and their answers will appear in <#{thread.id}>."

    async def on_github(self, event: str, payload: dict) -> tuple[int, str]:
        """An issue_comment or issues event: (HTTP status, text). Posting happens from the queue, after GitHub has its answer."""
        repo = (payload.get("repository") or {}).get("full_name", "").lower()
        issue = payload.get("issue") or {}
        if repo != self.s.reports_repo or "pull_request" in issue:
            return 202, "ignored"
        found = self.store.get(issue.get("number", 0))
        if not found or not found[0]:
            return 202, "not a report from Discord"
        if event == "issue_comment" and payload.get("action") == "created":
            comment = payload.get("comment") or {}
            if (comment.get("user") or {}).get("type") == "Bot":
                return 202, "ignored"
            text = reply_text(comment.get("body", ""), self.s.report_reply_prefix)
            if text is None:
                return 202, "for the team only"
            key, message = f"comment:{comment.get('id')}", f"**The team:** {text}"
        elif event == "issues" and payload.get("action") in ("closed", "reopened"):
            if payload["action"] == "reopened":
                message = "The team has opened this report again."
            elif issue.get("state_reason") == "not_planned":
                message = "The team has closed this report without a change. Thank you for sending it."
            else:
                message = "The team has finished with this report. Thank you for sending it!"
            key = f"{payload['action']}:{issue.get('number')}:{issue.get('updated_at')}"
        else:
            return 202, "ignored"
        if not self.store.first_time(key):
            return 202, "already posted"
        self.queue.put_nowait((found[0], found[1], message))
        return 200, "queued"

    async def send(self, thread_id: int, reporter_id: int, message: str) -> None:
        # An archived thread opens again by itself when the bot posts in it (tested), so a late answer still arrives.
        thread = self.client.get_partial_messageable(thread_id, type=discord.ChannelType.private_thread)
        await thread.send(f"<@{reporter_id}> {message}", allowed_mentions=discord.AllowedMentions(users=[discord.Object(id=reporter_id)]))

    async def run(self) -> None:
        while True:
            thread_id, reporter_id, message = await self.queue.get()
            for attempt in range(3):
                try:
                    await self.send(thread_id, reporter_id, message)
                    log.info("report: posted in thread %s", thread_id)
                    break
                except discord.HTTPException as e:
                    log.warning("report: posting in %s failed (%s), attempt %d", thread_id, e, attempt + 1)
                    await asyncio.sleep(5 * (attempt + 1))


class ReportModal(discord.ui.Modal):
    what = discord.ui.TextInput(label="In a few words", max_length=90, placeholder="The ferry never leaves the docks")
    details = discord.ui.TextInput(label="What happened, and where?", style=discord.TextStyle.paragraph, max_length=1500,
                                   placeholder="What you did, what you expected, what happened instead. Your character's name helps.")

    def __init__(self, reports: Reports, kind: str):
        super().__init__(title="Report a problem" if kind == "bug" else "Share an idea")
        self.reports = reports
        self.kind = kind

    async def on_submit(self, interaction: discord.Interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        text = await self.reports.file(interaction.user, self.kind, str(self.what.value), str(self.details.value))
        await interaction.followup.send(text, ephemeral=True)


def add_report_command(bot) -> None:
    @bot.tree.command(name="report", description="Tell the team about a problem, or share an idea")
    @app_commands.describe(kind="A problem, or an idea")
    @app_commands.choices(kind=[app_commands.Choice(name=v, value=k) for k, v in KINDS.items()])
    async def report_command(interaction: discord.Interaction, kind: app_commands.Choice[str]):
        await interaction.response.send_modal(ReportModal(bot.reports, kind.value))
