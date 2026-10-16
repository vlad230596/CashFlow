"""Stable integration identities, independent of display names and chosen icons."""

import re

BANK_IMPORT_NAMES = {
    "tbank": "Т-Банк",
    "yandex": "Яндекс",
    "alfa": "Альфа",
    "sber": "Сбер",
    "ozon": "Озон",
    "vtb": "ВТБ",
}
BANK_ALIASES = {
    "tbank": ("Т-Банк", "Тинькофф", "Тинькофф Банк", "T-Bank"),
    "alfa": ("Альфа", "Альфа-Банк", "Alfa Bank"),
    "vtb": ("ВТБ", "VTB"),
    "sber": ("Сбер", "Сбербанк", "Сбер Банк", "Sber"),
    "yandex": (
        "Яндекс",
        "Яндекс Банк",
        "Яндекс-Банк",
        "Яндекс Пэй",
        "Яндекс Pay",
        "Yandex Bank",
        "Yandex Pay",
    ),
    "ozon": ("Озон", "Озон Банк", "Ozon", "Ozon Банк", "Ozon Bank"),
}


def normalized_bank_name(value):
    return re.sub(r"[^a-zа-яё0-9]", "", str(value).lower())


def bank_key_for_name(value):
    name = normalized_bank_name(value)
    return next(
        (
            key
            for key, aliases in BANK_ALIASES.items()
            if name in {normalized_bank_name(alias) for alias in aliases}
        ),
        None,
    )


def validated_bank_key(value):
    if value is None:
        return None
    if not isinstance(value, str) or value not in BANK_IMPORT_NAMES:
        raise ValueError("Unsupported bank_key")
    return value
