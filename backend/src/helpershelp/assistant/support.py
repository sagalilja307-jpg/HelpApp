from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple

from helpershelp.assistant.models import Proposal, ProposalType, UnifiedItem, UnifiedItemType
from helpershelp.assistant.time_utils import utcnow

SUPPORT_LEVEL_KEY = "assistant.support.level"
SUPPORT_PAUSED_KEY = "assistant.support.paused"
SUPPORT_ADAPTATION_ENABLED_KEY = "assistant.support.adaptation_enabled"
SUPPORT_TIME_CRITICAL_HOURS_KEY = "assistant.support.time_critical_hours"
SUPPORT_DAILY_CAPS_KEY = "assistant.support.daily_caps"

LEARNING_KEY_PREFIX = "assistant.learning."
ADAPTIVE_SETTING_KEYS: Tuple[str, ...] = ("assistant.follow_up_days",)

DEFAULT_SUPPORT_LEVEL = 1
DEFAULT_SUPPORT_PAUSED = False
DEFAULT_SUPPORT_ADAPTATION_ENABLED = True
DEFAULT_TIME_CRITICAL_HOURS = 24
DEFAULT_DAILY_CAPS = {"0": 0, "1": 2, "2": 3, "3": 5}


@dataclass(frozen=True)
class SupportPolicy:
    level: int
    paused: bool
    adaptation_enabled: bool
    time_critical_window_hours: int
    daily_caps: Dict[str, int]
    nudge_limit_per_day: int
    allow_structuring: bool
    allow_active_help: bool
    allow_follow_up: bool

    def as_dict(self) -> Dict[str, Any]:
        return {
            "level": self.level,
            "paused": self.paused,
            "adaptation_enabled": self.adaptation_enabled,
            "time_critical_window_hours": self.time_critical_window_hours,
            "daily_caps": self.daily_caps,
            "nudge_limit_per_day": self.nudge_limit_per_day,
            "allow_structuring": self.allow_structuring,
            "allow_active_help": self.allow_active_help,
            "allow_follow_up": self.allow_follow_up,
        }


def _parse_bool(value: Any, default: bool) -> bool:
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return bool(value)
    if isinstance(value, str):
        normalized = value.strip().lower()
        if normalized in {"1", "true", "yes", "on"}:
            return True
        if normalized in {"0", "false", "no", "off"}:
            return False
    return default


def _parse_int(value: Any, default: int, minimum: int, maximum: int) -> int:
    try:
        parsed = int(value)
    except Exception:
        parsed = default
    return max(minimum, min(maximum, parsed))


def _normalize_daily_caps(value: Any) -> Dict[str, int]:
    normalized = dict(DEFAULT_DAILY_CAPS)
    if not isinstance(value, Mapping):
        return normalized
    for raw_key, raw_cap in value.items():
        key = str(raw_key).strip()
        if key not in {"0", "1", "2", "3"}:
            continue
        normalized[key] = _parse_int(raw_cap, normalized[key], minimum=0, maximum=10)
    return normalized


def normalized_support_settings(settings: Mapping[str, Any]) -> Dict[str, Any]:
    out: Dict[str, Any] = {}
    out[SUPPORT_LEVEL_KEY] = _parse_int(
        settings.get(SUPPORT_LEVEL_KEY, DEFAULT_SUPPORT_LEVEL),
        default=DEFAULT_SUPPORT_LEVEL,
        minimum=0,
        maximum=3,
    )
    out[SUPPORT_PAUSED_KEY] = _parse_bool(
        settings.get(SUPPORT_PAUSED_KEY, DEFAULT_SUPPORT_PAUSED),
        default=DEFAULT_SUPPORT_PAUSED,
    )
    out[SUPPORT_ADAPTATION_ENABLED_KEY] = _parse_bool(
        settings.get(SUPPORT_ADAPTATION_ENABLED_KEY, DEFAULT_SUPPORT_ADAPTATION_ENABLED),
        default=DEFAULT_SUPPORT_ADAPTATION_ENABLED,
    )
    out[SUPPORT_TIME_CRITICAL_HOURS_KEY] = _parse_int(
        settings.get(SUPPORT_TIME_CRITICAL_HOURS_KEY, DEFAULT_TIME_CRITICAL_HOURS),
        default=DEFAULT_TIME_CRITICAL_HOURS,
        minimum=1,
        maximum=168,
    )
    out[SUPPORT_DAILY_CAPS_KEY] = _normalize_daily_caps(settings.get(SUPPORT_DAILY_CAPS_KEY))
    return out


