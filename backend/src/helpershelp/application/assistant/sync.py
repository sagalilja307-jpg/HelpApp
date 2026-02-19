from __future__ import annotations

import logging
import os
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple, Iterable, cast
from helpershelp.domain.models.unified_item import UnifiedItem as DomainUnifiedItem, ItemEdge as DomainItemEdge
from helpershelp.assistant.models import UnifiedItem as AssistantUnifiedItem

from helpershelp.assistant.linking import link_emails_to_events
from helpershelp.assistant.sources.gcal import GCalAdapter
from helpershelp.assistant.sources.gmail import GmailAdapter
from helpershelp.infrastructure.persistence.sqlite_storage import SqliteStore
from helpershelp.infrastructure.security.token_manager import load_oauth_token
from helpershelp.domain.value_objects.time_utils import utcnow

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class SyncConfig:
    interval_seconds: int = 15 * 60
    sources: Optional[List[str]] = None  # ["gmail", "gcal"]

    def __post_init__(self):
        if self.sources is None:
            object.__setattr__(self, "sources", ["gmail", "gcal"])


def _parse_expires_at(token: Dict) -> Optional[datetime]:
    exp = token.get("expires_at")
    if not exp:
        return None
    try:
        return datetime.fromisoformat(exp.replace("Z", "+00:00"))
    except Exception:
        return None


def _token_valid(token: Dict) -> bool:
    exp = _parse_expires_at(token)
    if not exp:
        return True
    return exp > utcnow() + timedelta(seconds=30)


def run_sync_once(store: SqliteStore, sources: List[str]) -> Dict[str, int]:
    counts: Dict[str, int] = {"items_fetched": 0, "items_inserted": 0, "items_updated": 0, "edges_inserted": 0, "edges_updated": 0}

    for src in sources:
        token = load_oauth_token(store, provider=src)
        if not token:
            logger.info("[sync] No persisted token for %s", src)
            continue
        if not _token_valid(token):
            logger.info("[sync] Token expired for %s", src)
            continue

        access_token = token.get("access_token")
        if not access_token:
            continue

        try:
            if src == "gmail":
                items = GmailAdapter(access_token=access_token).fetch_items(days=90, max_results=50)
                ins, upd = store.upsert_items(cast(Iterable[DomainUnifiedItem], items))
                store.audit("sync_loop_gmail", {"fetched": len(items), "inserted": ins, "updated": upd})
            elif src == "gcal":
                items = GCalAdapter(access_token=access_token).fetch_items(days_forward=14, days_back=7, max_results=250)
                ins, upd = store.upsert_items(cast(Iterable[DomainUnifiedItem], items))
                store.audit("sync_loop_gcal", {"fetched": len(items), "inserted": ins, "updated": upd})
            else:
                continue

            counts["items_fetched"] += len(items)
            counts["items_inserted"] += ins
            counts["items_updated"] += upd

        except Exception as e:
            store.audit("sync_error", {"source": src, "error": str(e)})
            logger.exception("[sync] Error syncing %s: %s", src, e)

    # Linking pass
    try:
        all_recent = store.list_items(since=utcnow() - timedelta(days=30), limit=5000)
        edges = link_emails_to_events(cast(List[AssistantUnifiedItem], all_recent))
        e_ins, e_upd = store.upsert_edges(cast(Iterable[DomainItemEdge], edges))
        counts["edges_inserted"] += e_ins
        counts["edges_updated"] += e_upd
    except Exception as e:
        store.audit("linking_error", {"error": str(e)})

    return counts


def start_sync_loop(store: SqliteStore) -> Optional[threading.Thread]:
    if os.getenv("HELPERSHELP_ENABLE_SYNC_LOOP", "0") != "1":
        return None

    interval_minutes = os.getenv("HELPERSHELP_SYNC_INTERVAL_MINUTES", "15")
    try:
        interval_seconds = int(float(interval_minutes) * 60)
    except Exception:
        interval_seconds = 15 * 60
    interval_seconds = max(60, min(24 * 60 * 60, interval_seconds))

    sources_env = os.getenv("HELPERSHELP_SYNC_SOURCES", "gmail,gcal").strip()
    sources = [s.strip() for s in sources_env.split(",") if s.strip()]
    if not sources:
        sources = ["gmail", "gcal"]

    def loop():
        logger.info("[sync] Loop started. interval=%ss sources=%s", interval_seconds, sources)
        while True:
            try:
                run_sync_once(store, sources=sources)
            except Exception as e:
                logger.exception("[sync] Loop iteration failed: %s", e)
            time.sleep(interval_seconds)

    t = threading.Thread(target=loop, name="helpershelp-sync-loop", daemon=True)
    t.start()
    return t
