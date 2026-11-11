from datetime import datetime, timezone

import pytest

from partner_validity import offer_deadline


@pytest.mark.parametrize(('raw', 'expected'), [
    ({'endDate': '31.10.2026'}, '2026-10-31T21:00:00+00:00'),
    ({'endDate': '31.12.2026'}, '2026-12-31T21:00:00+00:00'),
    ({'expirationLabel': 'Последний день'}, '2026-10-02T21:00:00+00:00'),
    ({'expirationLabel': 'ещё 5 дней'}, '2026-10-06T21:00:00+00:00'),
    ({'expirationLabel': 'До 5 октября'}, '2026-10-05T21:00:00+00:00'),
    ({'expirationLabel': 'До 30 сентября'}, '2026-09-30T21:00:00+00:00'),
    ({'expirationLabel': 'до 03.10.2026'}, '2026-10-03T21:00:00+00:00'),
    ({'endDate': '2026-10-03'}, '2026-10-03T21:00:00+00:00'),
    ({'endDate': '2026-10-03T14:00:00Z'}, '2026-10-03T14:00:00+00:00'),
    ({'expirationLabel': 'Пока действует акция'}, None),
])
def test_deadline(raw, expected):
    # Already October 2 in Moscow, although the file's UTC date is October 1.
    actual = offer_deadline(raw, datetime(2026, 10, 1, 22, tzinfo=timezone.utc))
    assert (actual.isoformat() if actual else None) == expected


@pytest.mark.parametrize(('label', 'expected'), [
    # Read on 20 December: January is next year, a recent date stays expired.
    ('До 15 января', '2027-01-15T21:00:00+00:00'),
    ('до 10.01', '2027-01-10T21:00:00+00:00'),
    ('До 10 декабря', '2026-12-10T21:00:00+00:00'),
    ('до 13 нояб.', '2026-11-13T21:00:00+00:00'),
])
def test_year_less_deadline_rolls_over_new_year(label, expected):
    actual = offer_deadline(
        {'expirationLabel': label}, datetime(2026, 12, 20, 9, tzinfo=timezone.utc),
    )
    assert actual.isoformat() == expected
