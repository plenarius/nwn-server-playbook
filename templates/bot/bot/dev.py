"""/dev: builders load a pull request's build onto the dev server, roll it back, and ask what it runs (chapter 14, tier 3).

The bot only asks the operations API (POST /api/v1/dev/load), which starts the module repository's dev load workflow; the bot then
watches GET /api/v1/dev/status until that run ends and says how it went. Off until DEV_ROLE_ID is set."""
import asyncio
import logging
from datetime import datetime

import discord
from discord import app_commands

from .controls import is_staff
from .ops_api import OpsApiError

log = logging.getLogger("bot.dev")

POLL_SECONDS = 15
# Discord lets a bot answer an interaction for 15 minutes, so it waits a little less (the workflow stops at 12).
WAIT_MINUTES = 14
# asyncio keeps only a weak reference to a task; these are the loads being watched.
_watching: set = set()


def status_line(answer: dict) -> str:
    """One line: which build and commit, which content, healthy or not. The same words for /dev status and after a load."""
    loaded = answer.get("loaded") or {}
    if not loaded.get("label"):
        text = "The dev server has nothing loaded yet."
    else:
        text = f"Dev runs **{loaded['label']}**"
        if loaded.get("commit"):
            text += f" (commit `{loaded['commit']}`)"
        content = loaded.get("content")
        haks = loaded.get("dev_haks") or []
        if content:
            text += f", content `{content[:12]}`" + (f" with dev haks {', '.join(haks)}" if haks else " (the live haks)")
        else:
            text += ", the live content"
        text += f", {loaded.get('health') or 'health unknown'}."
    run = answer.get("last_run")
    if run:
        how = run.get("conclusion") or run.get("status")
        text += f"\nLast load: {run.get('title', '?')}, {how} (<{run.get('url')}>)"
    return text


def _created(run: dict) -> float:
    try:
        return datetime.fromisoformat(run["created_at"].replace("Z", "+00:00")).timestamp()
    except (KeyError, ValueError, AttributeError):
        return 0.0


async def wait_for_run(api, since: float, sleep=asyncio.sleep, polls: int = WAIT_MINUTES * 60 // POLL_SECONDS) -> dict | None:
    """The status once the run started at or after `since` has finished; None if it hasn't within WAIT_MINUTES."""
    for _ in range(polls):
        await sleep(POLL_SECONDS)
        try:
            answer = await api.dev_status()
        except OpsApiError:
            continue
        run = answer.get("last_run") or {}
        if _created(run) >= since - 5 and run.get("status") == "completed":
            return answer
    return None


async def load(api, who: str, target: str, report, sleep=asyncio.sleep) -> str:
    """Start a load; `report(text)` gets the outcome when the run ends. Returns the first answer, at once."""
    try:
        answer = await api.dev_load(target, who)
    except OpsApiError as e:
        return f"Not loaded: {e.message}"
    since = datetime.fromisoformat(answer.get("requested_at", "1970-01-01T00:00:00+00:00")).timestamp()
    log.info("dev load %s by %s", target, who)

    async def follow():
        done = await wait_for_run(api, since, sleep)
        if done is None:
            return await report(f"The load of {target} is still going after {WAIT_MINUTES} minutes; look at the workflow on GitHub.")
        ok = (done.get("last_run") or {}).get("conclusion") == "success"
        await report(("Loaded. " if ok else f"The load of {target} failed; the dev server keeps what it had. ") + status_line(done))

    task = asyncio.get_running_loop().create_task(follow())
    _watching.add(task)
    task.add_done_callback(_watching.discard)
    return f"Loading {target} onto the dev server for {who}. I'll say here when it's done (a minute or two)."


def can_load(member, s) -> bool:
    return is_staff(member, s.dev_role_id) or is_staff(member, s.staff_role_id)


def add_dev_commands(bot) -> None:
    group = app_commands.Group(name="dev", description="The dev server")

    async def start(interaction: discord.Interaction, target: str):
        if not can_load(interaction.user, bot.s):
            return await interaction.response.send_message("Only builders can load the dev server.", ephemeral=True)
        await interaction.response.defer(thinking=True)

        async def report(text):
            await interaction.followup.send(text)

        await interaction.followup.send(await load(bot.api, interaction.user.display_name, target, report))

    @group.command(name="load", description="Load a pull request's build onto the dev server")
    @app_commands.describe(pr="The pull request's number")
    async def load_command(interaction: discord.Interaction, pr: app_commands.Range[int, 1, 9999999]):
        await start(interaction, f"pr-{pr}")

    @group.command(name="main", description="Load main's newest build onto the dev server")
    async def main_command(interaction: discord.Interaction):
        await start(interaction, "main")

    @group.command(name="rollback", description="Put the build before back on the dev server")
    async def rollback_command(interaction: discord.Interaction):
        await start(interaction, "rollback")

    @group.command(name="status", description="What the dev server runs")
    async def status_command(interaction: discord.Interaction):
        await interaction.response.defer(ephemeral=True, thinking=True)
        try:
            text = status_line(await bot.api.dev_status())
        except OpsApiError as e:
            text = f"Can't tell right now: {e.message}"
        await interaction.followup.send(text, ephemeral=True)

    bot.tree.add_command(group)
