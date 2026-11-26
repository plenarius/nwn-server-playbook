from datetime import datetime, timezone

from bot.dashboard import GREEN, GREY, RED, look, render, started_at

NOW = datetime(2026, 11, 26, 16, 0, tzinfo=timezone.utc).timestamp()
UP = {"status": "running:healthy", "players": 3, "module": "mymodule", "nwnx_running": "ed79330", "restart_pending": None}


def fields(embed):
    return {f.name: f.value for f in embed.fields}


def test_online():
    e = render("My server", UP, {"operations": []}, NOW - 3600, now=NOW)
    assert e.colour.value == GREEN
    assert fields(e) == {"Server": "Online", "Players": "3", "Module": "mymodule",
                         "Last restart": f"<t:{int(NOW - 3600)}:R>", "NWNX": "ed79330"}


def test_offline_has_no_last_restart():
    e = render("My server", dict(UP, status="exited", players=0), {}, None, now=NOW)
    assert e.colour.value == RED
    assert fields(e)["Server"] == "Offline" and fields(e)["Players"] == "-" and "Last restart" not in fields(e)


def test_api_unreachable():
    e = render("My server", None, None, None, "the operations API did not answer", now=NOW)
    assert e.colour.value == GREY and "did not answer" in e.description


def test_countdown_and_operations():
    pending = {"reason": "update", "restart_at": "2026-11-26T16:05:00+00:00"}
    e = render("S", dict(UP, restart_pending=pending), {}, None, now=NOW)
    assert fields(e)["Restart"].startswith("<t:")
    e = render("S", UP, {"operations": ["restart"]}, None, now=NOW)
    assert fields(e)["In progress"] == "restart"


def test_look():
    assert look("running:starting")[0] == "Starting"
    assert look(None) == ("Not found", GREY)


def test_started_at():
    p = {"markers": {"module": "[Thu Nov 26 15:57:24] Loading Module: mymodule"}}
    assert started_at(p, NOW) == datetime(2026, 11, 26, 15, 57, 24, tzinfo=timezone.utc).timestamp()
    jan = datetime(2027, 1, 1, 0, 5, tzinfo=timezone.utc).timestamp()
    assert datetime.fromtimestamp(started_at({"markers": {"module": "[Thu Dec 31 23:59:00] Loading Module: m"}}, jan),
                                  tz=timezone.utc).year == 2026
    assert started_at({"markers": {"module": None}}) is None
