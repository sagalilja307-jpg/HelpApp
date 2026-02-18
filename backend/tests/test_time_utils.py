from datetime import datetime, timezone

from helpershelp.domain.value_objects.time_utils import (
    ensure_utc,
    format_iso8601,
    parse_iso_datetime,
)


def test_parse_iso_datetime_normalizes_offset_to_utc():
    parsed = parse_iso_datetime("2026-02-18T13:00:00+01:00")

    assert parsed == datetime(2026, 2, 18, 12, 0, tzinfo=timezone.utc)


def test_ensure_utc_assumes_utc_for_naive_input():
    normalized = ensure_utc(datetime(2026, 2, 18, 12, 0))

    assert normalized == datetime(2026, 2, 18, 12, 0, tzinfo=timezone.utc)


def test_format_iso8601_uses_explicit_timezone():
    rendered = format_iso8601(datetime(2026, 2, 18, 12, 0, tzinfo=timezone.utc))

    assert rendered == "2026-02-18T12:00:00Z"
