from __future__ import annotations

import json
import os
import sqlite3
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional, Tuple
from uuid import uuid4

from helpershelp.domain.models import ItemEdge, Proposal, ProposalStatus, UnifiedItem
from helpershelp.domain.value_objects.time_utils import utcnow
from helpershelp.config import DEFAULT_DB_PATH


def _iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None


def _dt(value: Optional[str]) -> Optional[datetime]:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _naive_utc(value: Optional[datetime]) -> Optional[datetime]:
    if value is None:
        return None
    if value.tzinfo is None:
        return value
    return value.astimezone(timezone.utc).replace(tzinfo=None)


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


def _json_default(value: Any):
    if isinstance(value, datetime):
        return value.isoformat()
    raise TypeError(f"Unsupported JSON type: {type(value)}")


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

                CREATE TABLE IF NOT EXISTS calendar_feature_events (
                    id TEXT PRIMARY KEY,
                    event_identifier TEXT NOT NULL,
                    title TEXT NOT NULL,
                    notes TEXT,
                    location TEXT,
                    start_at TEXT NOT NULL,
                    end_at TEXT NOT NULL,
                    is_all_day INTEGER NOT NULL,
                    calendar_title TEXT,
                    last_modified_at TEXT,
                    snapshot_hash TEXT NOT NULL,
                    ingested_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL,
                    payload_json TEXT NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_calendar_feature_events_start_at
                    ON calendar_feature_events(start_at);
                CREATE INDEX IF NOT EXISTS idx_calendar_feature_events_updated_at
                    ON calendar_feature_events(updated_at);
                CREATE INDEX IF NOT EXISTS idx_calendar_feature_events_event_identifier
                    ON calendar_feature_events(event_identifier);
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

    @staticmethod
    def _item_to_row(item: UnifiedItem) -> Dict[str, Any]:
        ext_provider = item.external_ref.provider if item.external_ref else None
        ext_id = item.external_ref.provider_id if item.external_ref else None
        ext_url = item.external_ref.url if item.external_ref else None
        return {
            "id": item.id,
            "source": item.source,
            "type": item.type.value,
            "title": item.title or "",
            "body": item.body or "",
            "created_at": _iso(item.created_at) or utcnow().isoformat(),
            "updated_at": _iso(item.updated_at) or utcnow().isoformat(),
            "start_at": _iso(item.start_at),
            "end_at": _iso(item.end_at),
            "due_at": _iso(item.due_at),
            "people_json": json.dumps([_dump_model(p) for p in item.people], ensure_ascii=False),
            "status_json": json.dumps(item.status or {}, ensure_ascii=False),
            "external_provider": ext_provider,
            "external_id": ext_id,
            "external_url": ext_url,
            "external_ref_json": json.dumps(_dump_model(item.external_ref), ensure_ascii=False) if item.external_ref else None,
            "provenance_json": json.dumps(_dump_model(item.provenance), ensure_ascii=False) if item.provenance else None,
        }

    @staticmethod
    def _row_to_item(row: sqlite3.Row) -> UnifiedItem:
        from helpershelp.domain.models import Person, ExternalRef, Provenance, UnifiedItemType
        
        # Parse people
        people_data = json.loads(row["people_json"] or "[]")
        people = [Person(**p) if isinstance(p, dict) else p for p in people_data]
        
        # Parse external_ref
        external_ref = None
        if row["external_ref_json"]:
            ext_data = json.loads(row["external_ref_json"])
            if ext_data:
                external_ref = ExternalRef(**ext_data)
        
        # Parse provenance
        provenance = None
        if row["provenance_json"]:
            prov_data = json.loads(row["provenance_json"])
            if prov_data:
                provenance = Provenance(**prov_data)
        
        return UnifiedItem(
            id=row["id"],
            source=row["source"],
            type=UnifiedItemType(row["type"]),
            title=row["title"],
            body=row["body"],
            created_at=_dt(row["created_at"]) or utcnow(),
            updated_at=_dt(row["updated_at"]) or utcnow(),
            start_at=_dt(row["start_at"]),
            end_at=_dt(row["end_at"]),
            due_at=_dt(row["due_at"]),
            people=people,
            status=json.loads(row["status_json"] or "{}"),
            external_ref=external_ref,
            provenance=provenance,
        )

    def upsert_items(self, items: Iterable[UnifiedItem]) -> Tuple[int, int]:
        inserted = 0
        updated = 0
        with self._conn() as conn:
            for item in items:
                row = self._item_to_row(item)
                if row["external_provider"] and row["external_id"]:
                    existing = conn.execute(
                        "SELECT id FROM unified_items WHERE external_provider=? AND external_id=?",
                        (row["external_provider"], row["external_id"]),
                    ).fetchone()
                    if existing:
                        row["id"] = existing["id"]
                        row["updated_at"] = utcnow().isoformat()
                        conn.execute(
                            """
                            UPDATE unified_items SET
                                source=:source,
                                type=:type,
                                title=:title,
                                body=:body,
                                updated_at=:updated_at,
                                start_at=:start_at,
                                end_at=:end_at,
                                due_at=:due_at,
                                people_json=:people_json,
                                status_json=:status_json,
                                external_url=:external_url,
                                external_ref_json=:external_ref_json,
                                provenance_json=:provenance_json
                            WHERE id=:id
                            """,
                            row,
                        )
                        updated += 1
                        continue

                # Fallback: upsert by id
                existing_by_id = conn.execute(
                    "SELECT id FROM unified_items WHERE id=?",
                    (row["id"],),
                ).fetchone()
                if existing_by_id:
                    row["updated_at"] = utcnow().isoformat()
                    conn.execute(
                        """
                        UPDATE unified_items SET
                            source=:source,
                            type=:type,
                            title=:title,
                            body=:body,
                            updated_at=:updated_at,
                            start_at=:start_at,
                            end_at=:end_at,
                            due_at=:due_at,
                            people_json=:people_json,
                            status_json=:status_json,
                            external_provider=:external_provider,
                            external_id=:external_id,
                            external_url=:external_url,
                            external_ref_json=:external_ref_json,
                            provenance_json=:provenance_json
                        WHERE id=:id
                        """,
                        row,
                    )
                    updated += 1
                else:
                    conn.execute(
                        """
                        INSERT INTO unified_items (
                            id, source, type, title, body,
                            created_at, updated_at,
                            start_at, end_at, due_at,
                            people_json, status_json,
                            external_provider, external_id, external_url,
                            external_ref_json, provenance_json
                        ) VALUES (
                            :id, :source, :type, :title, :body,
                            :created_at, :updated_at,
                            :start_at, :end_at, :due_at,
                            :people_json, :status_json,
                            :external_provider, :external_id, :external_url,
                            :external_ref_json, :provenance_json
                        )
                        """,
                        row,
                    )
                    inserted += 1
        return inserted, updated

    def list_items(
        self,
        since: Optional[datetime] = None,
        types: Optional[List[str]] = None,
        limit: int = 1000,
    ) -> List[UnifiedItem]:
        clauses: List[str] = []
        params: List[Any] = []
        if since:
            clauses.append("updated_at >= ?")
            params.append(since.isoformat())
        if types:
            clauses.append(f"type IN ({','.join(['?'] * len(types))})")
            params.extend(types)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        sql = f"SELECT * FROM unified_items {where} ORDER BY updated_at DESC LIMIT ?"
        params.append(int(limit))

        with self._conn() as conn:
            rows = conn.execute(sql, params).fetchall()
        return [self._row_to_item(r) for r in rows]

    def get_item(self, item_id: str) -> Optional[UnifiedItem]:
        with self._conn() as conn:
            row = conn.execute("SELECT * FROM unified_items WHERE id=?", (item_id,)).fetchone()
        return self._row_to_item(row) if row else None

    def upsert_calendar_feature_events(self, events: Iterable[Dict[str, Any]]) -> Tuple[int, int]:
        inserted = 0
        updated = 0
        now_iso = utcnow().isoformat()

        with self._conn() as conn:
            for event in events:
                row_id = str(event.get("id") or "")
                snapshot_hash = str(event.get("snapshot_hash") or "")
                if not row_id or not snapshot_hash:
                    continue

                existing = conn.execute(
                    "SELECT snapshot_hash FROM calendar_feature_events WHERE id=?",
                    (row_id,),
                ).fetchone()
                if existing and existing["snapshot_hash"] == snapshot_hash:
                    continue

                payload = json.dumps(event, ensure_ascii=False, default=_json_default)
                row_payload = (
                    row_id,
                    str(event.get("event_identifier") or ""),
                    str(event.get("title") or ""),
                    event.get("notes"),
                    event.get("location"),
                    _iso(event.get("start_at")) if isinstance(event.get("start_at"), datetime) else str(event.get("start_at") or ""),
                    _iso(event.get("end_at")) if isinstance(event.get("end_at"), datetime) else str(event.get("end_at") or ""),
                    1 if bool(event.get("is_all_day")) else 0,
                    event.get("calendar_title"),
                    _iso(event.get("last_modified_at")) if isinstance(event.get("last_modified_at"), datetime) else event.get("last_modified_at"),
                    snapshot_hash,
                    now_iso,
                    now_iso,
                    payload,
                )

                if existing:
                    conn.execute(
                        """
                        UPDATE calendar_feature_events SET
                            event_identifier=?,
                            title=?,
                            notes=?,
                            location=?,
                            start_at=?,
                            end_at=?,
                            is_all_day=?,
                            calendar_title=?,
                            last_modified_at=?,
                            snapshot_hash=?,
                            updated_at=?,
                            payload_json=?
                        WHERE id=?
                        """,
                        (
                            row_payload[1],
                            row_payload[2],
                            row_payload[3],
                            row_payload[4],
                            row_payload[5],
                            row_payload[6],
                            row_payload[7],
                            row_payload[8],
                            row_payload[9],
                            row_payload[10],
                            row_payload[12],
                            row_payload[13],
                            row_payload[0],
                        ),
                    )
                    updated += 1
                else:
                    conn.execute(
                        """
                        INSERT INTO calendar_feature_events (
                            id,
                            event_identifier,
                            title,
                            notes,
                            location,
                            start_at,
                            end_at,
                            is_all_day,
                            calendar_title,
                            last_modified_at,
                            snapshot_hash,
                            ingested_at,
                            updated_at,
                            payload_json
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                        row_payload,
                    )
                    inserted += 1
        return inserted, updated

    def list_calendar_feature_events(
        self,
        *,
        start: datetime,
        end: datetime,
        limit: int = 10000,
    ) -> List[Dict[str, Any]]:
        with self._conn() as conn:
            rows = conn.execute(
                """
                SELECT *
                FROM calendar_feature_events
                WHERE start_at <= ? AND end_at >= ?
                ORDER BY start_at ASC
                LIMIT ?
                """,
                (end.isoformat(), start.isoformat(), int(limit)),
            ).fetchall()

        out: List[Dict[str, Any]] = []
        for row in rows:
            out.append(
                {
                    "id": row["id"],
                    "event_identifier": row["event_identifier"],
                    "title": row["title"],
                    "notes": row["notes"],
                    "location": row["location"],
                    "start_at": _dt(row["start_at"]),
                    "end_at": _dt(row["end_at"]),
                    "is_all_day": bool(row["is_all_day"]),
                    "calendar_title": row["calendar_title"],
                    "last_modified_at": _dt(row["last_modified_at"]),
                    "snapshot_hash": row["snapshot_hash"],
                    "ingested_at": _dt(row["ingested_at"]),
                    "updated_at": _dt(row["updated_at"]),
                }
            )
        return out

    def get_calendar_feature_status(self, now: datetime, ttl_hours: int = 24) -> Dict[str, Any]:
        with self._conn() as conn:
            row = conn.execute(
                """
                SELECT
                    COUNT(*) AS snapshot_count,
                    MIN(start_at) AS coverage_start,
                    MAX(end_at) AS coverage_end,
                    MAX(updated_at) AS last_updated
                FROM calendar_feature_events
                """
            ).fetchone()

        snapshot_count = int((row["snapshot_count"] if row else 0) or 0)
        coverage_start = _naive_utc(_dt(row["coverage_start"])) if row else None
        coverage_end = _naive_utc(_dt(row["coverage_end"])) if row else None
        last_updated = _naive_utc(_dt(row["last_updated"])) if row else None

        now_utc = _naive_utc(now) or utcnow()

        coverage_days = None
        if coverage_start and coverage_end:
            coverage_days = max(1, (coverage_end.date() - coverage_start.date()).days + 1)

        fresh = False
        if last_updated:
            fresh = (now_utc - last_updated).total_seconds() <= max(0, int(ttl_hours)) * 3600

        return {
            "available": snapshot_count > 0,
            "last_updated": last_updated,
            "coverage_start": coverage_start,
            "coverage_end": coverage_end,
            "coverage_days": coverage_days,
            "snapshot_count": snapshot_count,
            "fresh": fresh,
            "freshness_ttl_hours": int(ttl_hours),
        }

    def upsert_edges(self, edges: Iterable[ItemEdge]) -> Tuple[int, int]:
        inserted = 0
        updated = 0
        with self._conn() as conn:
            for edge in edges:
                exists = conn.execute(
                    "SELECT id FROM item_edges WHERE from_item_id=? AND to_item_id=? AND edge_type=?",
                    (edge.from_item_id, edge.to_item_id, edge.edge_type.value),
                ).fetchone()
                payload = (
                    edge.id,
                    edge.from_item_id,
                    edge.to_item_id,
                    edge.edge_type.value,
                    float(edge.score),
                    json.dumps(edge.reasons or [], ensure_ascii=False),
                    _iso(edge.created_at) or utcnow().isoformat(),
                )
                if exists:
                    conn.execute(
                        """
                        UPDATE item_edges SET
                            score=?,
                            reasons_json=?,
                            created_at=created_at
                        WHERE id=?
                        """,
                        (float(edge.score), json.dumps(edge.reasons or [], ensure_ascii=False), exists["id"]),
                    )
                    updated += 1
                else:
                    conn.execute(
                        """
                        INSERT INTO item_edges (id, from_item_id, to_item_id, edge_type, score, reasons_json, created_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """,
                        payload,
                    )
                    inserted += 1
        return inserted, updated

    def list_edges_for_items(self, item_ids: List[str]) -> List[ItemEdge]:
        if not item_ids:
            return []
        placeholders = ",".join(["?"] * len(item_ids))
        sql = f"""
            SELECT * FROM item_edges
            WHERE from_item_id IN ({placeholders}) OR to_item_id IN ({placeholders})
        """
        params = item_ids + item_ids
        with self._conn() as conn:
            rows = conn.execute(sql, params).fetchall()

        edges: List[ItemEdge] = []
        for r in rows:
            from helpershelp.domain.models import EdgeType
            edges.append(
                ItemEdge(
                    id=r["id"],
                    from_item_id=r["from_item_id"],
                    to_item_id=r["to_item_id"],
                    edge_type=EdgeType(r["edge_type"]),
                    score=float(r["score"]),
                    reasons=json.loads(r["reasons_json"] or "[]"),
                    created_at=_dt(r["created_at"]) or utcnow(),
                )
            )
        return edges

    @staticmethod
    def _proposal_to_row(proposal: Proposal) -> Dict[str, Any]:
        related_ids = sorted(set(proposal.related_item_ids or []))
        dedupe_key = f"{proposal.proposal_type.value}:" + ",".join(related_ids)
        return {
            "id": proposal.id,
            "dedupe_key": dedupe_key,
            "proposal_type": proposal.proposal_type.value,
            "status": proposal.status.value,
            "summary": proposal.summary,
            "details_json": json.dumps(proposal.details or {}, ensure_ascii=False),
            "why_json": json.dumps(proposal.why or {}, ensure_ascii=False),
            "actions_json": json.dumps(proposal.actions or {}, ensure_ascii=False),
            "related_item_ids_json": json.dumps(related_ids, ensure_ascii=False),
            "expires_at": _iso(proposal.expires_at),
            "created_at": _iso(proposal.created_at) or utcnow().isoformat(),
            "updated_at": _iso(proposal.updated_at) or utcnow().isoformat(),
        }

    @staticmethod
    def _row_to_proposal(row: sqlite3.Row) -> Proposal:
        from helpershelp.domain.models import ProposalType, ProposalStatus
        return Proposal(
            id=row["id"],
            proposal_type=ProposalType(row["proposal_type"]),
            status=ProposalStatus(row["status"]),
            summary=row["summary"],
            details=json.loads(row["details_json"] or "{}"),
            why=json.loads(row["why_json"] or "{}"),
            actions=json.loads(row["actions_json"] or "{}"),
            related_item_ids=json.loads(row["related_item_ids_json"] or "[]"),
            expires_at=_dt(row["expires_at"]),
            created_at=_dt(row["created_at"]) or utcnow(),
            updated_at=_dt(row["updated_at"]) or utcnow(),
        )

    def upsert_proposals(self, proposals: Iterable[Proposal]) -> Tuple[int, int]:
        inserted = 0
        updated = 0
        with self._conn() as conn:
            for proposal in proposals:
                row = self._proposal_to_row(proposal)
                existing = conn.execute(
                    "SELECT id, status FROM proposals WHERE dedupe_key=?",
                    (row["dedupe_key"],),
                ).fetchone()
                if existing:
                    # Don't resurrect dismissed/accepted proposals back to pending
                    existing_status = existing["status"]
                    if existing_status != ProposalStatus.pending.value:
                        continue
                    conn.execute(
                        """
                        UPDATE proposals SET
                            summary=:summary,
                            details_json=:details_json,
                            why_json=:why_json,
                            actions_json=:actions_json,
                            related_item_ids_json=:related_item_ids_json,
                            expires_at=:expires_at,
                            updated_at=:updated_at
                        WHERE id=:id
                        """,
                        {**row, "id": existing["id"]},
                    )
                    updated += 1
                else:
                    conn.execute(
                        """
                        INSERT INTO proposals (
                            id, dedupe_key, proposal_type, status, summary,
                            details_json, why_json, actions_json, related_item_ids_json,
                            expires_at, created_at, updated_at
                        ) VALUES (
                            :id, :dedupe_key, :proposal_type, :status, :summary,
                            :details_json, :why_json, :actions_json, :related_item_ids_json,
                            :expires_at, :created_at, :updated_at
                        )
                        """,
                        row,
                    )
                    inserted += 1
        return inserted, updated

    def list_proposals(self, status: str = ProposalStatus.pending.value, limit: int = 200) -> List[Proposal]:
        with self._conn() as conn:
            rows = conn.execute(
                "SELECT * FROM proposals WHERE status=? ORDER BY updated_at DESC LIMIT ?",
                (status, int(limit)),
            ).fetchall()
        return [self._row_to_proposal(r) for r in rows]

    def get_proposal(self, proposal_id: str) -> Optional[Proposal]:
        with self._conn() as conn:
            row = conn.execute("SELECT * FROM proposals WHERE id=?", (proposal_id,)).fetchone()
        return self._row_to_proposal(row) if row else None

    def update_proposal_status(self, proposal_id: str, status: ProposalStatus, user_edits: Dict[str, Any]) -> Optional[Proposal]:
        now = utcnow().isoformat()
        with self._conn() as conn:
            existing = conn.execute("SELECT * FROM proposals WHERE id=?", (proposal_id,)).fetchone()
            if not existing:
                return None

            # Merge edits into details for traceability
            details = json.loads(existing["details_json"] or "{}")
            if user_edits:
                details = {**details, "user_edits": user_edits}

            conn.execute(
                """
                UPDATE proposals SET
                    status=?,
                    details_json=?,
                    updated_at=?
                WHERE id=?
                """,
                (status.value, json.dumps(details, ensure_ascii=False), now, proposal_id),
            )
            row = conn.execute("SELECT * FROM proposals WHERE id=?", (proposal_id,)).fetchone()
        return self._row_to_proposal(row)

    def insert_feedback(self, proposal_id: str, event_type: str, payload: Dict[str, Any]) -> None:
        row_id = str(uuid4())
        now = utcnow().isoformat()
        with self._conn() as conn:
            conn.execute(
                "INSERT INTO feedback_events (id, proposal_id, event_type, payload_json, created_at) VALUES (?, ?, ?, ?, ?)",
                (row_id, proposal_id, event_type, json.dumps(payload, ensure_ascii=False), now),
            )

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
