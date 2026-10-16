"""Shared time boundaries: UTC evidence instants and Moscow cashback wall time."""

from datetime import datetime, timedelta, timezone

MOSCOW = timezone(timedelta(hours=3))


def utc_now():
    return datetime.now(timezone.utc)


def utc_naive_now():
    """UTC ORM defaults for historical timestamp-without-time-zone columns."""
    return utc_now().replace(tzinfo=None)


def as_utc(value):
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def iso_datetime(value):
    return as_utc(value).isoformat() if value is not None else None
