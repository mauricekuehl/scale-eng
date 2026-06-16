from asyncio import Lock
from typing import cast

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

app = FastAPI()
lock = Lock()
urls: dict[str, str] = {}
url_codes: dict[str, str] = {}


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
    value = value.strip()
    if not value:
        raise HTTPException(status_code=400)
    return value


@app.get("/{code}")
async def get_url(code: str) -> dict[str, str]:
    async with lock:
        if code not in urls:
            raise HTTPException(status_code=404)
        return {"url": urls[code]}


# Only for testing purposes
@app.delete("/")
async def delete_all() -> dict[str, int]:
    async with lock:
        count = len(urls)
        urls.clear()
        url_codes.clear()
    return {"deleted": count}


@app.put("/{code}")
async def put_url(code: str, request: Request) -> JSONResponse:
    original_url = url_from(await json_body(request))
    async with lock:
        if original_url in url_codes:
            return JSONResponse({"code": url_codes[original_url]})
        if code in urls:
            raise HTTPException(status_code=409, detail="exists")

        urls[code] = original_url
        url_codes[original_url] = code
        return JSONResponse({"code": code}, status_code=201)
