import os
import secrets
import string
from typing import cast
from urllib.parse import urlparse

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import RedirectResponse

BASE_URL = os.environ["BASE_URL"].rstrip("/")
DB_URL = os.environ["DB_URL"].rstrip("/")
CHARS = string.ascii_letters + string.digits
CODE_LENGTH = 8
MAX_CREATE_ATTEMPTS = 10

app = FastAPI()


async def json_body(request: Request) -> dict[str, object]:
    try:
        body: object = await request.json()
    except ValueError as exc:
        raise HTTPException(status_code=400) from exc
    if not isinstance(body, dict):
        raise HTTPException(status_code=400)
    return cast(dict[str, object], body)


def url_from(body: dict[str, object]) -> str:
    value = body.get("url")
    if not isinstance(value, str):
        raise HTTPException(status_code=400)

    original_url = value.strip()
    parsed = urlparse(original_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise HTTPException(status_code=400)
    return original_url


def generate_code() -> str:
    return "".join(secrets.choice(CHARS) for _ in range(CODE_LENGTH))


@app.post("/create", status_code=201)
async def create(request: Request) -> dict[str, str]:
    original_url = url_from(await json_body(request))
    # This is bad Design. We probably should change this.
    async with httpx.AsyncClient(timeout=3) as client:
        for _ in range(MAX_CREATE_ATTEMPTS):
            code = generate_code()
            response = await client.put(f"{DB_URL}/{code}", json={"url": original_url})
            if response.status_code == 409:
                continue
            response.raise_for_status()
            return {"shortUrl": f"{BASE_URL}/{response.json()['code']}"}

    raise HTTPException(status_code=503, detail="could not allocate short code")


@app.get("/{code}")
async def redirect(code: str) -> RedirectResponse:
    if len(code) != CODE_LENGTH:
        raise HTTPException(status_code=404)

    async with httpx.AsyncClient(timeout=3) as client:
        response = await client.get(f"{DB_URL}/{code}")
        if response.status_code == 404:
            raise HTTPException(status_code=404)
        response.raise_for_status()
    return RedirectResponse(response.json()["url"], status_code=302)
