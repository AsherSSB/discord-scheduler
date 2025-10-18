import uvicorn
import aiohttp
import os

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from typing import cast
from pathlib import Path

DISCORD_TOKEN_URL = "https://discord.com/api/oauth2/token"

_ = load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with aiohttp.ClientSession() as session:
        app.state.aiohttp_session = session
        yield


app = FastAPI(lifespan=lifespan)


@app.get("/nuts")
async def test():
    return {"message": "nuts"}


@app.get("/api/client-id")
async def send_client_id():
    return {
        "client_id": os.environ["DISCORD_CLIENT_ID"],
    }


@app.post("/api/authenticate")
async def authenticate_client(auth_code: str):
    payload = {
        "client_id": os.environ["DISCORD_CLIENT_ID"],
        "client_secret": os.environ["DISCORD_CLIENT_SECRET"],
        "grant_type": "authorization_code",
        "code": auth_code,
    }

    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    async with aiohttp.ClientSession() as session:
        async with session.post(
            DISCORD_TOKEN_URL, data=payload, headers=headers
        ) as resp:
            response_data = cast(dict[str, str], await resp.json())
            return response_data


app.mount("/", StaticFiles(directory=Path("../client/dist"), html=True), name="static")

if __name__ == "__main__":
    # set reload=False for production
    uvicorn.run(app, host="127.0.0.1", port=8001, reload=True)
