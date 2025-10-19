import uvicorn
import aiohttp
import os
#added imports Request, Response, HTTPException, Any for auth headers, status passthrough, and body fields - Max
from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from typing import cast, Any
from pathlib import Path

DISCORD_TOKEN_URL = "https://discord.com/api/oauth2/token"

_ = load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    async with aiohttp.ClientSession() as session:
        app.state.aiohttp_session = session
        yield


app = FastAPI(lifespan=lifespan)


def _compute_redirect_uri(request: Request):  # compute fallback redirect_uri from env or proxy headers - Max
    explicit = os.environ.get("DISCORD_REDIRECT_URI", "").strip()
    if explicit:
        return explicit.rstrip("/")
    host = request.headers.get("x-forwarded-host") or request.headers.get("host")
    if not host:
        return None
    proto = request.headers.get("x-forwarded-proto") or "https"
    return f"{proto}://{host}"


@app.get("/nuts")
async def test():
    return {"message": "nuts"}


@app.get("/api/client-id")
async def send_client_id(request: Request):  # accept Request so we can compute redirect_uri - Max
    return {
        "client_id": os.environ["DISCORD_CLIENT_ID"],
        "redirect_uri": _compute_redirect_uri(request),  # include redirect_uri for authorize() fallback - Max
    }


@app.post("/api/authenticate")
async def authenticate_client(request: Request, code_payload: dict[str, Any], response: Response):  # loosen body typing; capture Response - Max
    auth_code = code_payload["code"]
    payload = {
        "client_id": os.environ["DISCORD_CLIENT_ID"],
        "client_secret": os.environ["DISCORD_CLIENT_SECRET"],
        "grant_type": "authorization_code",
        "code": auth_code,
    }

    use_redirect = bool(code_payload.get("use_redirect_uri"))  # accept boolean from client - Max
    if use_redirect:
        redirect_uri = _compute_redirect_uri(request)  # compute redirect on demand - Max
        if redirect_uri:
            payload["redirect_uri"] = redirect_uri  # send redirect_uri only when used - Max

    headers = {"Content-Type": "application/x-www-form-urlencoded"}

    async with app.state.aiohttp_session.post(  # reuse lifespan session instead of creating a new one - Max
        DISCORD_TOKEN_URL, data=payload, headers=headers
    ) as resp:
        response.status_code = resp.status  # pass Discord status through to client - Max
        response_data = cast(dict[str, str], await resp.json())
        return response_data


def _bearer_from(request: Request) -> str:  # helper to extract Bearer token or 401 - Max
    auth = request.headers.get("authorization") or ""
    if not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")
    return auth.split(" ", 1)[1].strip()

# Minimal additions - Max

@app.get("/api/me")
async def me(request: Request, response: Response):  # proxy to Discord users/@me - Max
    token = _bearer_from(request)
    async with app.state.aiohttp_session.get(
        "https://discord.com/api/users/@me",
        headers={"Authorization": f"Bearer {token}"}  # forward bearer token - Max
    ) as resp:
        response.status_code = resp.status  # surface upstream status - Max
        return await resp.json()


@app.get("/api/guilds")
async def guilds(request: Request, response: Response):  # proxy to Discord users/@me/guilds - Max
    token = _bearer_from(request)
    async with app.state.aiohttp_session.get(
        "https://discord.com/api/users/@me/guilds",
        headers={"Authorization": f"Bearer {token}"}  # forward bearer token - Max
    ) as resp:
        response.status_code = resp.status  # surface upstream status - Max
        return await resp.json()

# Minimal additions end - Max

app.mount("/", StaticFiles(directory=Path("../client/dist"), html=True), name="static")

if __name__ == "__main__":
    # set reload=False for production
    uvicorn.run(app, host="127.0.0.1", port=8001, reload=True)
