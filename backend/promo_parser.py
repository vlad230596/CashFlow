"""Best-effort extraction of promo codes, offers and expiring points.

The owner pastes an SMS, messenger message or banner text; the parser
pre-fills an editor that the user always reviews before saving, so every
field is optional and a wrong guess is cheaper than a missed one. Dates are
civil dates in the Moscow business calendar; `expires_at` is the last day
on which the offer still works (inclusive).
"""
import calendar
import re
from dataclasses import dataclass
from datetime import date, timedelta
from decimal import Decimal

from partner_validity import full_year, month_number, resolve_yearless

MAX_TEXT_LENGTH = 10000

_SPACES = re.compile(r'[     \t\r\f\v]')
_AMOUNT = r'(\d{1,3}(?:[   ]\d{3})+|\d+)(?:[.,](\d{1,2}))?'

# --- Dates -----------------------------------------------------------------

_DAY_MONTH = re.compile(
    r'(?<![\d.])(\d{1,2})(?:-?го)?\s+([а-я]{3,8}\.?)'
    r'(?:\s+(\d{4})(?:\s*(?:г\.|года|г\b))?)?'
)
_NUMERIC_DATE = re.compile(r'(?<![\d.,])(\d{1,2})[./](\d{1,2})(?:[./](\d{4}|\d{2}))?(?![\d.,]\d)')
_ISO_DATE = re.compile(r'(?<!\d)(\d{4})-(\d{2})-(\d{2})(?!\d)')
_BARE_RANGE = re.compile(r'\bс\s+(\d{1,2})\s*(?:по|до|-|–|—)\s*(?=\d{1,2}[\s./])')

_START_PREFIX = re.compile(r'(?:\bс|\bсо|\bначиная\s+с|\bот)\s*$')
_UNTIL_PREFIX = re.compile(r'(?:\bдо|\bпо|\buntil|\btill)\s*$')
_EXPIRY_WORDS = (
    r'сгор\w*|истека\w*|истеч\w*|заканчива\w*|законч\w*|прекрат\w*|'
    r'действ\w*|годе?н\w*|срок\w*|успе\w*|акту\w*'
)
_EXPIRY_NEAR = re.compile(rf'(?:{_EXPIRY_WORDS})(?:[^\d.!?\n]|\.(?!\s)){{0,40}}$')
_CREDIT_NEAR = re.compile(r'(?:начисл\w*|зачисл\w*|получ\w*|прид\w*|поступ\w*)[^\d!?\n]{0,30}$')
_RANGE_GAP = re.compile(r'^\s*(?:по|до|-|–|—)\s*$')

_RELATIVE_DAYS = re.compile(
    r'(?:осталось|остается|остаётся|еще|ещё|через|в\s+течение)\s+(\d{1,3})\s+'
    r'(?:дн\.|день|дня|дней)'
)
_TODAY = re.compile(
    r'только\s+сегодня|до\s+конца\s+(?:сегодняшнего\s+)?дня|последний\s+день|'
    r'(?:сгор\w*|истека\w*|действует|заканчива\w*)\s+сегодня|'
    r'сегодня\s+(?:сгор\w*|истека\w*|заканчива\w*|последний)'
)
_TOMORROW = re.compile(
    r'(?:до|сгор\w*|истека\w*|заканчива\w*|действует)\s+(?:до\s+)?завтра|'
    r'завтра\s+(?:сгор\w*|истека\w*|заканчива\w*)'
)
_END_OF = re.compile(
    r'до\s+конца\s+(?:этого\s+|текущего\s+|этой\s+|текущей\s+)?'
    r'(месяца|недели|года|[а-я]{3,8})'
)


@dataclass
class _DateToken:
    start: int
    end: int
    day: int
    month: int
    year: int | None
    role: str = 'neutral'  # start | end | credit | neutral
    score: int = 0
    phrase_start: int | None = None


