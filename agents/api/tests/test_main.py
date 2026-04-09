import asyncio
from datetime import datetime, timezone

import httpx
import pytest

from main import (
    PRODUCT_SEARCH_ERROR_MESSAGE,
    SERVICE_NAME,
    SERVICE_VERSION,
    app,
    get_product_repository,
)


def _product_payload(product_id: int) -> dict:
    timestamp = datetime.now(timezone.utc).isoformat()
    return {
        "id": product_id,
        "name": f"Product {product_id}",
        "description": "Test product",
        "price": 19.99,
        "created_at": timestamp,
        "updated_at": timestamp,
    }


class FakeProductRepository:
    async def search(self, query: str, limit: int, cursor: int | None = None):
        items = [_product_payload(1)]
        return items[:limit], None

    async def count_search_results(self, query: str) -> int:
        return 1


class FailingProductRepository:
    async def search(self, query: str, limit: int, cursor: int | None = None):
        raise RuntimeError("database unavailable")

    async def count_search_results(self, query: str) -> int:
        return 0


@pytest.fixture(autouse=True)
def clear_dependency_overrides():
    app.dependency_overrides.clear()
    yield
    app.dependency_overrides.clear()


async def _get(path: str, params: dict | None = None) -> httpx.Response:
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://testserver") as client:
        return await client.get(path, params=params)


def _get_sync(path: str, params: dict | None = None) -> httpx.Response:
    return asyncio.run(_get(path, params=params))


def test_health_check_returns_service_metadata():
    response = _get_sync("/health")

    assert response.status_code == 200
    payload = response.json()
    assert payload["status"] == "healthy"
    assert payload["service"] == SERVICE_NAME
    assert payload["version"] == SERVICE_VERSION


def test_ping_returns_pong():
    response = _get_sync("/ping")

    assert response.status_code == 200
    assert response.json()["message"] == "pong"


def test_root_returns_available_endpoints():
    response = _get_sync("/")

    assert response.status_code == 200
    payload = response.json()
    assert payload["service"] == SERVICE_NAME
    assert payload["version"] == SERVICE_VERSION
    assert payload["endpoints"]["products_search"] == "/products/search"


def test_product_search_returns_results_with_overridden_repository():
    app.dependency_overrides[get_product_repository] = lambda: FakeProductRepository()

    response = _get_sync("/products/search", params={"query": "phone"})

    assert response.status_code == 200
    payload = response.json()
    assert payload["total"] == 1
    assert payload["next_cursor"] is None
    assert payload["products"][0]["name"] == "Product 1"


def test_product_search_rejects_invalid_limit():
    app.dependency_overrides[get_product_repository] = lambda: FakeProductRepository()

    response = _get_sync("/products/search", params={"query": "phone", "limit": 0})

    assert response.status_code == 422


def test_product_search_returns_generic_error_message():
    app.dependency_overrides[get_product_repository] = lambda: FailingProductRepository()

    response = _get_sync("/products/search", params={"query": "phone"})

    assert response.status_code == 500
    assert response.json()["detail"] == PRODUCT_SEARCH_ERROR_MESSAGE