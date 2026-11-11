"""Normalize bank deadlines to exclusive instants in Moscow time.

The Russian calendar-date helpers here are shared with `promo_parser`.
"""
import re
from datetime import date, datetime, timedelta, timezone

MOSCOW = timezone(timedelta(hours=3))
MONTHS = dict(zip(
    'января февраля марта апреля мая июня июля августа сентября октября ноября декабря'.split(),
    range(1, 13),
))
# Genitive month name or a common abbreviation ("13 нояб.", "1 дек").
MONTH_STEMS = {
    'янв': 1, 'фев': 2, 'мар': 3, 'апр': 4, 'мая': 5, 'май': 5, 'июн': 6,
    'июл': 7, 'авг': 8, 'сен': 9, 'окт': 10, 'ноя': 11, 'дек': 12,
}
# How far in the past a year-less bank label may lie and still mean this year:
# "до 30 сентября" read on 2 October is an expired offer, while "до 15 января"
# read on 20 December is next January.
OFFER_PAST_GRACE_DAYS = 183


def month_number(word):
    """Month of a genitive name or abbreviation; None for other words."""
    word = word.lower().replace('ё', 'е').rstrip('.')
    if word in MONTHS:
        return MONTHS[word]
    if len(word) >= 3 and word[:3] in MONTH_STEMS:
        stem = word[:3]
        # Reject unrelated words that merely share a stem ("марки", "декор").
        full = next(name for name, number in MONTHS.items()
                    if number == MONTH_STEMS[stem])
        if full.startswith(word) or word in {'май', 'мая', 'сент'}:
            return MONTH_STEMS[stem]
    return None


def full_year(value):
    """Four-digit year from a 2- or 4-digit token."""
    year = int(value)
    return year + 2000 if year < 100 else year


def resolve_yearless(day, month, today, *, past_grace_days=0):
    """Calendar date for a day/month without a year, relative to `today`.

    The date is in today's year unless it lies more than `past_grace_days`
    in the past, in which case it is next year. Returns None for impossible
    dates such as 30 February.
    """
    try:
        candidate = date(today.year, month, day)
    except ValueError:
        if month == 2 and day == 29:
            # 29 February without a year: the next leap year that fits.
            for year in range(today.year + 1, today.year + 5):
                try:
                    return date(year, 2, 29)
                except ValueError:
                    continue
        return None
    if (today - candidate).days > past_grace_days:
        try:
            return date(today.year + 1, month, day)
        except ValueError:
            return None
    return candidate


def parse_offer_date(value):
    """Accept the extension's calendar dates as well as ISO timestamps."""
    if re.fullmatch(r'\d{2}\.\d{2}\.\d{4}', value):
        return datetime.strptime(value, '%d.%m.%Y'), True
    return (
        datetime.fromisoformat(value.replace('Z', '+00:00')),
        bool(re.fullmatch(r'\d{4}-\d{2}-\d{2}', value)),
    )


def offer_deadline(raw, generated_at):
    anchor = generated_at.astimezone(MOSCOW)
    day = datetime(anchor.year, anchor.month, anchor.day, tzinfo=MOSCOW)
    explicit = raw.get('endDate')
    if explicit:
        parsed, calendar_date = parse_offer_date(explicit)
        if calendar_date:
            parsed = parsed.replace(tzinfo=MOSCOW) + timedelta(days=1)
        elif parsed.tzinfo is None:
            parsed = parsed.replace(tzinfo=MOSCOW)
        return parsed.astimezone(timezone.utc)
    label = str(raw.get('validityLabel') or raw.get('expirationLabel') or '')
    label = label.lower().replace('ё', 'е')
    if re.search(r'последний день|до конца дня|\bсегодня\b', label):
        end = day + timedelta(days=1)
    elif re.search(r'\bзавтра\b', label):
        end = day + timedelta(days=2)
    elif match := re.search(r'(?:(?:еще|осталось|через)\s+)?\b(\d+)\s+д(?:ень|ня|ней)\b', label):
        end = day + timedelta(days=max(1, int(match[1])))
    else:
        match = re.search(r'до\s+(\d{1,2})[./](\d{1,2})(?:[./](\d{2}|\d{4}))?\b', label)
        if match:
            year, month, date_ = match[3], int(match[2]), int(match[1])
        else:
            match = re.search(r'до\s+(\d{1,2})\s+([а-я]+\.?)(?:\s+(\d{4}))?', label)
            month = month_number(match[2]) if match else None
            if month is None:
                return None
            year, date_ = match[3], int(match[1])
        if year:
            try:
                resolved = date(full_year(year), month, date_)
            except ValueError:
                return None
        else:
            resolved = resolve_yearless(
                date_, month, day.date(), past_grace_days=OFFER_PAST_GRACE_DAYS,
            )
            if resolved is None:
                return None
        end = datetime(resolved.year, resolved.month, resolved.day, tzinfo=MOSCOW)
        end += timedelta(days=1)
    return end.astimezone(timezone.utc)
