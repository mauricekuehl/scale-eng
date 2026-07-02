import gc
from typing import cast

from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

app = FastAPI()
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


@app.get("/by-url")
async def get_code_by_url(url: str) -> dict[str, str]:
    try:
        return {"code": url_codes[url]}
    except KeyError:
        raise HTTPException(status_code=404) from None


@app.get("/{code}")
async def get_url(code: str) -> dict[str, str]:
    try:
        return {"url": urls[code]}
    except KeyError:
        raise HTTPException(status_code=404) from None


# Only for testing purposes
@app.delete("/")
async def delete_all() -> dict[str, int]:
    count = len(urls)
    urls.clear()
    url_codes.clear()
    gc.collect()
    return {"deleted": count}


@app.put("/{code}")
async def put_url(code: str, request: Request) -> JSONResponse:
    original_url = url_from(await json_body(request))
    existing_code = url_codes.get(original_url)
    if existing_code is not None:
        return JSONResponse({"code": existing_code})
    if code in urls:
        raise HTTPException(status_code=409, detail="exists")

    urls[code] = original_url
    url_codes[original_url] = code
    return JSONResponse({"code": code}, status_code=201)
