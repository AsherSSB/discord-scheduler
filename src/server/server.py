import uvicorn
import httpx
import os

# added imports Request, Response, HTTPException, Any for auth headers, status passthrough, and body fields - Max
from fastapi import FastAPI, Request, Response, HTTPException
from fastapi.staticfiles import StaticFiles
from contextlib import asynccontextmanager
from dotenv import load_dotenv
from typing import cast
from pathlib import Path

_ = load_dotenv()

DISCORD_TOKEN_URL = "https://discord.com/api/oauth2/token"
CLIENT_ID = os.environ.get("DISCORD_CLIENT_ID", "").strip()
CLIENT_SECRET = os.environ.get("DISCORD_CLIENT_SECRET", "").strip()
REDIRECT_URI = os.environ.get("DISCORD_REDIRECT_URI", "")


@asynccontextmanager
async def lifespan(app: FastAPI):
    app.state.http_client = httpx.AsyncClient()
    yield
    await app.state.http_client.aclose()


app = FastAPI(lifespan=lifespan)


def _get_http_client() -> httpx.AsyncClient:
    return cast(httpx.AsyncClient, app.state.http_client)


def _compute_redirect_uri(request: Request):
    if REDIRECT_URI:
        return REDIRECT_URI.rstrip("/")

    # fallback to
    host = request.headers.get("x-forwarded-host") or request.headers.get("host")
    if not host:
        return None
    proto = request.headers.get("x-forwarded-proto") or "https"
    return f"{proto}://{host}"


@app.get("/api/client-id")
async def send_client_id(request: Request):
    return {
        "client_id": CLIENT_ID,
        "redirect_uri": _compute_redirect_uri(request),
    }


@app.post("/api/authenticate")
async def authenticate_client(
    request: Request, code_payload: dict[str, str | bool], response: Response
):
    auth_code = code_payload.get("code")
    payload = {
        "client_id": CLIENT_ID,
        "client_secret": CLIENT_SECRET,
        "grant_type": "authorization_code",
        "code": auth_code,
    }

    if bool(code_payload.get("use_redirect_uri")):
        if redirect_uri := _compute_redirect_uri(request):
            payload["redirect_uri"] = redirect_uri

    headers = {"Content-Type": "application/x-www-form-urlencoded"}
    http_client = _get_http_client()
    resp = await http_client.get(DISCORD_TOKEN_URL, headers=headers)
    response.status_code = resp.status_code
    response_data = cast(dict[str, str], resp.json)
    return response_data


def _bearer_from(
    request: Request,
) -> str:
    auth = request.headers.get("authorization") or ""

    if not auth.lower().startswith("bearer "):
        raise HTTPException(status_code=401, detail="Missing bearer token")

    return auth.split(" ", 1)[1].strip()


@app.get("/api/me")
async def me(request: Request, response: Response):
    token = _bearer_from(request)
    http_client = _get_http_client()
    resp = await http_client.get(
        "https://discord.com/api/users/@me",
        headers={"Authorization": f"Bearer {token}"},
    )
    response.status_code = resp.status_code
    return resp.text


@app.get("/api/guilds")
async def guilds(request: Request, response: Response):
    token = _bearer_from(request)
    http_client = _get_http_client()
    resp = await http_client.get(
        "https://discord.com/api/users/@me/guilds",
        headers={"Authorization": f"Bearer {token}"},
    )
    response.status_code = resp.status_code
    return resp.text


app.mount("/", StaticFiles(directory=Path("../client/dist"), html=True), name="static")

if __name__ == "__main__":
    # set reload=False for production
    uvicorn.run(app, host="127.0.0.1", port=8001, reload=True)
