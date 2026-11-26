from datetime import datetime, timezone

from bot.roster import GREEN, GREY, render

NOW = datetime(2026, 11, 26, 16, 0, tzinfo=timezone.utc).timestamp()


def test_names():
    e = render({"count": 2, "characters": [{"name": "Mira"}, {"name": "Sam @everyone"}]}, now=NOW)
    assert e.title == "Who's online (2)" and e.colour.value == GREEN
    assert e.description == "Mira · Sam @​everyone"


def test_nobody_and_unknown():
    assert render({"count": 0, "characters": []}, now=NOW).description == "Nobody is in the game right now."
    e = render(None, "the operations API did not answer", now=NOW)
    assert e.colour.value == GREY and "Can't tell" in e.description


def test_a_long_roster_is_cut():
    e = render({"count": 400, "characters": [{"name": f"Character number {i}"} for i in range(400)]}, now=NOW)
    assert len(e.description) < 4096 and e.description.endswith("more")
