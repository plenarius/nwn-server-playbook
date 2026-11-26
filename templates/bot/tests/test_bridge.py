import json
from types import SimpleNamespace

from bot.bridge import Bridge, RateLimit, for_discord, for_game, posts_for, speaker_name
from tests.fakes import FakeClient

BRIDGE = 300


def message(content, author_id=11, name="Tam", mentions=(), roles=(), bot=False, channel=BRIDGE, attachments=()):
    channels = {77: SimpleNamespace(name="rules")}
    author = SimpleNamespace(id=author_id, display_name=name, bot=bot)
    msg = SimpleNamespace(content=content, author=author, mentions=list(mentions), role_mentions=list(roles), webhook_id=None,
                          channel=SimpleNamespace(id=channel), guild=SimpleNamespace(get_channel=channels.get), attachments=list(attachments),
                          reactions=[])

    async def add_reaction(emoji):
        msg.reactions.append(emoji)
    msg.add_reaction = add_reaction
    return msg


def test_from_game_no_mention_survives():
    out = for_discord("hi @everyone and @here, <@123> <@&456> *bold* <cA1z>red</c>")
    assert "@everyone" not in out and "@here" not in out and "<@123>" not in out and "<@&456>" not in out
    assert "\\*bold\\*" in out and "<c" not in out and "red" in out


def test_to_game_mentions_become_names():
    m = message("hi <@42> and <@!43>, see <#77> <:wave:999> <@&5> @everyone\nsecond line <cA1z>x</c>",
                mentions=[SimpleNamespace(id=42, display_name="Mira", name="m"), SimpleNamespace(id=43, display_name="Sam", name="s")],
                roles=[SimpleNamespace(id=5, name="Staff")])
    assert for_game(m) == "hi @Mira and @Sam, see #rules :wave: @Staff everyone second line x"
    assert for_game(message("look", attachments=[1])) == "look [picture]"
    assert len(for_game(message("x" * 1000))) == 300
    assert speaker_name(SimpleNamespace(display_name="<cA1z>Tam</c>  the   Bold")) == "Tam the Bold"


def test_rate_limit():
    rl = RateLimit(count=2, seconds=10, total=3)
    assert rl.allow("a", 0) and rl.allow("a", 1) and not rl.allow("a", 2)
    assert rl.allow("b", 2) and not rl.allow("c", 3)  # everyone together: 3
    assert rl.allow("a", 11)  # the window moved on


def test_posts_are_split_on_lines():
    rows = [(i, "Mira", "x" * 500) for i in range(10)]
    posts = posts_for(rows)
    assert all(len(p) <= 1900 for p in posts) and sum(p.count("**Mira**") for p in posts) == 10


class FakePool:
    """Answers the bridge's three queries like the game's database would."""

    def __init__(self, rows=()):
        self.rows, self.jobs = list(rows), []
        pool = self

        class Cursor:
            async def __aenter__(self): return self
            async def __aexit__(self, *a): return False

            async def execute(self, sql, args=()):
                if sql.startswith("INSERT INTO work_queue"):
                    pool.jobs.append(args[0])
                    self.result = []
                elif "MAX(id)" in sql:
                    self.result = [(max((r[0] for r in pool.rows), default=0),)]
                else:
                    self.result = [r for r in pool.rows if r[0] > args[0]]

            async def fetchall(self): return self.result

        class Conn:
            async def __aenter__(self): return self
            async def __aexit__(self, *a): return False
            def cursor(self): return Cursor()
        self._conn = Conn()

    def acquire(self):
        return self._conn


def bridge(tmp_path, pool):
    s = SimpleNamespace(bridge_channel_id=BRIDGE, data_dir=str(tmp_path))
    return Bridge(FakeClient(), s, pool)


async def test_discord_to_game_as_a_job(tmp_path):
    pool = FakePool()
    b = bridge(tmp_path, pool)
    assert await b.on_message(message("hello <@42>", mentions=[SimpleNamespace(id=42, display_name="Mira", name="m")]))
    assert pool.jobs == ["Tam\nhello @Mira"]
    assert not await b.on_message(message("from a bot", bot=True))
    assert not await b.on_message(message("elsewhere", channel=1))
    for i in range(4):
        assert await b.on_message(message(f"line {i}"))
    flood = message("one too many")
    assert not await b.on_message(flood) and flood.reactions == ["⏳"]
    assert len(pool.jobs) == 5


async def test_game_to_discord_from_where_it_left_off(tmp_path):
    pool = FakePool([(1, "Old", "said yesterday")])
    b = bridge(tmp_path, pool)
    assert await b.from_game() == 0  # the first start begins at the newest line
    pool.rows += [(2, "Mira", "the ferry @everyone"), (3, "[DM] Ossian", "hold on")]
    assert await b.from_game() == 2
    text, mentions = b.client.partials[BRIDGE].sent[0]
    assert "said yesterday" not in text and "**Mira**: the ferry @​everyone" in text and "**[DM] Ossian**: hold on" in text
    assert json.load(open(tmp_path / "bridge.json")) == {"last_id": 3}
    again = bridge(tmp_path, pool)  # a restart carries on from the file
    assert await again.from_game() == 0 and again.last_id == 3
