# CashFlow — прототипы для продуктового утверждения

Статус: утверждено и реализовано 22 сентября 2026 года. Все семь направлений перенесены во Flutter и подключены к существующим маршрутам без расширения backend-контрактов.

Актуально на 22 сентября 2026 года. Все банковские названия, проценты, сроки, лимиты и операции в макетах демонстрационные. HTML-файлы сохранены как воспроизводимые прототипы и история продуктовых решений.

| Направление | Статус | PNG для быстрого просмотра | Интерактивный HTML | UX-описание |
|---|---|---|---|---|
| Акции | Реализовано | [actions-screen.png](concepts/actions-screen.png) | [actions-screen.html](prototypes/actions-screen.html) | [actions-screen-ux.md](../actions-screen-ux.md) |
| Ещё | Реализовано | [more-screen.png](concepts/more-screen.png) | [more-screen.html](prototypes/more-screen.html) | [more-screen-ux.md](../more-screen-ux.md) |
| Вход, состояния и администрирование | Реализовано | [admin-access-views.png](concepts/admin-access-views.png) | [admin-access-views.html](prototypes/admin-access-views.html) | [admin-access-ux.md](../admin-access-ux.md) |
| Подтверждение в банках | Реализовано | [plan-confirmation.png](concepts/plan-confirmation.png) | [plan-confirmation.html](prototypes/plan-confirmation.html) | [plan-confirmation-ux.md](../plan-confirmation-ux.md) |
| Состояния Выгоды | Реализовано | [benefit-states.png](concepts/benefit-states.png) | [benefit-states.html](prototypes/benefit-states.html) | [benefit-states-ux.md](../benefit-states-ux.md) |
| Импорт и проверка MCC | Реализовано | [mcc-import-review.png](concepts/mcc-import-review.png) | [mcc-import-review.html](prototypes/mcc-import-review.html) | [mcc-import-review-ux.md](../mcc-import-review-ux.md) |
| Карточка категории конкретной карты | Реализовано | [category-detail.png](concepts/category-detail.png) | [category-detail.html](prototypes/category-detail.html) | [category-detail-ux.md](../category-detail-ux.md) |

## Уже существующие утверждённые направления

- [единый поиск покупки](concepts/purchase-search-flow-mobile.png);
- [ручной План — compact](concepts/plan-manual-mobile.png);
- [ручной План — expanded](concepts/plan-manual-desktop.png);
- [общая оболочка](concepts/shell-option-a.png).

## Граница текущей работы

Материалы остаются эталоном структуры и поведения. Реализация использует только существующие backend-контракты; функции, которым нужен новый контракт, показаны как недоступные или справочные. Проверки compact/medium/expanded, крупного текста, ролей и dark mode закреплены widget-тестами.
