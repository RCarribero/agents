from types import SimpleNamespace

import pytest

import supabase_client


@pytest.fixture(autouse=True)
def clear_supabase_cache(monkeypatch):
    monkeypatch.delenv("SUPABASE_URL", raising=False)
    monkeypatch.delenv("SUPABASE_KEY", raising=False)
    supabase_client.clear_supabase_client_cache()
    yield
    supabase_client.clear_supabase_client_cache()


def test_cached_supabase_client_is_reused(monkeypatch):
    calls: list[tuple[str, str]] = []

    def fake_create_client(url: str, key: str):
        calls.append((url, key))
        return SimpleNamespace(url=url, key=key)

    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_KEY", "service-key")
    monkeypatch.setattr(supabase_client, "create_client", fake_create_client)

    first = supabase_client.get_shared_supabase_client()
    second = supabase_client.get_shared_supabase_client()

    assert first is second
    assert calls == [("https://example.supabase.co", "service-key")]


def test_missing_configuration_raises_explicit_error():
    with pytest.raises(supabase_client.SupabaseConfigurationError):
        supabase_client.get_shared_supabase_client()