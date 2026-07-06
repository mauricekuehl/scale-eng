import json
import os
import urllib.error
import urllib.request

import pytest

BASE_URL = os.environ.get("API_URL", "").rstrip("/")
if not BASE_URL:
    pytest.fail("API_URL is required", pytrace=False)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def request(method: str, path: str, body: dict[str, str] | None = None):
    data = None
    headers = {}
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"

    req = urllib.request.Request(f"{BASE_URL}{path}", data=data, headers=headers, method=method)
    try:
        return OPENER.open(req, timeout=10)
    except urllib.error.HTTPError as error:
        return error


def test_unknown_code_returns_404() -> None:
    response = request("GET", "/unknown1")
    assert response.status == 404, f"expected 404 for unknown code, got {response.status}"


def test_invalid_url_returns_400() -> None:
    response = request("POST", "/create", {"url": "not-a-url"})
    assert response.status == 400, f"expected 400 for invalid URL, got {response.status}"


def test_create_returns_new_codes_for_same_url_and_redirects() -> None:
    created = request("POST", "/create", {"url": "https://example.com/some/long/url"})
    assert created.status == 201, f"expected 201 for create, got {created.status}"
    short_url = json.load(created)["shortUrl"]
    code = short_url.rsplit("/", 1)[-1]
    assert len(code) == 8, f"expected 8-character code, got {code}"

    repeated = request("POST", "/create", {"url": "https://example.com/some/long/url"})
    assert repeated.status == 201, f"expected 201 for repeated create, got {repeated.status}"
    repeated_short_url = json.load(repeated)["shortUrl"]
    repeated_code = repeated_short_url.rsplit("/", 1)[-1]
    assert len(repeated_code) == 8, f"expected 8-character code, got {repeated_code}"
    assert repeated_short_url != short_url, "expected repeated URL to get a new code"

    redirect = request("GET", f"/{code}")
    assert redirect.status == 302, f"expected 302 for short URL, got {redirect.status}"
    assert redirect.headers["Location"] == "https://example.com/some/long/url"

    repeated_redirect = request("GET", f"/{repeated_code}")
    assert repeated_redirect.status == 302, (
        f"expected 302 for repeated short URL, got {repeated_redirect.status}"
    )
    assert repeated_redirect.headers["Location"] == "https://example.com/some/long/url"
