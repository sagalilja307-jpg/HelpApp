"""Storage port - abstract interface for persistence"""
from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

from helpershelp.domain.models import ItemEdge, Proposal, UnifiedItem


class StoragePort(ABC):
    """Abstract interface for item storage operations"""

    @abstractmethod
    def init(self) -> None:
        """Initialize storage (create tables, etc.)"""
        pass

    @abstractmethod
    def upsert_item(self, item: UnifiedItem) -> None:
        """Insert or update an item"""
        pass

    @abstractmethod
    def get_item(self, item_id: str) -> Optional[UnifiedItem]:
        """Retrieve an item by ID"""
        pass

    @abstractmethod
    def list_items(
        self,
        item_type: Optional[str] = None,
        limit: Optional[int] = None,
        offset: int = 0,
    ) -> List[UnifiedItem]:
        """List items with optional filtering"""
        pass

    @abstractmethod
    def delete_item(self, item_id: str) -> None:
        """Delete an item"""
        pass

    @abstractmethod
    def upsert_proposal(self, proposal: Proposal) -> None:
        """Insert or update a proposal"""
        pass

    @abstractmethod
    def get_proposal(self, proposal_id: str) -> Optional[Proposal]:
        """Retrieve a proposal by ID"""
        pass

    @abstractmethod
    def list_proposals(
        self,
        status: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> List[Proposal]:
        """List proposals with optional status filter"""
        pass

    @abstractmethod
    def upsert_edge(self, edge: ItemEdge) -> None:
        """Insert or update an edge"""
        pass

    @abstractmethod
    def list_edges(
        self,
        from_item_id: Optional[str] = None,
        to_item_id: Optional[str] = None,
    ) -> List[ItemEdge]:
        """List edges with optional filters"""
        pass

    @abstractmethod
    def get_settings(self) -> Dict[str, Any]:
        """Get all settings"""
        pass

    @abstractmethod
    def set_setting(self, key: str, value: Any) -> None:
        """Set a single setting"""
        pass
