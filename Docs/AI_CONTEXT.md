# Контекст для нового чата Cursor

Прочитай этот файл в начале работы над BuildChecklists.  
Затем при необходимости открой остальные документы в `Docs/`.  
**Код не менять, пока не понят контур данных и не согласован план.**

---

## Что это за проект

**BuildChecklists** — iOS-приложение (SwiftUI) для контроля частной стройки: чек-листы этапов, фото, сроки, расходы, бюджет, задачи.

Полностью локальное. Сервера нет. Подписки — StoreKit 2.

Язык интерфейса — русский.

---

## Текущая версия

- App Store **1.0.3**
- Build **9**
- Bundle ID: `com.mikhail.buildchecklists.arm`
- Deployment target таргета: iOS 17.6

Эта папка — **единственный источник истины для iOS** с указанной даты фиксации.  
Папки BuildChecklists 2 и BuildChecklists 3 — архивные копии, не разрабатывать там.

Для Android этот iOS-проект — эталон поведения. См. `ANDROID_SYNC.md`.

---

## Как устроена архитектура (коротко)

```
App (BuildChecklistsApp / RootView)
  → AppStore + SubscriptionService
    → Models
    → Services (JSON, медиа, auth)
    → ProgressStore (рабочие чек-листы на projectID)
  → Views / Components
  → Resources (JSON-паки + InfoTexts)
```

Два контура чек-листов:

1. `Project.stages` из `Resources/Seeds/stages.json` — **таймлайн / сроки**.
2. `*ProgressStore` из паков типа конструкции — **рабочие чек-листы, % на карточке, фото пунктов**.

Их нельзя склеить «по пути». Подробности: `ARCHITECTURE.md`, `DATA_FLOW.md`.

---

## Как мы работаем

1. Сначала анализ существующего кода и `Docs/`.
2. Потом план: что меняется / что нельзя трогать / как проверить.
3. Только потом дифф в коде.
4. Никаких неожиданных рефакторингов и смены архитектуры.
5. Коммит — только если пользователь попросил. После большого этапа **рекомендовать** коммит.
6. Перед крупной задачей — резервная точка (понятный откат).
7. Поведение DEMO, подписок и формата данных на диске священно.

Полный регламент: `DEVELOPMENT_RULES.md`.

---

## Что запрещено менять без отдельной явной задачи

- Product ID подписок (`buildchecklists.user.*`, `buildchecklists.pro.monthly.v2`, `buildchecklists.pro.yearly`).
- Лимит USER = 2 проекта; PRO без лимита; нет подписки → read-only.
- Авто-включение DEMO на старте (его быть не должно).
- Persist JSON проектов/расходов/задач внутри DEMO.
- `title` пунктов/этапов в JSON-паках (merge прогресса по строке title).
- `rawValue` Codable-enum’ов и имена файлов в Documents.
- Склейка ProgressStore обратно в `Project.stages` через materialize.
- Удаление «мёртвого» кода пачкой (`LoginView`, `StageDetailView`, дубли паков).
- Переписывание `AppStore.swift` / `MainTabView.swift` «на модули».
- Git config, force-push, коммит без просьбы.

---

## Самые важные файлы

| Файл | Зачем |
|---|---|
| `App/BuildChecklistsApp.swift` | Вход, онбординг vs Welcome vs Main |
| `Store/AppStore.swift` | Весь домен, DEMO, CRUD, бюджет |
| `Store/SubscriptionService.swift` | StoreKit |
| `Models/Project.swift`, `Stage.swift`, `StageItem.swift`, `Expenses.swift`, `Enums.swift` | Модель |
| `Services/StorageService.swift` | JSON на диске |
| `Services/*ProgressStore.swift` | Прогресс стадий |
| `Resources/Seeds/stages.json` | Таймлайн |
| `Resources/Seeds/*Packs/*.json` | Рабочие чек-листы |
| `Views/Projects/ProjectDashboardView.swift` | Карта объекта |
| `Views/Projects/ProjectsListView.swift` | Список + % + обложки |
| `Views/Stages/*StagesScreen.swift` + `StageDetailView2.swift` | Чек-листы |
| `Components/ChecklistItemRow2.swift` | Статус и фото пункта |
| `Views/Paywall/PaywallView.swift` | Покупка |
| `Views/Welcome/WelcomeView.swift` | Вход в DEMO / регистрацию |
| `Views/WhatsNew/WhatsNewView.swift` | «Что нового» на Version |

Документы: этот файл + `PROJECT_OVERVIEW.md`, `ARCHITECTURE.md`, `DATA_FLOW.md`, `DEMO_MODE.md`, `SUBSCRIPTIONS.md`, `RELEASE_PROCESS.md`, `DEVELOPMENT_RULES.md`, `ANDROID_SYNC.md`.

---

## Частые ошибки при работе с проектом

1. Считать `Project.stages` рабочим чек-листом и править прогресс только там. Карточка проекта читает ProgressStore.
2. Переименовать пункт в JSON — пользователь теряет статус (merge по title).
3. Поменять формулу `%` только в одном экране. Копии есть в списке, дашборде и бюджете. Двери в среднее сейчас не входят.
4. Забыть `bcProgressDidChange` после записи ProgressStore — UI не обновит %.
5. Включить запись DEMO на диск или авто-DEMO в bootstrap.
6. Зачистить DEMO не во всех `BC_*` папках.
7. Выдать роль PRO локально, минуя StoreKit.
8. Спутать `isDemoMode` и `userRole == .demo`.
9. Добавить расход в категорию «покрытие крыши» — такой `ExpenseCategory` нет.
10. Использовать `StageDetailView` / `ItemCardView` для новых стадий вместо `StageDetailView2` / `ChecklistItemRow2`.
11. Ломать decode старых проектов, добавив обязательное поле.
12. Править копию проекта в другой папке, а не этот репозиторий.

---

## Как правильно выполнять новые задачи

```
1. Прочитать AI_CONTEXT.md и профильный Doc (DEMO / подписки / данные).
2. Найти все точки: модель, AppStore, View, ProgressStore, JSON.
3. Сказать план и риски (совместимость данных, DEMO, %).
4. Менять минимальный дифф.
5. Проверить сценарий пользователя, не только компиляцию.
6. Если изменилось поведение — обновить Docs.
7. Предложить коммит, если этап большой; не коммитить молча.
```

Если задача про Android: не копировать внутреннюю нарезку файлов iOS, копировать поведение. iOS остаётся эталоном, пока продукт явно не меняют на обеих платформах.

Если пользователь сказал «ничего не изменяй» — не изменять код и не «улучшать» документацию сверх запроса.
