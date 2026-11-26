from types import SimpleNamespace
from datetime import datetime, timezone

from bot.dashboard import GREEN, GREY, RED, Dashboard, look, render, started_at

NOW = datetime(2026, 11, 26, 16, 0, tzinfo=timezone.utc).timestamp()
UP = {"status": "running:healthy", "players": 3, "module": "mymodule", "nwnx_running": "ed79330", "restart_pending": None,
      "started_at": "2026-11-26T15:00:00+00:00"}


def fields(embed):
    return {f.name: f.value for f in embed.fields}


def test_online():
    e = render("My server", UP, {"operations": []}, now=NOW)
    assert e.colour.value == GREEN
    assert fields(e) == {"Server": "Online", "Players": "3", "Module": "mymodule",
                         "Last restart": f"<t:{int(NOW - 3600)}:R>", "NWNX": "ed79330"}


def test_started_at_unknown():
    e = render("My server", dict(UP, started_at=None), {}, now=NOW)
    assert fields(e)["Last restart"] == "unknown"


def test_offline_has_no_last_restart():
    e = render("My server", dict(UP, status="exited", players=0), {}, now=NOW)
    assert e.colour.value == RED
    assert fields(e)["Server"] == "Offline" and fields(e)["Players"] == "-" and "Last restart" not in fields(e)


def test_api_unreachable():
    e = render("My server", None, None, "the operations API did not answer", now=NOW)
    assert e.colour.value == GREY and "did not answer" in e.description


def test_countdown_and_operations():
    pending = {"reason": "update", "restart_at": "2026-11-26T16:05:00+00:00"}
    e = render("S", dict(UP, restart_pending=pending), {}, now=NOW)
    assert fields(e)["Restart"].startswith("<t:")
    e = render("S", UP, {"operations": ["restart"]}, now=NOW)
    assert fields(e)["In progress"] == "restart"


def test_look():
    assert look("running:starting")[0] == "Starting"
    assert look(None) == ("Not found", GREY)


def test_started_at():
    assert started_at({"started_at": "2026-11-26T15:57:24+00:00"}) == datetime(2026, 11, 26, 15, 57, 24,
                                                                               tzinfo=timezone.utc).timestamp()
    assert started_at({"started_at": "2026-11-26T15:57:24Z"}) == started_at({"started_at": "2026-11-26T15:57:24+00:00"})
    assert started_at({"started_at": None}) is None
    assert started_at({}) is None and started_at(None) is None
    assert started_at({"started_at": "soon"}) is None


async def test_build_reads_started_at_from_status(tmp_path):
    class Api:
        async def status(self):
            return UP

        async def progress(self):
            return {"operations": []}

    settings = SimpleNamespace(data_dir=str(tmp_path), server_name="S", dashboard_channel_id=1)
    e = await Dashboard(None, Api(), settings).build()
    assert fields(e)["Last restart"] == f"<t:{int(NOW - 3600)}:R>"
