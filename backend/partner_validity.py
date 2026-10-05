"""Normalize bank deadlines to exclusive instants in Moscow time."""
import re
from datetime import datetime, timedelta, timezone

MOSCOW = timezone(timedelta(hours=3))
MONTHS = dict(zip(
    'января февраля марта апреля мая июня июля августа сентября октября ноября декабря'.split(),
    range(1, 13),
))


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
        match = re.search(r'до\s+(\d{1,2})[./](\d{1,2})(?:[./](\d{4}))?', label)
        if match:
            year, month, date = int(match[3] or anchor.year), int(match[2]), int(match[1])
        else:
            match = re.search(r'до\s+(\d{1,2})\s+([а-я]+)(?:\s+(\d{4}))?', label)
            if not match or match[2] not in MONTHS:
                return None
            year, month, date = int(match[3] or anchor.year), MONTHS[match[2]], int(match[1])
        try:
            end = datetime(year, month, date, tzinfo=MOSCOW) + timedelta(days=1)
        except ValueError:
            return None
    return end.astimezone(timezone.utc)
