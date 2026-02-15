from __future__ import annotations

from datetime import datetime, timezone


def utcnow() -> datetime:
    """
    Return a naive datetime representing current UTC time.

    Python 3.14 deprecates `datetime.utcnow()`. This helper keeps the codebase
    forward-compatible while still using naive UTC timestamps internally.
    """
    return datetime.now(timezone.utc).replace(tzinfo=None)

