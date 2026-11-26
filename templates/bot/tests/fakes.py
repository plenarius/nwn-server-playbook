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


def interaction(name="Someone", role_ids=()):
    user = SimpleNamespace(display_name=name, roles=[SimpleNamespace(id=r) for r in role_ids])
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
