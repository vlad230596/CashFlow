"""Anchored due-date schedules for planned payments; pure date math, no ORM.

A recurring payment is anchored to a reference due date. Every occurrence is
computed from the anchor (never from the previous occurrence), so month-end
anchors do not drift: anchor 31 Jan -> 28 Feb -> 31 Mar -> 30 Apr.
"""

import calendar
from datetime import date, timedelta

INTERVAL_UNITS = ('day', 'week', 'month', 'year')


def add_months(anchor, months):
    """Anchor plus whole months, clamping the anchor day to the month length."""
    month_index = anchor.month - 1 + months
    year = anchor.year + month_index // 12
    month = month_index % 12 + 1
    day = min(anchor.day, calendar.monthrange(year, month)[1])
    return date(year, month, day)


def occurrence(anchor, count, unit, index):
    """The index-th due date (index 0 is the anchor itself)."""
    if index < 0:
        raise ValueError('index must not be negative')
    if unit == 'day':
        return anchor + timedelta(days=count * index)
    if unit == 'week':
        return anchor + timedelta(weeks=count * index)
    if unit == 'month':
        return add_months(anchor, count * index)
    if unit == 'year':
        return add_months(anchor, 12 * count * index)
    raise ValueError(f'unsupported interval unit: {unit}')


def _index_not_after(anchor, count, unit, value):
    """A lower bound index whose occurrence is <= value (value >= anchor)."""
    if unit in ('day', 'week'):
        step = count * (7 if unit == 'week' else 1)
        return (value - anchor).days // step
    step_months = count * (12 if unit == 'year' else 1)
    months_between = (value.year - anchor.year) * 12 + value.month - anchor.month
    # The occurrence `months_between // step` months later lies in a month
    # before or equal to value's month; one step earlier is always <= value.
    return max(0, months_between // step_months - 1)


def next_occurrence_after(anchor, count, unit, after):
    """Smallest occurrence strictly later than `after`."""
    if after < anchor:
        return anchor
    index = _index_not_after(anchor, count, unit, after)
    candidate = occurrence(anchor, count, unit, index)
    while candidate <= after:
        index += 1
        candidate = occurrence(anchor, count, unit, index)
    return candidate


def is_occurrence(anchor, count, unit, value):
    if value < anchor:
        return False
    return next_occurrence_after(anchor, count, unit, value - timedelta(days=1)) == value


def occurrences_between(anchor, count, unit, start, end, *, limit=1000):
    """Occurrences d with start <= d <= end, at most `limit` items."""
    result = []
    current = next_occurrence_after(anchor, count, unit, start - timedelta(days=1))
    while current <= end and len(result) < limit:
        result.append(current)
        current = next_occurrence_after(anchor, count, unit, current)
    return result