def resolve_support_policy(settings: Mapping[str, Any]) -> SupportPolicy:
    normalized = normalized_support_settings(settings)
    level = int(normalized[SUPPORT_LEVEL_KEY])
    paused = bool(normalized[SUPPORT_PAUSED_KEY])
    adaptation_enabled = bool(normalized[SUPPORT_ADAPTATION_ENABLED_KEY])
    daily_caps = dict(normalized[SUPPORT_DAILY_CAPS_KEY])
    nudge_limit = 0 if paused else int(daily_caps.get(str(level), 0))

    allow_structuring = (not paused) and level >= 2
    allow_active_help = (not paused) and level >= 3
    allow_follow_up = allow_active_help

    return SupportPolicy(
        level=level,
        paused=paused,
        adaptation_enabled=adaptation_enabled,
        time_critical_window_hours=int(normalized[SUPPORT_TIME_CRITICAL_HOURS_KEY]),
        daily_caps=daily_caps,
        nudge_limit_per_day=nudge_limit,
        allow_structuring=allow_structuring,
        allow_active_help=allow_active_help,
        allow_follow_up=allow_follow_up,
    )


def start_of_day_utc(now: Optional[datetime] = None) -> datetime:
    current = now or utcnow()
    return current.replace(hour=0, minute=0, second=0, microsecond=0)


def is_item_time_critical(
    item: UnifiedItem,
    now: Optional[datetime] = None,
    window_hours: int = DEFAULT_TIME_CRITICAL_HOURS,
) -> bool:
    current = now or utcnow()
    window_seconds = max(1, int(window_hours)) * 3600

    if item.type == UnifiedItemType.event:
        if not item.start_at:
            return False
        delta_seconds = (item.start_at - current).total_seconds()
        return -3600 <= delta_seconds <= window_seconds

    if item.type in {UnifiedItemType.task, UnifiedItemType.reminder}:
        if not item.due_at:
            return False
        delta_seconds = (item.due_at - current).total_seconds()
        return delta_seconds <= window_seconds

    return False


def split_dashboard_items_by_policy(
    scored_items: Sequence[Any],
    policy: SupportPolicy,
    now: Optional[datetime] = None,
    important_limit: int = 3,
    upcoming_limit: int = 20,
) -> Tuple[List[UnifiedItem], List[UnifiedItem]]:
    current = now or utcnow()
    if policy.level >= 2 and not policy.paused:
        important = [entry.item for entry in scored_items[:important_limit]]
        upcoming = [entry.item for entry in scored_items[important_limit : important_limit + upcoming_limit]]
        return important, upcoming

    critical_scored = [
        entry
        for entry in scored_items
        if is_item_time_critical(entry.item, now=current, window_hours=policy.time_critical_window_hours)
    ]
    important = [entry.item for entry in critical_scored[:important_limit]]

    if policy.level == 1 and not policy.paused:
        upcoming = [entry.item for entry in critical_scored[important_limit : important_limit + upcoming_limit]]
    else:
        upcoming = []
    return important, upcoming


def is_proposal_allowed_for_policy(
    proposal: Proposal,
    policy: SupportPolicy,
    item_by_id: Mapping[str, UnifiedItem],
    now: Optional[datetime] = None,
) -> bool:
    if policy.paused or policy.level == 0:
        return False

    if policy.level == 1:
        current = now or utcnow()
        for item_id in proposal.related_item_ids:
            item = item_by_id.get(item_id)
            if item and is_item_time_critical(
                item,
                now=current,
                window_hours=policy.time_critical_window_hours,
            ):
                return True
        return False

    if policy.level == 2:
        return proposal.proposal_type in {
            ProposalType.create_reminder,
            ProposalType.schedule_timeblock,
        }

    return True


def filter_proposals_for_policy(
    proposals: Iterable[Proposal],
    policy: SupportPolicy,
    item_by_id: Mapping[str, UnifiedItem],
    now: Optional[datetime] = None,
) -> List[Proposal]:
    current = now or utcnow()
    return [
        proposal
        for proposal in proposals
        if is_proposal_allowed_for_policy(proposal, policy=policy, item_by_id=item_by_id, now=current)
    ]


def adaptation_allowed(policy: SupportPolicy) -> bool:
    if policy.paused:
        return False
    return policy.adaptation_enabled


def follow_up_days_range_for_level(level: int) -> Tuple[int, int]:
    if level <= 1:
        return (3, 7)
    if level == 2:
        return (2, 7)
    return (1, 7)


def clamp_follow_up_days(value: int, policy: SupportPolicy) -> int:
    minimum, maximum = follow_up_days_range_for_level(policy.level)
    return max(minimum, min(maximum, int(value)))


def learning_setting_keys(settings: Mapping[str, Any]) -> List[str]:
    keys = set()
    for key in settings.keys():
        if key.startswith(LEARNING_KEY_PREFIX):
            keys.add(key)
    for key in ADAPTIVE_SETTING_KEYS:
        if key in settings:
            keys.add(key)
    return sorted(keys)
