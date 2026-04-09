"""
Helpers compartidos para gestionar el cliente de Supabase.

Centraliza la carga de configuración y reutiliza una única instancia del
cliente durante la vida del proceso para evitar recrearlo en cada request.
"""

from __future__ import annotations

import os
from functools import lru_cache

from supabase import Client, create_client


class SupabaseConfigurationError(RuntimeError):
    """Se lanza cuando falta configuración obligatoria de Supabase."""


def is_supabase_configured() -> bool:
    return bool(os.getenv("SUPABASE_URL") and os.getenv("SUPABASE_KEY"))


def _get_supabase_credentials() -> tuple[str, str]:
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_KEY")

    if not url or not key:
        raise SupabaseConfigurationError(
            "Supabase no configurado. Variables SUPABASE_URL y SUPABASE_KEY requeridas."
        )

    return url, key


@lru_cache(maxsize=1)
def get_shared_supabase_client() -> Client:
    url, key = _get_supabase_credentials()
    return create_client(url, key)


def clear_supabase_client_cache() -> None:
    get_shared_supabase_client.cache_clear()