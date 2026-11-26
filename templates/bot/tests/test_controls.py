import pytest

from bot.controls import DashboardView, RestartModal, is_staff
from bot.ops_api import OpsApiError
from tests.fakes import FakeApi, bot, interaction


def button(view, custom_id):
    return next(item for item in view.children if getattr(item, "custom_id", None) == custom_id)


def test_is_staff():
    assert is_staff(interaction(role_ids=[1, 42]).user, 42)
    assert not is_staff(interaction(role_ids=[1]).user, 42)


async def test_non_staff_is_turned_away():
    api = FakeApi()
    view = DashboardView(bot(api))
    i = interaction(role_ids=[7])
    assert await view.interaction_check(i) is False
    assert i.response.messages == ["Only staff can do that."]
    assert api.calls == []


async def test_restart_button_asks_then_restarts():
    api = FakeApi()
    b = bot(api)
    view = DashboardView(b)
    i = interaction("Mira", role_ids=[42])
    assert await view.interaction_check(i)
    await button(view, "dashboard:restart").callback(i)
    modal = i.response.modal
    assert isinstance(modal, RestartModal)
    modal.minutes._value, modal.reason._value = "2", "new module"
    submit = interaction("Mira", role_ids=[42])
    await modal.on_submit(submit)
    assert api.calls == [("restart", 2, "new module (Mira)")]
    assert submit.followup.messages[0].startswith("Restart in 2 minutes.")
    assert b.dashboard.refreshed == 1


async def test_restart_minutes_are_kept_in_range():
    api = FakeApi()
    modal = RestartModal(bot(api))
    modal.minutes._value, modal.reason._value = "99", ""
    await modal.on_submit(interaction("Mira", role_ids=[42]))
    assert api.calls == [("restart", 30, "restart by Mira")]


async def test_cancel_button():
    api = FakeApi()
    view = DashboardView(bot(api))
    i = interaction("Mira", role_ids=[42])
    await button(view, "dashboard:cancel").callback(i)
    assert api.calls == [("cancel",)]
    assert i.followup.messages == ["Restart cancelled"]


async def test_api_refusal_is_shown():
    class Busy(FakeApi):
        async def restart(self, minutes, reason):
            raise OpsApiError(409, "A restart or deploy is already in progress")
    modal = RestartModal(bot(Busy()))
    modal.minutes._value, modal.reason._value = "5", "x"
    i = interaction("Mira", role_ids=[42])
    await modal.on_submit(i)
    assert i.followup.messages == ["Restart refused: A restart or deploy is already in progress"]