def _date_tokens(low):
    tokens = []
    for match in _DAY_MONTH.finditer(low):
        month = month_number(match[2])
        if month is None:
            continue
        tokens.append(_DateToken(
            match.start(), match.end(), int(match[1]), month,
            full_year(match[3]) if match[3] else None,
        ))
    for match in _NUMERIC_DATE.finditer(low):
        day, month = int(match[1]), int(match[2])
        if not (1 <= day <= 31 and 1 <= month <= 12):
            continue
        tail = low[match.end():match.end() + 6]
        if re.match(r'\s*(?:%|₽|руб|р\.|rub|бал|бон|шт|кг|км|ч\b)', tail):
            continue  # an amount such as "1.5 %" or "2.50 ₽"
        if match[3] is None and not re.search(r'[./]', match[0]):
            continue
        tokens.append(_DateToken(
            match.start(), match.end(), day, month,
            full_year(match[3]) if match[3] else None,
        ))
    for match in _ISO_DATE.finditer(low):
        tokens.append(_DateToken(
            match.start(), match.end(), int(match[3]), int(match[2]), int(match[1]),
        ))
    for match in _BARE_RANGE.finditer(low):
        following = next(
            (token for token in tokens if token.start == match.end()), None,
        )
        if following is not None:
            tokens.append(_DateToken(
                match.start(1), match.end(1), int(match[1]), following.month,
                following.year, role='start', phrase_start=match.start(),
            ))
    tokens.sort(key=lambda token: token.start)
    # Drop tokens nested in another one ("13.11" inside an ISO date etc.).
    result = []
    for token in tokens:
        if result and token.start < result[-1].end:
            continue
        result.append(token)
    return result


def _sentence_prefix(low, position, limit=60):
    prefix = low[max(0, position - limit):position]
    cut = max(prefix.rfind('!'), prefix.rfind('?'), prefix.rfind('\n'), prefix.rfind('. '))
    return prefix[cut + 1:] if cut >= 0 else prefix


def _classify(low, tokens):
    for index, token in enumerate(tokens):
        if token.role == 'start':
            continue
        prefix = _sentence_prefix(low, token.start)
        previous = tokens[index - 1] if index else None
        gap = low[previous.end:token.start] if previous else None
        if previous is not None and gap is not None and _RANGE_GAP.match(gap) and (
            previous.role == 'start' or gap.strip() in {'-', '–', '—'}
        ):
            previous.role = 'start'
            token.role, token.score = 'end', 3
            token.phrase_start = previous.phrase_start or previous.start
            continue
        if _START_PREFIX.search(prefix):
            token.role = 'start'
            token.phrase_start = token.start - len(_START_PREFIX.search(prefix)[0])
            continue
        until = _UNTIL_PREFIX.search(prefix)
        near = _EXPIRY_NEAR.search(prefix)
        credit = _CREDIT_NEAR.search(prefix)
        if until:
            token.role = 'end'
            token.score = 1 if credit and not near else 3
            token.phrase_start = token.start - len(near[0] if near else until[0])
        elif near:
            token.role, token.score = 'end', 2
            token.phrase_start = token.start - len(near[0])
        elif credit:
            token.role = 'credit'


def _resolve_token(token, today, *, anchor=None):
    """Calendar date of a token. End dates without a year roll forward."""
    if token.year is not None:
        try:
            return date(token.year, token.month, token.day)
        except ValueError:
            return None
    if anchor is not None:
        # A range start without a year shares the end's year.
        try:
            candidate = date(anchor.year, token.month, token.day)
        except ValueError:
            return None
        if candidate > anchor:
            try:
                candidate = date(anchor.year - 1, token.month, token.day)
            except ValueError:
                return None
        return candidate
    grace = 0 if token.role == 'end' else 183
    return resolve_yearless(token.day, token.month, today, past_grace_days=grace)


def _relative_candidates(low, today):
    """(date, score, start, end) for phrases like «осталось 3 дня»."""
    found = []
    for match in _RELATIVE_DAYS.finditer(low):
        days = int(match[1])
        if days > 0:
            found.append((today + timedelta(days=days - 1), 2, match.start(), match.end()))
    for match in _TODAY.finditer(low):
        found.append((today, 2, match.start(), match.end()))
    for match in _TOMORROW.finditer(low):
        found.append((today + timedelta(days=1), 2, match.start(), match.end()))
    for match in _END_OF.finditer(low):
        word = match[1]
        if word == 'месяца':
            value = date(today.year, today.month,
                         calendar.monthrange(today.year, today.month)[1])
        elif word == 'недели':
            value = today + timedelta(days=6 - today.weekday())
        elif word == 'года':
            value = date(today.year, 12, 31)
        else:
            month = month_number(word)
            if month is None:
                continue
            last = calendar.monthrange(today.year, month)[1]
            value = resolve_yearless(last, month, today)
            if value is not None and value.day != calendar.monthrange(value.year, month)[1]:
                value = value.replace(day=calendar.monthrange(value.year, month)[1])
        if value is not None:
            found.append((value, 3, match.start(), match.end()))
    return found


