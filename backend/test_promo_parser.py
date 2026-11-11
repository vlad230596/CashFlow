"""Parser cases use invented messages modelled on real SMS/messenger offers."""
from datetime import date

import pytest

from promo_parser import parse_promo_text

TODAY = date(2026, 11, 11)  # Wednesday


def parse(text, today=TODAY):
    return parse_promo_text(text, today)


def test_marketplace_sms_with_code_discount_conditions_and_deadline():
    result = parse(
        'OZON: Дарим промокод OZON500 на скидку 500 ₽ при заказе от 3000 ₽. '
        'Действует до 30 ноября.'
    )
    assert result['kind'] == 'promo'
    assert result['merchant'] == 'Ozon'
    assert result['promo_code'] == 'OZON500'
    assert result['discount'] == 'скидка 500 ₽'
    assert result['expires_at'] == '2026-11-30'
    assert result['expiry_phrase'] == 'Действует до 30 ноября'
    assert result['expires_at_confidence'] == 'explicit'
    assert 'при заказе от 3000 ₽' in result['description']
    assert result['title'] == 'Ozon: скидка 500 ₽'
    assert {'expires_at', 'promo_code', 'merchant', 'discount'} <= set(result['found'])


def test_points_credit_with_burn_date():
    result = parse(
        'Пятёрочка: на вашу карту начислено 300 баллов. '
        'Баллы сгорят 15 декабря, успейте потратить!'
    )
    assert result['kind'] == 'points'
    assert result['merchant'] == 'Пятёрочка'
    assert result['points_amount'] == '300.00'
    assert result['points_unit'] == 'баллов'
    assert result['expires_at'] == '2026-12-15'
    assert result['promo_code'] is None
    assert result['title'] == 'Пятёрочка: 300 баллов'


@pytest.mark.parametrize(('text', 'expected'), [
    ('Скидка 20% на всё по промокоду AUTUMN20 до 13.11', '2026-11-13'),
    ('Промокод SALE10 действует до 10 ноября', '2027-11-10'),  # already past
    ('Промокод SALE10 действует до 11 ноября', '2026-11-11'),  # today
    ('Код ZIMA-2026, срок действия до 2026-12-31', '2026-12-31'),
    ('Скидка по коду NY27 до 05.01.27', '2027-01-05'),
    ('Предложение действительно по 30.11.2026 включительно', '2026-11-30'),
    ('Успейте до 13 нояб. — код FAST13', '2026-11-13'),
    ('Скидка 15% до 1 января по коду NEWYEAR', '2027-01-01'),
    ('Акция действует до 30-го ноября', '2026-11-30'),
    ('Распродажа до 29 февраля', '2028-02-29'),
    ('Предложение действует до конца месяца', '2026-11-30'),
    ('Скидка действует до конца недели', '2026-11-15'),
    ('Действует до конца года, код YEAR26', '2026-12-31'),
    ('Скидка до конца декабря по коду DEC', '2026-12-31'),
    ('Осталось 3 дня, чтобы потратить 1 250 бонусов', '2026-11-13'),
    ('Яндекс Плюс: 500 баллов Плюса сгорят через 5 дней', '2026-11-15'),
    ('Ещё 1 день: скидка 10%', '2026-11-11'),
    ('Только сегодня! −30% на всё в Ламоде по коду LAMODA30', '2026-11-11'),
    ('Ваши бонусы сгорают завтра', '2026-11-12'),
    ('Ваш промокод на скидку 15%: «ЛЕТО15». Срок действия — 31.12.2026', '2026-12-31'),
    ('Баллы сгорят 15.12.2026 в 23:59', '2026-12-15'),
])
def test_expiry_dates(text, expected):
    assert parse(text)['expires_at'] == expected


def test_relative_and_explicit_deadlines_resolve_against_moscow_today():
    result = parse('Акция до 10 января', today=date(2026, 12, 20))
    assert result['expires_at'] == '2027-01-10'


def test_range_gives_start_and_end():
    result = parse('Акция с 1 по 30 ноября: кешбэк 10% в Ленте')
    assert result['starts_at'] == '2026-11-01'
    assert result['expires_at'] == '2026-11-30'
    assert result['expiry_phrase'] == 'с 1 по 30 ноября'
    assert result['discount'] == 'кешбэк 10%'
    assert result['merchant'] == 'Лента'


def test_numeric_range_and_range_across_new_year():
    result = parse('Скидки 13.11–20.11 по коду BLACK')
    assert (result['starts_at'], result['expires_at']) == ('2026-11-13', '2026-11-20')
    result = parse('Праздничная акция с 25 декабря по 10 января')
    assert (result['starts_at'], result['expires_at']) == ('2026-12-25', '2027-01-10')


def test_start_only_is_not_an_expiry():
    result = parse('Скидка 10% на кофе с 1 декабря. Промокод COFFEE')
    assert result['starts_at'] == '2026-12-01'
    assert result['expires_at'] is None


def test_crediting_date_does_not_win_over_the_offer_deadline():
    result = parse(
        'Промокод KUPON действует до 30.11. Баллы начислим до 10.12 после покупки.'
    )
    assert result['expires_at'] == '2026-11-30'


def test_several_deadlines_remind_about_the_earliest():
    result = parse('Скидка действует до 25.11, а баллы сгорят 15.12')
    assert result['expires_at'] == '2026-11-25'


def test_single_unlabelled_future_date_is_a_flagged_guess():
    result = parse('Чёрная пятница 27.11! Код BF2026')
    assert result['expires_at'] == '2026-11-27'
    assert result['expires_at_confidence'] == 'guessed'


