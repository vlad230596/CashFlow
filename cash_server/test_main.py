import unittest
from datetime import datetime, timedelta, timezone

from main import (
    _category_period,
    _clean_category_description,
    _extract_cashback_amounts,
    _parse_import_datetime,
    _selection_is_locked,
)


class CashbackImportDatesTest(unittest.TestCase):
    def setUp(self):
        self.generated_at = _parse_import_datetime('2026-08-19T18:16:34.746Z')

    def test_generated_at_is_converted_to_moscow_time(self):
        self.assertEqual(
            self.generated_at,
            datetime(2026, 8, 19, 21, 16, 34, 746000, tzinfo=timezone(timedelta(hours=3))),
        )

    def test_monthly_category_uses_calendar_month(self):
        self.assertEqual(
            _category_period(self.generated_at, None),
            (datetime(2026, 8, 1), datetime(2026, 9, 1)),
        )

    def test_relative_expiry_is_bound_to_category(self):
        self.assertEqual(
            _category_period(self.generated_at, 'ещё 5 дней'),
            (datetime(2026, 8, 1), datetime(2026, 8, 24)),
        )

    def test_named_expiry_is_inclusive(self):
        self.assertEqual(
            _category_period(self.generated_at, 'Копится до 15 сентября'),
            (datetime(2026, 8, 1), datetime(2026, 9, 16)),
        )

    def test_explicit_selection_lock_wins(self):
        bank = {
            'selection': {
                'isLocked': False,
                'selectedCount': 4,
                'maxSelectable': 4,
            }
        }
        self.assertFalse(_selection_is_locked(bank, [{'selected': True}]))

    def test_full_selection_is_inferred_as_locked_for_legacy_json(self):
        bank = {'selection': {'selectedCount': 4, 'maxSelectable': 4}}
        self.assertTrue(_selection_is_locked(bank, [{'selected': True}]))

    def test_all_active_automatic_categories_are_inferred_as_locked(self):
        bank = {'selection': {'selectedCount': 2, 'maxSelectable': None}}
        self.assertTrue(
            _selection_is_locked(
                bank,
                [{'selected': True}, {'selected': True}],
            )
        )

    def test_extracts_vtb_max_cashback_and_minimum_purchase(self):
        imported = {
            'subtitle': 'При покупке от 5 000 ₽ онлайн и в розничных магазинах',
            'description': 'Кешбэк до 2 000 рублей\nMCC: 5691',
        }
        self.assertEqual(_extract_cashback_amounts(imported), (2000.0, 5000.0))

    def test_prefers_structured_amounts(self):
        imported = {
            'maxCashbackAmount': 750,
            'minPurchaseAmount': 1200,
            'description': 'Кешбэк до 500 рублей',
        }
        self.assertEqual(_extract_cashback_amounts(imported), (750.0, 1200.0))

    def test_cleans_vtb_limit_and_mcc_explanation(self):
        description = (
            'Кешбэк до 2 000 рублей\n'
            'MCC: 5691\n'
            'МСС — это код вида деятельности продавца. По нему банк определяет '
            'категорию покупки для расчета кешбэка.\n'
            'При оплате по СБП кешбэк не начисляется'
        )
        self.assertEqual(
            _clean_category_description('vtb', description),
            'MCC: 5691\nПри оплате по СБП кешбэк не начисляется',
        )

    def test_cleans_limit_sentence_without_removing_other_details(self):
        description = (
            'За покупки в приложении партнера. Лимит кешбэка 500 ₽. '
            'Не распространяется на оплату по СБП.'
        )
        self.assertEqual(
            _clean_category_description('ozon', description),
            'За покупки в приложении партнера. Не распространяется на оплату по СБП.',
        )


if __name__ == '__main__':
    unittest.main()
