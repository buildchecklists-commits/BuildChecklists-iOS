# Подписки и роли доступа

Состояние на релиз **1.0.3 / Build 9**.  
Оплата только через App Store. Своего бэкенда подписок нет. Комментарии в `RegisterView` про Supabase/`get-role` — наследие, на логику не влияют.

---

## Где живёт логика

| Слой | Файл | Ответственность |
|---|---|---|
| StoreKit | `Store/SubscriptionService.swift` | Продукты, покупка, restore, entitlements, listener транзакций |
| Правила | `Store/AppStore.swift` | `applySubscriptionToRoleAndAccess()`, лимит проектов, `ensureCanMutate()` |
| UI покупки | `Views/Paywall/PaywallView.swift` | USER/PRO, месяц/год, legal-ссылки |
| UI статуса | `ProfilePlaceholderView` в `Views/Main/MainTabView.swift` | Текущий тариф, обновить, восстановить, paywall |
| Блокер записи | десятки экранов | `isReadOnlyMode` → alert + sheet Paywall |

Product IDs (App Store Connect):

```
USER  monthly   buildchecklists.user.monthly
USER  yearly    buildchecklists.user.yearly
PRO   monthly   buildchecklists.pro.monthly.v2
PRO   yearly    buildchecklists.pro.yearly
```

Продукт PRO monthly без суффикса `.v2` в коде не запрашивается.

Legal в paywall:

- Privacy Policy: `https://buildchecklists-commits.github.io/buildchecklists-privacy/`
- Terms of Use: стандартный Apple EULA.

---

## Роли

`UserRole`: `demo`, `user`, `pro`.

Это **не** то же самое, что `isDemoMode`.

| Состояние | Как получается | Редактирование | Лимит проектов | Persist данных |
|---|---|---|---|---|
| **DEMO** | Кнопка «Попробовать демо», сессия | Да | Нет | JSON проектов/расходов/задач не пишется |
| **USER** | Активная подписка USER | Да | Максимум 2 | Да |
| **PRO** | Активная подписка PRO (приоритет над USER) | Да | Нет | Да |
| **Read-only** | Нет активных entitlements и это не DEMO | Нет | Создавать нельзя | Чтение с диска да |

Если активны и USER, и PRO, выигрывает PRO (`hasPro` проверяется первым).

`subscription.tier == .none` при живой сессии без DEMO всё равно проецируется в `userRole = .user` плюс `isReadOnlyMode = true`. То есть «нет подписки» в UI выглядит как USER без права писать, а не как DEMO.

---

## USER

- Подписка `buildchecklists.user.*`.
- На paywall: «До 2 проектов», редактирование и сохранение.
- `canCreateNewProject`: `projects.count < 2`.
- Третий проект → `AppStoreError.projectLimitReached` → алерт в `ProjectFormView`.
- Уже созданные данные не удаляются при переходе на USER.

---

## PRO

- Подписка `buildchecklists.pro.*` (месячный ID — `.v2`).
- На paywall: «Без ограничений», бейдж «Рекомендуем».
- `canCreateNewProject == true` при активной подписке.
- Если раньше был USER с 2 проектами, лимит снимается, данные сохраняются.

---

## DEMO

См. `DEMO_MODE.md`.

Кратко для доступа:

- `isDemoMode == true` обходит StoreKit в `bootstrap` (на практике bootstrap выключает DEMO, entitlements проверяются; DEMO включается позже кнопкой).
- `ensureCanMutate()` при DEMO сразу return.
- `canCreateNewProject` для роли `.demo` = true.
- Истёкшая подписка DEMO не включает: `isReadOnlyMode` принудительно false.

После регистрации DEMO выключается, дальше решает StoreKit. Без покупки новый профиль сразу в read-only.

---

## StoreKit: как определяется доступ

`SubscriptionService.refreshAccessFromStoreKit()`:

```
для каждой Transaction.currentEntitlements
    пропуск unverified
    пропуск isUpgraded
    пропуск revocationDate != nil
    если productID из userProductIDs → hasUser
    если productID из proProductIDs → hasPro

tier = hasPro ? .pro : hasUser ? .user : .none
isSubscriptionActive = (tier != .none)
isReadOnlyExpired = !isSubscriptionActive
```

Когда вызывается:

- `AppStore.bootstrap()` (если не DEMO);
- `loadProducts()`, `purchase()`, `restorePurchases()`;
- listener `Transaction.updates` с момента init сервиса;
- `AppStore.refreshRoleForCurrentUser()` (кнопки «Обновить» / после покупки).

Init сервиса **не** блокирует первый кадр полной проверкой: UI показывается, entitlements доезжают в bootstrap.

Покупка:

```
product.purchase()
  success → checkVerified → transaction.finish() → refresh
  userCancelled → false
  pending → сообщение «ожидает подтверждения»
```

Restore:

```
StoreKit.AppStore.sync()   // явно StoreKit.AppStore, не наш класс AppStore
refreshAccessFromStoreKit()
AppStore.refreshRoleForCurrentUser()
```

---

## Лимиты

Проверяется только число элементов в `AppStore.projects` (все загруженные объекты). Скрытых/архивных проектов нет.

Лимит не смотрит на ProgressStore и не смотрит на DEMO-артефакты на диске.

Read-only запрещает любые `ensureCanMutate` операции, не только создание проекта.

---

## Read-only

Включается, если `subscription.isReadOnlyExpired` и сессия не DEMO.

Последствия:

- `canEditAnything == false`
- `canCreateNewProject == false`
- CRUD бросает `AppStoreError.subscriptionExpiredReadOnly`
- Экраны показывают баннер/alert и предлагают Paywall
- Загрузка JSON в bootstrap **разрешена** — пользователь видит свои объекты

Проверки в UI неединообразны:

- часть экранов: `isReadOnlyMode && !isDemoMode`
- часть: только `isReadOnlyMode`

Сейчас в DEMO `isReadOnlyMode` всегда false, поэтому оба варианта работают. Менять один флажок без второго опасно.

Удаление аккаунта не отменяет подписку Apple. После wipe при следующем запуске StoreKit снова может выдать USER/PRO на чистые локальные данные.

---

## Смена ролей

```
Welcome ──демо──► isDemoMode
Welcome ──регистрация──► isRegistered, userRole из аргумента
                         (RegisterView передаёт .demo, затем сразу Paywall)
                         exitDemoMode → refresh StoreKit → user/pro/read-only

Paywall покупка USER/PRO ──► refreshRoleForCurrentUser
Restore / «Обновить»     ──► то же

Истечение подписки       ──► isReadOnlyExpired → isReadOnlyMode
                             если в UserDefaults лежала роль demo — заменить на user

Logout                   ──► isRegistered false, роль demo, данные persist пустыми
Delete account           ──► wipe Documents, флаги сброшены, подписка Apple на месте
```

`login()` ставит `isRegistered = true` без проверки пароля и без вызова AuthService (кроме последующего `exitDemoMode`). Экран входа не подключён. Не использовать login как образец «настоящей авторизации».

`persistUserRole()` пишет `bc.user.role`. Это кэш для UI, не источник права доступа. Право всегда пересчитывается из StoreKit (кроме активной DEMO-сессии).

---

## Что нельзя ломать в задачах

- Product ID, особенно `buildchecklists.pro.monthly.v2`.
- Приоритет PRO над USER.
- Read-only при отсутствии entitlements у зарегистрированного пользователя.
- Лимит ровно 2 проекта на USER.
- DEMO без авто-включения на старте.
- Restore через `StoreKit.AppStore.sync()`, не через самописный класс `AppStore`.
