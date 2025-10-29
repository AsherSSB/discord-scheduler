import os
import discord
from discord.ext import commands
import asyncio
from dotenv import load_dotenv
from utils.dataclasses import Member


class Client(commands.Bot):
    def __init__(self):
        super().__init__(command_prefix="!", intents=discord.Intents.all())


class Bot:
    def __init__(self) -> None:
        self._client: Client = Client()
        _ = self._run()

        @self._client.event
        async def on_ready():
            if self._client.user:
                print(self._client.user.name)

    async def get_guild_members(self, guild_id: int) -> list[Member] | None:
        if not (guild := self._client.get_guild(guild_id)):
            return None

        return [
            Member(
                id=member.id,
                name=member.name,
                avatar=(member.avatar.url if member.avatar else ""),
            )
            for member in guild.members
        ]

    def _run(self):
        _ = load_dotenv()
        TOKEN = os.getenv("DISCORD_TOKEN")

        _ = asyncio.create_task(self._client.start(str(TOKEN)))
