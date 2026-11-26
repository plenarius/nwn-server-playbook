"""Restart and cancel, as buttons under the dashboard and as slash commands, for members with the staff role."""
import logging

import discord
from discord import app_commands

from .ops_api import OpsApi, OpsApiError

log = logging.getLogger("bot.controls")


def is_staff(member, staff_role_id: int) -> bool:
    return any(role.id == staff_role_id for role in getattr(member, "roles", []))


async def restart(api: OpsApi, who: str, minutes: int, reason: str) -> str:
    minutes = max(1, min(minutes, 30))
    try:
        answer = await api.restart(minutes, f"{reason} ({who})" if reason else f"restart by {who}")
    except OpsApiError as e:
        return f"Restart refused: {e.message}"
    log.info("restart in %d min by %s", minutes, who)
    return f"Restart in {minutes} minute{'s' if minutes != 1 else ''}. " + answer.get("message", "")


async def cancel(api: OpsApi, who: str) -> str:
    try:
        answer = await api.cancel_restart()
    except OpsApiError as e:
        return f"Cancel failed: {e.message}"
    log.info("cancel by %s: %s", who, answer.get("message"))
    return answer.get("message", "Cancelled")


class RestartModal(discord.ui.Modal, title="Restart the game"):
    minutes = discord.ui.TextInput(label="Minutes of warning (1 to 30)", default="5", max_length=2)
    reason = discord.ui.TextInput(label="Reason", default="restart", max_length=100, required=False)

    def __init__(self, bot):
        super().__init__()
        self.bot = bot

    async def on_submit(self, interaction: discord.Interaction):
        try:
            minutes = int(str(self.minutes.value))
        except ValueError:
            return await interaction.response.send_message("Minutes must be a number.", ephemeral=True)
        await interaction.response.defer(ephemeral=True, thinking=True)
        text = await restart(self.bot.api, interaction.user.display_name, minutes, str(self.reason.value))
        await interaction.followup.send(text, ephemeral=True)
        await self.bot.dashboard.refresh()


class DashboardView(discord.ui.View):
    """The buttons. timeout=None and fixed custom_ids make them persistent: they still work after the bot restarts."""

    def __init__(self, bot):
        super().__init__(timeout=None)
        self.bot = bot

    async def interaction_check(self, interaction: discord.Interaction) -> bool:
        if is_staff(interaction.user, self.bot.s.staff_role_id):
            return True
        await interaction.response.send_message("Only staff can do that.", ephemeral=True)
        return False

    @discord.ui.button(label="Restart", style=discord.ButtonStyle.primary, custom_id="dashboard:restart")
    async def restart_button(self, interaction: discord.Interaction, button: discord.ui.Button):
        await interaction.response.send_modal(RestartModal(self.bot))

    @discord.ui.button(label="Cancel restart", style=discord.ButtonStyle.secondary, custom_id="dashboard:cancel")
    async def cancel_button(self, interaction: discord.Interaction, button: discord.ui.Button):
        await interaction.response.defer(ephemeral=True, thinking=True)
        await interaction.followup.send(await cancel(self.bot.api, interaction.user.display_name), ephemeral=True)
        await self.bot.dashboard.refresh()


def add_commands(bot) -> None:
    """/restart and /cancel-restart. Discord shows them to everyone; the staff check is here, in the bot."""

    @bot.tree.command(name="restart", description="Restart the game after a countdown")
    @app_commands.describe(minutes="Minutes of warning, 1 to 30", reason="Why, shown to players")
    async def restart_command(interaction: discord.Interaction, minutes: app_commands.Range[int, 1, 30] = 5,
                              reason: str = "restart"):
        if not is_staff(interaction.user, bot.s.staff_role_id):
            return await interaction.response.send_message("Only staff can do that.", ephemeral=True)
        await interaction.response.defer(ephemeral=True, thinking=True)
        await interaction.followup.send(await restart(bot.api, interaction.user.display_name, minutes, reason), ephemeral=True)
        await bot.dashboard.refresh()

    @bot.tree.command(name="cancel-restart", description="Cancel a pending restart")
    async def cancel_command(interaction: discord.Interaction):
        if not is_staff(interaction.user, bot.s.staff_role_id):
            return await interaction.response.send_message("Only staff can do that.", ephemeral=True)
        await interaction.response.defer(ephemeral=True, thinking=True)
        await interaction.followup.send(await cancel(bot.api, interaction.user.display_name), ephemeral=True)
        await bot.dashboard.refresh()