def _dates(text, low, today):
    tokens = _date_tokens(low)
    _classify(low, tokens)
    candidates = []  # (score, date, phrase_start, phrase_end, confidence)
    for token in tokens:
        if token.role != 'end':
            continue
        value = _resolve_token(token, today)
        if value is not None:
            candidates.append((
                token.score, value, token.phrase_start or token.start, token.end,
                'explicit',
            ))
    for value, score, start, end in _relative_candidates(low, today):
        candidates.append((score, value, start, end, 'relative'))
    if not candidates:
        neutral = []
        for token in tokens:
            if token.role != 'neutral':
                continue
            value = _resolve_token(token, today)
            if value is not None and value >= today:
                neutral.append((0, value, token.start, token.end, 'guessed'))
        if len(neutral) == 1:
            candidates = neutral

    expires_at = phrase = confidence = None
    if candidates:
        best = max(item[0] for item in candidates)
        # Several equally strong deadlines: remind about the earliest one.
        score, expires_at, start, end, confidence = min(
            (item for item in candidates if item[0] == best), key=lambda item: item[1],
        )
        phrase = ' '.join(text[start:end].split()).rstrip('.,;')

    starts_at = None
    for token in tokens:
        if token.role != 'start':
            continue
        anchor = expires_at if expires_at is not None and token.year is None else None
        value = _resolve_token(token, today, anchor=anchor)
        if value is not None and (expires_at is None or value <= expires_at):
            starts_at = value
            break
    return starts_at, expires_at, phrase, confidence


# --- Promo codes -------------------------------------------------------------

_CODE_KEYWORD = re.compile(
    r'(промо[\s-]?код\w*|купон\w*|по\s+коду|код(?:у|ом)?|promo\s*code|coupon|code)'
    r'(?![\w-])',
    re.IGNORECASE,
)
_CODE_VALUE = re.compile(
    r'[\s:—–\-]*(?:на\s+скидку\s+)?([«"“„\'`]?)'
    r'([A-Za-zА-ЯЁа-яё0-9][A-Za-zА-ЯЁа-яё0-9_\-]{1,39})'
)
_OTP_CONTEXT = re.compile(
    r'никому\s+не\s+(?:сообщайте|говорите)|подтвержд\w*|одноразов\w*|для\s+входа|пароль',
    re.IGNORECASE,
)
_STANDALONE_CODE = re.compile(r'(?<![\w-])([A-ZА-ЯЁ0-9][A-ZА-ЯЁ0-9_-]{3,19})(?![\w-])')
_NOT_CODES = {'RUB', 'РУБ', 'USD', 'EUR', 'SMS', 'СМС', 'NFC', 'QR', 'ПИН', 'PIN', 'MCC'}


def _has_letter(value):
    return any(char.isalpha() for char in value)


def _has_digit(value):
    return any(char.isdigit() for char in value)


def _promo_code(text):
    otp = bool(_OTP_CONTEXT.search(text))
    for keyword in _CODE_KEYWORD.finditer(text):
        plain_code = keyword[1].lower().startswith(('код', 'code', 'по коду'))
        if otp and plain_code:
            continue
        value = _CODE_VALUE.match(text, keyword.end())
        if not value:
            continue
        quoted = bool(value[1])
        token = value[2].strip('-_')
        if len(token) < 3 or token.upper() in _NOT_CODES:
            continue
        if not _has_letter(token):
            if plain_code and not quoted:
                continue  # bare digits after «код» are usually an SMS code
            return token
        if quoted or token == token.upper() or (_has_letter(token) and _has_digit(token)):
            return token
    if otp:
        return None
    for match in _STANDALONE_CODE.finditer(text):
        token = match[1].strip('-_')
        if token in _NOT_CODES or not (_has_letter(token) and _has_digit(token)):
            continue
        if re.fullmatch(r'\d+(?:Р|P|РУБ|RUB|ГБ|МБ|ТБ|GB|MB|TB|МИН|ШТ|K|К|Х|X)', token):
            continue
        return token
    return None


