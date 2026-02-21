from __future__ import annotations

import json
import os
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional
from uuid import uuid4

from helpershelp.core.time_utils import utcnow
from helpershelp.core.config import DEFAULT_DB_PATH


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None


def _dt(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _dump_model(obj: Any) -> Dict[str, Any]:
    if obj is None:
        return {}
    # Handle dataclasses (new domain models)
    if hasattr(obj, "__dataclass_fields__"):
        from dataclasses import asdict
        result = asdict(obj)
        # Convert enums to their values
        for key, value in result.items():
            if hasattr(value, 'value'):
                result[key] = value.value
        return result
    # Handle Pydantic models (for backward compatibility)
    if hasattr(obj, "model_dump"):
        return obj.model_dump()  # pydantic v2
    if hasattr(obj, "dict"):
        return obj.dict()  # pydantic v1
    if isinstance(obj, dict):
        return obj
    raise TypeError(f"Unsupported model type: {type(obj)}")


@dataclass(frozen=True)
class StoreConfig:
    db_path: Path


class SqliteStore:
    def __init__(self, config: StoreConfig):
        self.config = config

    @contextmanager
    def _conn(self):
        self.config.db_path.parent.mkdir(parents=True, exist_ok=True)
        conn = sqlite3.connect(str(self.config.db_path), check_same_thread=False)
        conn.row_factory = sqlite3.Row
        try:
            conn.execute("PRAGMA journal_mode=WAL;")
            conn.execute("PRAGMA foreign_keys=ON;")
            yield conn
            conn.commit()
        finally:
            conn.close()

    def init(self) -> None:
        with self._conn() as conn:
            conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS unified_items (
                    id TEXT PRIMARY KEY,
                    source TEXT NOT NULL,
                    type TEXT NOT NULL,
                    title TEXT NOT NULL,
                    body TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    start_at TEXT,
                    end_at TEXT,
                    due_at TEXT,
                    people_json TEXT NOT NULL,
                    status_json TEXT NOT NULL,
                    external_provider TEXT,
                    external_id TEXT,
                    external_url TEXT,
                    external_ref_json TEXT,
                    provenance_json TEXT
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_unified_items_external
                    ON unified_items(external_provider, external_id)
                    WHERE external_provider IS NOT NULL AND external_id IS NOT NULL;

                CREATE INDEX IF NOT EXISTS idx_unified_items_type_updated
                    ON unified_items(type, updated_at);

                CREATE TABLE IF NOT EXISTS item_edges (
                    id TEXT PRIMARY KEY,
                    from_item_id TEXT NOT NULL,
                    to_item_id TEXT NOT NULL,
                    edge_type TEXT NOT NULL,
                    score REAL NOT NULL,
                    reasons_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(from_item_id) REFERENCES unified_items(id) ON DELETE CASCADE,
                    FOREIGN KEY(to_item_id) REFERENCES unified_items(id) ON DELETE CASCADE
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_item_edges_unique
                    ON item_edges(from_item_id, to_item_id, edge_type);

                CREATE TABLE IF NOT EXISTS proposals (
                    id TEXT PRIMARY KEY,
                    dedupe_key TEXT NOT NULL,
                    proposal_type TEXT NOT NULL,
                    status TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    details_json TEXT NOT NULL,
                    why_json TEXT NOT NULL,
                    actions_json TEXT NOT NULL,
                    related_item_ids_json TEXT NOT NULL,
                    expires_at TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_proposals_dedupe
                    ON proposals(dedupe_key);
                CREATE INDEX IF NOT EXISTS idx_proposals_status
                    ON proposals(status, updated_at);

                CREATE TABLE IF NOT EXISTS feedback_events (
                    id TEXT PRIMARY KEY,
                    proposal_id TEXT NOT NULL,
                    event_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    FOREIGN KEY(proposal_id) REFERENCES proposals(id) ON DELETE CASCADE
                );
                CREATE INDEX IF NOT EXISTS idx_feedback_events_type_time
                    ON feedback_events(event_type, created_at);

                CREATE TABLE IF NOT EXISTS settings (
                    key TEXT PRIMARY KEY,
                    value_json TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS audit_log (
                    id TEXT PRIMARY KEY,
                    event_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    created_at TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_audit_log_time
                    ON audit_log(created_at);

                CREATE TABLE IF NOT EXISTS source_sync_state (
                    source TEXT PRIMARY KEY,
                    cursor TEXT,
                    updated_at TEXT NOT NULL
                );
                """
            )

    def audit(self, event_type: str, payload: Dict[str, Any]) -> None:
        row_id = str(uuid4())
        now = utcnow().isoformat()
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO audit_log (id, event_type, payload_json, created_at) VALUES (?, ?, ?, ?)",
                (row_id, event_type, json.dumps(payload, ensure_ascii=False), now),
            )

    def get_settings(self) -> Dict[str, Any]:
        with self._conn() as conn:
            rows = conn.execute("SELECT key, value_json FROM settings").fetchall()
        out: Dict[str, Any] = {}
        for row in rows:
            try:
                out[row["key"]] = json.loads(row["value_json"])
            except Exception:
                out[row["key"]] = row["value_json"]
        return out

    def upsert_settings(self, updates: Dict[str, Any]) -> Dict[str, Any]:
        now = utcnow().isoformat()
        with self._conn() as conn:
            for key, val in updates.items():
                conn.execute(
                    """
                    INSERT INTO settings (key, value_json, updated_at)
                    VALUES (?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        value_json=excluded.value_json,
                        updated_at=excluded.updated_at
                    """,
                    (key, json.dumps(val, ensure_ascii=False), now),
                )
        return self.get_settings()

    def delete_settings(self, keys: Iterable[str]) -> int:
        key_list = [str(key) for key in keys if str(key).strip()]
        if not key_list:
            return 0
        with self._conn() as conn:
            placeholders = ",".join(["?"] * len(key_list))
            cur = conn.execute(
                f"DELETE FROM settings WHERE key IN ({placeholders})",
                key_list,
            )
            return int(cur.rowcount or 0)





    def count_audit_events(self, event_type: str, since: datetime) -> int:
        with self._conn() as conn:
            row = conn.execute(
                """
                SELECT COUNT(*) AS count_value
                FROM audit_log
                WHERE event_type=? AND created_at>=?
                """,
                (event_type, since.isoformat()),
            ).fetchone()
        if not row:
            return 0
        return int(row["count_value"] or 0)

    def list_audit_events(
        self,
        event_types: Optional[List[str]] = None,
        since: Optional[datetime] = None,
        limit: int = 200,
    ) -> List[Dict[str, Any]]:
        clauses: List[str] = []
        params: List[Any] = []
        if event_types:
            placeholders = ",".join(["?"] * len(event_types))
            clauses.append(f"event_type IN ({placeholders})")
            params.extend(event_types)
        if since:
            clauses.append("created_at >= ?")
            params.append(since.isoformat())

        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        sql = f"""
            SELECT id, event_type, payload_json, created_at
            FROM audit_log
            {where}
            ORDER BY created_at DESC
            LIMIT ?
        """
        params.append(int(limit))
        with self._conn() as conn:
            rows = conn.execute(sql, params).fetchall()

        out: List[Dict[str, Any]] = []
        for row in rows:
            payload = {}
            try:
                payload = json.loads(row["payload_json"] or "{}")
            except Exception:
                payload = {"raw": row["payload_json"]}
            out.append(
                {
                    "id": row["id"],
                    "event_type": row["event_type"],
                    "payload": payload,
                    "created_at": row["created_at"],
                }
            )
        return out


def get_store() -> SqliteStore:
    db_path = Path(os.getenv("HELPERSHELP_DB_PATH", str(DEFAULT_DB_PATH))).expanduser().resolve()
    store = SqliteStore(StoreConfig(db_path=db_path))
    store.init()
    return store
