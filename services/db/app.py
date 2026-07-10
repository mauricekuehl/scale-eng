import gc
from typing import cast

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

app = FastAPI()
urls: dict[str, str] = {}


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
    try:
        return {"url": urls[code]}
    except KeyError:
        raise HTTPException(status_code=404) from None


@app.delete("/{code}")
async def delete_url(code: str) -> dict[str, int]:
    try:
        del urls[code]
    except KeyError:
        raise HTTPException(status_code=404) from None
    return {"deleted": 1}


# Only for testing purposes
@app.delete("/")
async def delete_all() -> dict[str, int]:
    count = len(urls)
    urls.clear()
    gc.collect()
    return {"deleted": count}


@app.put("/{code}")
async def put_url(code: str, request: Request) -> JSONResponse:
    original_url = url_from(await json_body(request))
    if code in urls:
        raise HTTPException(status_code=409, detail="exists")

    urls[code] = original_url
    return JSONResponse({"code": code}, status_code=201)