# --- Points and discounts ------------------------------------------------------

_POINTS = re.compile(
    _AMOUNT + r'\s*(бонусн\w+\s+рубл\w+|баллов|балла|балл|бонусов|бонуса|бонус|'
    r'милей|мили|миль|плюсов|спасибо)(?![а-я])'
)
_POINTS_CONTEXT = re.compile(
    r'начисл\w*|зачисл\w*|сгор\w*|сгоря\w*|баланс\w*|на\s+счет\w*|на\s+счёт\w*|'
    r'доступно|накоплен\w*|у\s+вас|ваши|ваших|потрат\w*|списат\w*|подар\w*|дарим'
)
_BURN_OR_CREDIT = re.compile(
    r'сгор\w*|начисл\w*|зачисл\w*|баланс\w*|накоплен\w*|на\s+сч[её]т\w*'
)
_DISCOUNT_PATTERNS = (
    re.compile(
        r'скидк\w*\s+(?:в\s+размере\s+)?(до\s+)?(\d+(?:[.,]\d+)?\s*%|' + _AMOUNT
        + r'\s*(?:₽|руб\w*\.?|р\.))'
    ),
    re.compile(r'(\d+(?:[.,]\d+)?)\s*%\s*(скидк\w*|кешб[эе]к\w*|кэшб[эе]к\w*|cashback)'),
    re.compile(r'(кешб[эе]к\w*|кэшб[эе]к\w*)\s+(до\s+)?(\d+(?:[.,]\d+)?\s*%)'),
    re.compile(r'(?<![\w\d])[-−–]\s?(\d+(?:[.,]\d+)?)\s*%'),
    re.compile(r'(?<![\w\d])[-−–]\s?' + _AMOUNT + r'\s*(?:₽|руб)'),
    re.compile(r'бесплатн\w+\s+доставк\w*'),
)


def _amount(integer, fraction):
    value = Decimal(re.sub(r'\s', '', integer))
    if fraction:
        value += Decimal(f'0.{fraction}')
    return value


def _format_amount(value):
    if value == value.to_integral_value():
        return f'{int(value):,}'.replace(',', ' ')
    return f'{value:.2f}'.replace('.', ',')


def _points(low):
    best = None
    for match in _POINTS.finditer(low):
        amount = _amount(match[1], match[2])
        if amount <= 0:
            continue
        sentence = _sentence_prefix(low, match.start(), limit=80) + low[
            match.start():match.end() + 40
        ]
        score = 1 if _POINTS_CONTEXT.search(sentence) else 0
        if best is None or score > best[0]:
            best = (score, amount, ' '.join(match[3].split()))
    return (best[1], best[2]) if best else (None, None)


def _discount(low):
    found = []
    for index, pattern in enumerate(_DISCOUNT_PATTERNS):
        match = pattern.search(low)
        if not match:
            continue
        if index == 0:
            prefix = 'скидка до ' if match[1] else 'скидка '
            value = prefix + ' '.join(match[2].split())
        elif index == 1:
            word = 'скидка' if match[2].startswith('скид') else 'кешбэк'
            value = f'{match[1]}% {word}'
        elif index == 2:
            value = 'кешбэк ' + ('до ' if match[2] else '') + ' '.join(match[3].split())
        elif index == 3:
            value = f'−{match[1]}%'
        elif index == 4:
            value = f'−{_format_amount(_amount(match[1], match[2]))} ₽'
        else:
            value = 'бесплатная доставка'
        value = re.sub(r'(\d)\s+%', r'\1%', value)
        value = re.sub(r'\s*(?:руб\w*\.?|р\.)$', ' ₽', value)
        found.append((match.start(), value))
    return min(found)[1] if found else None


# --- Merchant ------------------------------------------------------------------

