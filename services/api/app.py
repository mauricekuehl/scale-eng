import asyncio
import hashlib
import os
import secrets
import string
from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import cast
from urllib.parse import urlparse

import httpx
from cache import LRUCache
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import RedirectResponse
from instrumentation import instrument_cache
from opentelemetry import metrics

BASE_URL = os.environ["BASE_URL"].rstrip("/")
CHARS = string.ascii_letters + string.digits
CODE_LENGTH = 8
MAX_CREATE_ATTEMPTS = 10
DB_TIMEOUT = httpx.Timeout(connect=0.5, read=2.0, write=2.0, pool=0.5)
DB_LIMITS = httpx.Limits(max_connections=100, max_keepalive_connections=20)
CACHE_CAPACITY = int(os.environ.get("CACHE_CAPACITY", "1000"))

cache = LRUCache(CACHE_CAPACITY)
# Expose the cache's cumulative hit/miss counters as OTLP metrics
instrument_cache(metrics.get_meter("url-shortener-api"), cache)


def configured_db_urls() -> tuple[str, ...]:
    raw_urls = os.environ.get("DB_URLS") or os.environ.get("DB_URL")
    if raw_urls is None:
        raise RuntimeError("DB_URLS or DB_URL is required")

    urls = tuple(url.strip().rstrip("/") for url in raw_urls.split(",") if url.strip())
    if not urls:
        raise RuntimeError("DB_URLS or DB_URL must contain at least one URL")
    return urls


DB_URLS = configured_db_urls()


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncIterator[None]:
    app.state.db_client = httpx.AsyncClient(
        timeout=DB_TIMEOUT,
        limits=DB_LIMITS,
        trust_env=False,
    )
    try:
        yield
    finally:
        await app.state.db_client.aclose()


app = FastAPI(lifespan=lifespan)


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


def db_client(request: Request) -> httpx.AsyncClient:
    return cast(httpx.AsyncClient, request.app.state.db_client)


def shard_url_for_key(key: str) -> str:
    digest = hashlib.sha256(key.encode()).digest()
    shard_index = int.from_bytes(digest[:8], "big") % len(DB_URLS)
    return DB_URLS[shard_index]


def raise_for_db_status(response: httpx.Response) -> None:
    try:
        response.raise_for_status()
    except httpx.HTTPStatusError as exc:
        raise HTTPException(status_code=502, detail="db service error") from exc


async def db_get(client: httpx.AsyncClient, code: str) -> httpx.Response:
    try:
        return await client.get(f"{shard_url_for_key(code)}/{code}")
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="db service unavailable") from exc


async def db_put(client: httpx.AsyncClient, code: str, original_url: str) -> httpx.Response:
    try:
        return await client.put(f"{shard_url_for_key(code)}/{code}", json={"url": original_url})
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="db service unavailable") from exc


# Only for testing purposes
@app.delete("/")
async def delete_all(request: Request) -> dict[str, int]:
    client = db_client(request)
    try:
        responses = await asyncio.gather(*(client.delete(f"{db_url}/") for db_url in DB_URLS))
    except httpx.RequestError as exc:
        raise HTTPException(status_code=503, detail="db service unavailable") from exc

    deleted = 0
    for response in responses:
        raise_for_db_status(response)
        deleted += response.json()["deleted"]
    cache.data.clear()
    return {"deleted": deleted}


@app.post("/create", status_code=201)
async def create(request: Request) -> dict[str, str]:
    original_url = url_from(await json_body(request))
    client = db_client(request)

    for _ in range(MAX_CREATE_ATTEMPTS):
        code = generate_code()
        response = await db_put(client, code, original_url)
        if response.status_code == 409:
            continue
        raise_for_db_status(response)
        return {"shortUrl": f"{BASE_URL}/{response.json()['code']}"}

    raise HTTPException(status_code=503, detail="could not allocate short code")


@app.get("/{code}")
async def redirect(code: str, request: Request) -> RedirectResponse:
    if len(code) != CODE_LENGTH:
        raise HTTPException(status_code=404)

    cached_url = cache.get(code)
    if cached_url is not None:
        return RedirectResponse(cached_url, status_code=302)

    response = await db_get(db_client(request), code)
    if response.status_code == 404:
        raise HTTPException(status_code=404)
    raise_for_db_status(response)

    url = response.json()["url"]
    cache.put(code, url)
    return RedirectResponse(url, status_code=302)
