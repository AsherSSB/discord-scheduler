from uuid import UUID
from starlette.status import HTTP_404_NOT_FOUND, HTTP_500_INTERNAL_SERVER_ERROR
import uvicorn
import aiohttp
import os

from datetime import time, date
from fastapi import FastAPI, HTTPException
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from typing import cast
from pathlib import Path

from utils.database import Database

DISCORD_TOKEN_URL = "https://discord.com/api/oauth2/token"

_ = load_dotenv()

db = Database()


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with aiohttp.ClientSession() as session:
        app.state.aiohttp_session = session
        yield


app = FastAPI(lifespan=lifespan)


@app.get("/api/client-id")
async def send_client_id():
    return {
        "client_id": os.environ["DISCORD_CLIENT_ID"],
    }


@app.post("/api/authenticate")
async def authenticate_client(code_payload: dict[str, str]):
    auth_code = code_payload["code"]
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


@app.post("/api/user")
async def create_user(user_id: int):
    db.create_user(user_id)
    return {"message": "successfully created user"}


@app.get("/api/poll/{poll_id}")
async def get_poll(poll_id: UUID):
    if not (poll := db.get_poll(poll_id)):
        raise HTTPException(status_code=HTTP_404_NOT_FOUND)
    return poll.model_dump()


@app.post("/api/poll")
async def create_poll(
    name: str,
    creator_id: int,
    start_time: time,
    end_time: time,
    start_date: date,
    end_date: date,
):
    poll_id = db.create_poll(
        name, creator_id, start_time, end_time, start_date, end_date
    )
    if not poll_id:
        raise HTTPException(status_code=HTTP_500_INTERNAL_SERVER_ERROR)

    return {"id": poll_id}


app.mount("/", StaticFiles(directory=Path("../client/dist"), html=True), name="static")

if __name__ == "__main__":
    # set reload=False for production
    uvicorn.run(app, host="127.0.0.1", port=8001, reload=True)