KNOWN_MERCHANTS = (
    ('Ozon', r'ozon|озон'),
    ('Wildberries', r'wildberries|вайлдберриз|\bwb\b'),
    ('Яндекс Маркет', r'яндекс\s*маркет\w*|yandex\s*market'),
    ('Яндекс Еда', r'яндекс\s*ед[аыуе]'),
    ('Яндекс Go', r'яндекс\s*go|яндекс\s*такси'),
    ('Яндекс Плюс', r'яндекс\s*плюс\w*'),
    ('Кинопоиск', r'кинопоиск\w*'),
    ('Самокат', r'самокат\w*'),
    ('Пятёрочка', r'пят[её]рочк\w*'),
    ('Перекрёсток', r'перекр[её]ст\w*'),
    ('Магнит', r'магнит\b|магнита\b|магните\b'),
    ('Лента', r'\bленты?\b|\bленте\b'),
    ('ВкусВилл', r'вкусвилл\w*'),
    ('Купер', r'купер\w*|сбермаркет\w*'),
    ('Мегамаркет', r'мегамаркет\w*'),
    ('Ламода', r'lamoda|ламод\w*'),
    ('М.Видео', r'м\.?\s?видео|mvideo'),
    ('Эльдорадо', r'эльдорадо'),
    ('Ситилинк', r'ситилинк\w*|citilink'),
    ('DNS', r'\bdns\b'),
    ('Спортмастер', r'спортмастер\w*'),
    ('Золотое Яблоко', r'золото[ей]\s+яблок\w*'),
    ('Летуаль', r'летуал\w*|l.?etoile'),
    ('Додо Пицца', r'додо\s*пицц\w*|dodo'),
    ('Delivery Club', r'delivery\s*club'),
    ('AliExpress', r'aliexpress|алиэкспресс\w*'),
    ('Лукойл', r'лукойл\w*'),
    ('Аптека.ру', r'аптека\.ру|apteka\.ru'),
    ('СберСпасибо', r'сбер\s*спасибо|бонус\w*\s+спасибо'),
    ('Т-Банк', r'т-банк\w*|тинькофф\w*|t-bank'),
    ('Альфа-Банк', r'альфа[\s-]?банк\w*'),
    ('ВТБ', r'\bвтб\b'),
    ('Аэрофлот', r'аэрофлот\w*'),
    ('РЖД', r'\bржд\b'),
    ('Литрес', r'литрес\w*|litres'),
    ('Иви', r'\bivi\b|\bиви\b'),
    ('Okko', r'\bokko\b'),
)
_GENERIC_SENDERS = {
    'промокод', 'внимание', 'важно', 'акция', 'код', 'ваш', 'вам', 'для вас',
    'новость', 'напоминание', 'уведомление', 'сообщение', 'подарок', 'скидка',
    'баллы', 'бонусы', 'привет', 'здравствуйте', 'спешите', 'только сегодня',
}
_SENDER = re.compile(
    r'^\s*[\[(]?([A-Za-zА-ЯЁа-яё0-9][A-Za-zА-ЯЁа-яё0-9 .&\'-]{1,28}?)[\])]?\s*[:|]\s'
)
_QUOTED_MERCHANT = re.compile(
    r'(?:\bв|\bво|\bот|\bна|магазин\w*|сервис\w*|приложени\w*|сети|партн[её]р\w*)\s+'
    r'«([^»]{2,40})»',
    re.IGNORECASE,
)
_PLACE_MERCHANT = re.compile(
    r'(?:в\s+магазин\w*|в\s+приложени\w*|на\s+сайте|в\s+сервисе|в\s+сети|от)\s+'
    r'([A-ZА-ЯЁ][\w.&-]+(?:\s+[A-ZА-ЯЁ][\w.&-]+)?)'
)


def _merchant(text, low, code):
    first_line = text.strip().split('\n', 1)[0]
    sender = _SENDER.match(first_line)
    if sender:
        name = sender[1].strip(' .-')
        if (
            name.lower() not in _GENERIC_SENDERS
            and name != code
            and _has_letter(name)
            and len(name.split()) <= 3
        ):
            known = _known_merchant(name.lower())
            return known or name
    known = _known_merchant(low)
    if known:
        return known
    for pattern in (_QUOTED_MERCHANT, _PLACE_MERCHANT):
        for match in pattern.finditer(text):
            name = match[1].strip(' .')
            if name != code and name.lower() not in _GENERIC_SENDERS:
                return name
    return None


