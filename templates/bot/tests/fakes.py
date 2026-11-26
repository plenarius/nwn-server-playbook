"""Stand-ins for Discord interactions and the operations API, so the buttons and commands run without Discord."""
from types import SimpleNamespace


class FakeResponse:
    def __init__(self):
        self.messages, self.modal, self.deferred = [], None, False

    async def send_message(self, text, ephemeral=False):
        self.messages.append(text)

    async def send_modal(self, modal):
        self.modal = modal

    async def defer(self, ephemeral=False, thinking=False):
        self.deferred = True


class FakeFollowup:
    def __init__(self):
        self.messages = []

    async def send(self, text, ephemeral=False):
        self.messages.append(text)


def interaction(name="Someone", role_ids=(), user_id=1):
    user = SimpleNamespace(id=user_id, display_name=name, roles=[SimpleNamespace(id=r) for r in role_ids])
    return SimpleNamespace(user=user, response=FakeResponse(), followup=FakeFollowup())


class FakeApi:
    def __init__(self):
        self.calls = []

    async def restart(self, minutes, reason):
        self.calls.append(("restart", minutes, reason))
        return {"ok": True, "message": f"Restart countdown started ({minutes * 60}s)"}

    async def cancel_restart(self):
        self.calls.append(("cancel",))
        return {"ok": True, "message": "Restart cancelled"}


class FakeDashboard:
    def __init__(self):
        self.refreshed = 0

    async def refresh(self):
        self.refreshed += 1


def bot(api, staff_role_id=42):
    return SimpleNamespace(api=api, s=SimpleNamespace(staff_role_id=staff_role_id), dashboard=FakeDashboard())


class FakeThread:
    _next = 9000

    def __init__(self, id=None, name="", private=True):
        FakeThread._next += 1
        self.id = id or FakeThread._next
        self.name, self.private = name, private
        self.members, self.sent = [], []

    async def add_user(self, user):
        self.members.append(user.id)

    async def send(self, text, allowed_mentions=None):
        users = getattr(allowed_mentions, "users", None)
        self.sent.append((text, [u.id for u in users] if isinstance(users, list) else users))


class FakeChannel:
    def __init__(self):
        self.threads, self.sent = [], []

    async def create_thread(self, name, type=None, invitable=True, auto_archive_duration=None):
        import discord
        t = FakeThread(name=name, private=type == discord.ChannelType.private_thread)
        self.threads.append(t)
        return t

    async def send(self, text=None, embed=None, allowed_mentions=None):
        self.sent.append((text, embed, allowed_mentions))
        return SimpleNamespace(id=len(self.sent))


class FakeClient:
    def __init__(self):
        self.channel = FakeChannel()
        self.partials = {}

    async def fetch_channel(self, channel_id):
        return self.channel

    def get_partial_messageable(self, channel_id, type=None):
        if channel_id not in self.partials:
            self.partials[channel_id] = FakeThread(channel_id)
        return self.partials[channel_id]