def test_unknown_expiry_stays_null():
    result = parse('Дарим скидку 300 ₽ на первый заказ по промокоду HELLO300')
    assert result['expires_at'] is None
    assert result['expiry_phrase'] is None
    assert result['promo_code'] == 'HELLO300'
    assert result['description'] == (
        'Дарим скидку 300 ₽ на первый заказ по промокоду HELLO300'
    )


@pytest.mark.parametrize('text', [
    'Кешбэк 1.5% на всё',
    'Цена 2.50 ₽ за штуку',
    'Время работы 10.00–22.00',
])
def test_amounts_and_times_are_not_dates(text):
    assert parse(text)['expires_at'] is None


@pytest.mark.parametrize(('text', 'expected'), [
    ('Введите промокод: SPRING25 при оформлении', 'SPRING25'),
    ('по промокоду «ЛЕТО2026» скидка', 'ЛЕТО2026'),
    ('Промокод "welcome10" на первый заказ', 'welcome10'),
    ('Ваш промокод — Sale15', 'Sale15'),
    ('Промокоды на скидку: MEGA20 и MEGA30', 'MEGA20'),
    ('Используйте код BLACKFRIDAY', 'BLACKFRIDAY'),
    ('Купон 123456 на скидку', '123456'),
    ('Промокод 777888 даёт скидку', '777888'),
    ('Скидка 10% — просто покажите на кассе QR. Код KASSA10', 'KASSA10'),
    ('Дарим AUTUMN50 — скидку на осенние товары', 'AUTUMN50'),
    ('Промо-код: TAXI-300', 'TAXI-300'),
    ('Promo code: WINTER24', 'WINTER24'),
])
def test_promo_codes(text, expected):
    assert parse(text)['promo_code'] == expected


@pytest.mark.parametrize('text', [
    'Код подтверждения: 4821. Никому не сообщайте его.',
    'Ваш код для входа 553201',
    'Промокод действует при заказе от 1000 ₽',
    'Скидка 500 руб. на заказ от 2000 р.',
    'Получите 500 баллов за покупку',
])
def test_no_false_promo_codes(text):
    assert parse(text)['promo_code'] is None


@pytest.mark.parametrize(('text', 'amount', 'unit'), [
    ('Начислено 1 000 бонусов за покупку', '1000.00', 'бонусов'),
    ('У вас 2 450 баллов, они сгорят 31 декабря', '2450.00', 'баллов'),
    ('Ваш баланс: 125,50 бонусных рублей', '125.50', 'бонусных рублей'),
    ('Сгорит 1 балл', '1.00', 'балл'),
    ('На счёт зачислено 300 миль Аэрофлот Бонус', '300.00', 'миль'),
    ('Вам начислено 500 бонусов Спасибо', '500.00', 'бонусов'),
])
def test_points_amounts(text, amount, unit):
    result = parse(text)
    assert result['kind'] == 'points'
    assert result['points_amount'] == amount
    assert result['points_unit'] == unit


def test_points_without_amount_are_still_points():
    result = parse('Ваши бонусы сгорят 31 декабря')
    assert result['kind'] == 'points'
    assert result['points_amount'] is None
    assert result['expires_at'] == '2026-12-31'


def test_gift_points_with_a_code_are_a_promo():
    result = parse('Дарим 500 баллов по промокоду GIFT500 до 20.11')
    assert result['kind'] == 'promo'
    assert result['promo_code'] == 'GIFT500'
    assert result['discount'] == '500 баллов'
    assert result['points_amount'] is None


@pytest.mark.parametrize(('text', 'expected'), [
    ('Скидка 20% на обувь', 'скидка 20%'),
    ('Скидка до 50 % на технику', 'скидка до 50%'),
    ('Скидка 1 500 руб. на заказ', 'скидка 1 500 ₽'),
    ('Только сегодня −30% на всё', '−30%'),
    ('Дарим -500 ₽ на первый заказ', '−500 ₽'),
    ('15% кешбэк баллами', '15% кешбэк'),
    ('Кэшбэк до 25% у партнёров', 'кешбэк до 25%'),
    ('Бесплатная доставка по коду SHIP', 'бесплатная доставка'),
])
def test_discounts(text, expected):
    assert parse(text)['discount'] == expected


@pytest.mark.parametrize(('text', 'expected'), [
    ('[Самокат] Код SAM200 на скидку 200 ₽', 'Самокат'),
    ('Перекрёсток: ваши баллы сгорят завтра', 'Перекрёсток'),
    ('Скидка 10% в магазине «Цветочная лавка» по коду FLOWER', 'Цветочная лавка'),
    ('Скидка 10% в приложении Кофемания по коду COFFEE10', 'Кофемания'),
    ('Спортмастер дарит 1000 бонусов на день рождения', 'Спортмастер'),
    ('Wildberries: скидка 7% по коду WB7', 'Wildberries'),
    ('Промокод: SALE20. Скидка 20%', None),
])
def test_merchant(text, expected):
    assert parse(text)['merchant'] == expected


def test_otp_messages_produce_nothing_useful():
    result = parse('Код подтверждения 4821. Никому не сообщайте его.')
    assert result['promo_code'] is None
    assert result['expires_at'] is None
    assert result['points_amount'] is None


def test_title_falls_back_to_the_first_sentence():
    result = parse('Новая коллекция уже в продаже! Заходите.')
    assert result['title'] == 'Новая коллекция уже в продаже!'
    assert result['found'] == []


def test_long_text_is_truncated_and_multiline_banner_parsed():
    banner = 'М.Видео\nСкидка 3000 ₽\nна смартфоны\nпо промокоду PHONE3000\nдо 24.11'
    result = parse(banner + '\n' + 'x' * 20000)
    assert result['merchant'] == 'М.Видео'
    assert result['promo_code'] == 'PHONE3000'
    assert result['expires_at'] == '2026-11-24'
    assert result['discount'] == 'скидка 3000 ₽'