def _known_merchant(low):
    best = None
    for name, pattern in KNOWN_MERCHANTS:
        match = re.search(pattern, low)
        if match and (best is None or match.start() < best[0]):
            best = (match.start(), name)
    return best[1] if best else None


# --- Conditions and title ------------------------------------------------------

_CONDITIONS = re.compile(
    r'при\s+заказе|при\s+покупке|при\s+оплате|заказ\w*\s+от\s+\d|покупк\w*\s+от\s+\d|'
    r'минимальн\w*|на\s+первый|перв\w+\s+заказ|не\s+суммир\w*|однократ\w*|'
    r'один\s+раз|только\s+для|для\s+новых|кроме\s|не\s+действует|до\s+\d+\s*%\s+от'
)


def _sentences(text):
    parts = re.split(r'(?<=[.!?])\s+|\n+', text)
    return [' '.join(part.split()) for part in parts if part.strip()]


def _conditions(text):
    selected = []
    for sentence in _sentences(text):
        if _CONDITIONS.search(sentence.lower().replace('ё', 'е')):
            selected.append(sentence)
        if len(selected) == 2:
            break
    value = ' '.join(selected)
    return value[:500] or None


def _title(kind, merchant, discount, points_amount, points_unit, code, text):
    if kind == 'points' and points_amount is not None:
        points = f'{_format_amount(points_amount)} {points_unit}'
        return f'{merchant}: {points}' if merchant else points.capitalize()
    if merchant and discount:
        return f'{merchant}: {discount}'
    if merchant:
        return f'{merchant}: промокод' if code else merchant
    if discount:
        return discount[0].upper() + discount[1:]
    sentences = _sentences(text)
    if not sentences:
        return None
    first = sentences[0]
    return first if len(first) <= 80 else first[:79].rstrip() + '…'


# --- Entry point ---------------------------------------------------------------

def _normalize(text):
    text = _SPACES.sub(' ', text.replace('\r\n', '\n'))
    # Same length as `text`, so match positions map back to the original.
    low = ''.join(
        lowered if len(lowered := char.lower()) == 1 else char for char in text
    ).replace('ё', 'е')
    return text, low


def parse_promo_text(text, today):
    """Fields recognized in `text`; None for anything not found."""
    text, low = _normalize(text[:MAX_TEXT_LENGTH])
    starts_at, expires_at, phrase, confidence = _dates(text, low, today)
    code = _promo_code(text)
    points_amount, points_unit = _points(low)
    discount = _discount(low)
    merchant = _merchant(text, low, code)

    kind = 'promo'
    if points_amount is not None and (
        code is None or (_BURN_OR_CREDIT.search(low) and not discount)
    ):
        kind = 'points'
    elif (
        points_amount is None and code is None and discount is None
        and re.search(r'балл|бонус|мил[иья]', low)
    ):
        kind = 'points'  # «Ваши бонусы сгорят 31 декабря» without an amount
    if kind == 'promo' and points_amount is not None:
        if discount is None:
            discount = f'{_format_amount(points_amount)} {points_unit}'
        points_amount = points_unit = None

    result = {
        'kind': kind,
        'title': _title(kind, merchant, discount, points_amount, points_unit, code, text),
        'merchant': merchant,
        'promo_code': code if kind == 'promo' else None,
        'discount': discount if kind == 'promo' else None,
        'points_amount': (
            f'{points_amount:.2f}' if points_amount is not None else None
        ),
        'points_unit': points_unit,
        'description': _conditions(text),
        'starts_at': starts_at.isoformat() if starts_at else None,
        'expires_at': expires_at.isoformat() if expires_at else None,
        'expiry_phrase': phrase,
        'expires_at_confidence': confidence,
    }
    result['found'] = [
        name for name in (
            'expires_at', 'starts_at', 'promo_code', 'merchant', 'discount',
            'points_amount', 'description',
        )
        if result[name] is not None
    ]
    return result
