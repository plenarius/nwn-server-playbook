import asyncio
from types import SimpleNamespace

import discord

from bot import dev
from bot.ops_api import OpsApiError
from tests.fakes import interaction

LOADED = {"label": "pr-12-3f9c2ab", "commit": "3f9c2ab", "content": "c0fb1843a53c26ec684e72601f82352626279d88",
          "dev_haks": ["newarea"], "health": "healthy"}


def run(status, conclusion=None, created="2026-11-26T20:00:10Z"):
    return {"title": "dev load pr-12 for Mira", "status": status, "conclusion": conclusion, "created_at": created,
            "url": "https://github.com/you/mymodule/actions/runs/7"}


class DevApi:
    """The operations API's two dev routes: a load starts a run that is queued, then in progress, then done."""

    def __init__(self, conclusion="success", refuse=None):
        self.calls, self.polls = [], 0
        self.conclusion, self.refuse = conclusion, refuse

    async def dev_load(self, target, who):
        self.calls.append(("load", target, who))
        if self.refuse:
            raise OpsApiError(409, self.refuse)
        return {"ok": True, "target": target, "requested_at": "2026-11-26T20:00:08+00:00"}

    async def dev_status(self):
        self.polls += 1
        if self.polls == 1:  # the run before this one: finished, but older than the request
            return {"loaded": {"label": "main-bfc572a"}, "last_run": run("completed", "success", "2026-11-26T19:00:00Z")}
        if self.polls == 2:
            return {"loaded": {"label": "main-bfc572a"}, "last_run": run("in_progress")}
        return {"loaded": LOADED, "last_run": run("completed", self.conclusion)}


async def no_sleep(_):
    await asyncio.sleep(0)


def test_status_line():
    line = dev.status_line({"loaded": LOADED, "last_run": run("completed", "success")})
    assert line.startswith("Dev runs **pr-12-3f9c2ab** (commit `3f9c2ab`), content `c0fb1843a53c` with dev haks newarea, healthy.")
    assert "Last load: dev load pr-12 for Mira, success" in line
    assert dev.status_line({"loaded": None, "last_run": None}) == "The dev server has nothing loaded yet."
    assert ", the live content, healthy." in dev.status_line({"loaded": {"label": "main-bfc572a", "health": "healthy"}})


async def test_load_reports_when_the_run_ends():
    api, said = DevApi(), []

    async def report(text):
        said.append(text)

    first = await dev.load(api, "Mira", "pr-12", report, sleep=no_sleep)
    assert first.startswith("Loading pr-12 onto the dev server for Mira.")
    for _ in range(20):
        await asyncio.sleep(0)
    assert api.calls == [("load", "pr-12", "Mira")]
    assert api.polls == 3  # the older run and the running one were not taken for the answer
    assert said and said[0].startswith("Loaded. Dev runs **pr-12-3f9c2ab**")


async def test_a_failed_load_says_so():
    api, said = DevApi(conclusion="failure"), []

    async def report(text):
        said.append(text)

    await dev.load(api, "Mira", "pr-12", report, sleep=no_sleep)
    for _ in range(20):
        await asyncio.sleep(0)
    assert said[0].startswith("The load of pr-12 failed; the dev server keeps what it had.")


async def test_refusal_is_shown():
    said = []

    async def report(text):
        said.append(text)

    answer = await dev.load(DevApi(refuse="a dev load is already running: dev load main"), "Mira", "main", report)
    assert answer == "Not loaded: a dev load is already running: dev load main"
    assert said == []


async def test_commands_and_roles():
    api = DevApi()
    tree_commands = []
    bot = SimpleNamespace(api=api, s=SimpleNamespace(staff_role_id=42, dev_role_id=77),
                          tree=SimpleNamespace(add_command=tree_commands.append))
    dev.add_dev_commands(bot)
    group = tree_commands[0]
    assert group.name == "dev" and sorted(c.name for c in group.commands) == ["load", "main", "rollback", "status"]
    load_cmd = next(c for c in group.commands if c.name == "load")

    player = interaction("Tam", role_ids=[1])
    await load_cmd.callback(player, 12)
    assert player.response.messages == ["Only builders can load the dev server."] and api.calls == []

    builder = interaction("Mira", role_ids=[77])
    await load_cmd.callback(builder, 12)
    assert api.calls == [("load", "pr-12", "Mira")]
    assert builder.followup.messages[0].startswith("Loading pr-12")

    status_cmd = next(c for c in group.commands if c.name == "status")
    anyone = interaction("Tam", role_ids=[1])
    await status_cmd.callback(anyone)
    assert anyone.followup.messages[0].startswith("Dev runs") or anyone.followup.messages[0].startswith("The dev")
    assert isinstance(group, discord.app_commands.Group)
