from types import SimpleNamespace

from bot.reports import ReportModal, Reports, Store, issue_body, reply_text
from tests.fakes import FakeThread, FakeClient, interaction

REPO = "you/reports"


class FakeGitHub:
    def __init__(self):
        self.issues = []

    async def create_issue(self, repo, title, body, labels):
        self.issues.append((repo, title, body, labels))
        return 40 + len(self.issues)


def reports(tmp_path, cooldown=10):
    s = SimpleNamespace(reports_repo=REPO, reports_channel_id=5, report_reply_prefix="to reporter:", report_cooldown_minutes=cooldown)
    client = FakeClient()
    return Reports(client, s, FakeGitHub(), Store(str(tmp_path / "reports.db"))), client


async def submit(r, user_id=7001, kind="bug"):
    modal = ReportModal(r, kind)
    modal.what._value, modal.details._value = "The ferry never leaves", "At the docks, since this morning. My character is Mira."
    i = interaction("Mira", user_id=user_id)
    await modal.on_submit(i)
    return i


async def test_a_report_files_an_issue_and_a_private_thread(tmp_path):
    r, client = reports(tmp_path)
    i = await submit(r)
    repo, title, body, labels = r.github.issues[0]
    assert (repo, title, labels) == (REPO, "The ferry never leaves", ["bug", "from-discord"])
    assert "7001" not in body and "Mira" in body  # what they wrote, but not who they are on Discord
    thread = client.channel.threads[0]
    assert thread.private and thread.name == "#41 The ferry never leaves" and thread.members == [7001]
    assert thread.sent[0][0].startswith("<@7001> thank you!") and thread.sent[0][1] == [7001]  # only the reporter is pinged
    assert r.store.get(41) == (thread.id, 7001)
    assert i.followup.messages == [f"Thanks! The team has it as report 41, and their answers will appear in <#{thread.id}>."]


async def test_one_report_per_cooldown(tmp_path):
    r, _ = reports(tmp_path)
    await submit(r)
    i = await submit(r)
    assert i.followup.messages[0].startswith("Thanks! You can send another report in 10 minutes")
    assert len(r.github.issues) == 1
    await submit(r, user_id=7002)  # someone else may
    assert len(r.github.issues) == 2


def comment(body, number=41, cid=900, kind="User", repo=REPO):
    return {"action": "created", "repository": {"full_name": repo}, "issue": {"number": number},
            "comment": {"id": cid, "body": body, "user": {"type": kind}}}


async def test_comments_for_the_reporter_reach_the_thread(tmp_path):
    r, client = reports(tmp_path)
    await submit(r)
    thread_id = client.channel.threads[0].id
    assert await r.on_github("issue_comment", comment("Looks like the ferry script. @everyone")) == (202, "for the team only")
    assert await r.on_github("issue_comment", comment("To reporter: found it, a fix is on its way", cid=901)) == (200, "queued")
    assert await r.on_github("issue_comment", comment("To reporter: found it, a fix is on its way", cid=901)) == (202, "already posted")
    assert await r.on_github("issue_comment", comment("To reporter: hi", number=99, cid=902)) == (202, "not a report from Discord")
    assert await r.on_github("issue_comment", comment("To reporter: hi", repo="you/other", cid=903)) == (202, "ignored")
    assert await r.on_github("issue_comment", comment("To reporter: hi", kind="Bot", cid=904)) == (202, "ignored")
    closed = {"action": "closed", "repository": {"full_name": REPO}, "issue": {"number": 41, "state_reason": "completed", "updated_at": "t"}}
    assert await r.on_github("issues", closed) == (200, "queued")
    assert r.queue.qsize() == 2
    thread, reporter, text = r.queue.get_nowait()
    assert (thread, reporter, text) == (thread_id, 7001, "**The team:** found it, a fix is on its way")
    await r.send(thread, reporter, text)
    assert client.partials[thread_id].sent == [("<@7001> **The team:** found it, a fix is on its way", [7001])]


def test_reply_text():
    assert reply_text("To reporter: thanks!", "to reporter:") == "thanks!"
    assert reply_text("to REPORTER:   x", "to reporter:") == "x"
    assert reply_text("To reporter:", "to reporter:") is None
    assert reply_text("internal note", "to reporter:") is None
    assert "To reporter:" in issue_body("bug", "x")
