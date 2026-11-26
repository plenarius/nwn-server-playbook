import hashlib
import hmac
import json
from types import SimpleNamespace

from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer

from bot.changelog import Changelog, embed_for, entry, signature_ok

SECRET = "a-test-secret-of-some-length"


def merged(number=12, labels=(), repo="you/mymodule", merged=True, action="closed"):
    return {"action": action, "repository": {"full_name": repo},
            "pull_request": {"number": number, "merged": merged, "title": "Fix the ferry", "html_url": f"https://github.com/{repo}/pull/{number}",
                             "user": {"login": "mira"}, "labels": [{"name": n} for n in labels]}}


def sign(body: bytes, secret=SECRET):
    return "sha256=" + hmac.new(secret.encode(), body, hashlib.sha256).hexdigest()


def test_signature():
    body = b'{"a": 1}'
    assert signature_ok(SECRET, body, sign(body))
    assert not signature_ok(SECRET, body, sign(body, "another-secret"))
    assert not signature_ok(SECRET, body + b" ", sign(body))
    assert not signature_ok(SECRET, body, "")
    assert not signature_ok("", body, sign(body, ""))


def test_entry():
    assert entry(merged())["key"] == "you/mymodule#12"
    assert entry(merged(merged=False)) is None
    assert entry(merged(action="opened")) is None
    assert entry(merged(labels=["no-changelog"]), skip_label="no-changelog") is None
    assert entry(merged(repo="you/other"), repos=("you/mymodule",)) is None
    assert entry(merged(labels=["bug"]), skip_label="no-changelog")["labels"] == ["bug"]
    e = embed_for(entry(merged(labels=["bug"])))
    assert e.title == "mymodule #12: Fix the ferry" and e.footer.text == "by mira · bug"


async def client():
    settings = SimpleNamespace(webhook_secret=SECRET, changelog_repos=(), changelog_skip_label="no-changelog", changelog_channel_id=1)
    cl = Changelog(None, settings)
    app = web.Application()
    cl.routes(app)
    c = TestClient(TestServer(app))
    await c.start_server()
    return cl, c


async def post(c, event, payload, signature=None):
    body = json.dumps(payload).encode()
    return await c.post("/github", data=body, headers={"X-GitHub-Event": event, "X-Hub-Signature-256": signature or sign(body)})


async def test_receiver():
    cl, c = await client()
    try:
        r = await post(c, "pull_request", merged(), signature="sha256=" + "0" * 64)
        assert r.status == 401 and cl.queue.empty()
        r = await post(c, "ping", {"zen": "hi", "repository": {"full_name": "you/mymodule"}})
        assert (r.status, await r.text()) == (200, "pong")
        r = await post(c, "pull_request", merged(merged=False))
        assert r.status == 202 and cl.queue.empty()
        r = await post(c, "pull_request", merged())
        assert (r.status, await r.text()) == (200, "queued") and cl.queue.qsize() == 1
        r = await post(c, "pull_request", merged())  # GitHub's "Redeliver"
        assert (r.status, await r.text()) == (202, "already posted") and cl.queue.qsize() == 1
    finally:
        await c.close()
