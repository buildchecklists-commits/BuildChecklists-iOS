# Потоки данных

Как данные появляются, где живут и как доходят до UI. Состояние на момент релиза **1.0.3 / Build 9**.

---

## Что хранится в памяти

Источник: `@MainActor class AppStore`.

| Поле | Содержание |
|---|---|
| `projects` | Все объекты текущей сессии |
| `expenses` | Все расходы |
| `tasks` | Все задачи |
| `seeds` | Глобальные этапы из `stages.json` |
| `isRegistered` | Есть локальный профиль |
| `userRole` | `demo` / `user` / `pro` |
| `isDemoMode` | Сессионный DEMO |
| `isReadOnlyMode` | Подписка истекла, запись запрещена |
| `selectedTab` | Текущая вкладка |
| `subscription` | Экземпляр `SubscriptionService` (продукты, tier, ошибки) |

Дополнительно в Views:

- `@State [Stage]` на экранах стадий — рабочий чек-лист до/после записи в ProgressStore;
- `@AppStorage` тема, онбординг, имя и аватар профиля;
- coachmark-флаги DEMO только в `@State` текущей сессии.

ProgressStore **не кэшируются** в AppStore. Каждый экран/карточка читает файлы или UserDefaults заново (часто при `bcProgressDidChange`).

---

## Что хранится на диске (Documents)

| Файл / папка | Данные |
|---|---|
| `build_checklists_projects.json` | Проекты: метаданные, `stages` таймлайна, контакты, пути файлов, бюджеты |
| `build_checklists_expenses.json` | Расходы |
| `build_checklists_tasks.json` | Задачи |
| `build_checklists_profile.json` | Локальный профиль (имя, email, secret) |
| `BC_Geology/{uuid}.json` | Рабочий чек-лист геологии |
| `BC_Foundation/{uuid}.json` | Фундамент |
| `BC_Walls/{uuid}.json` | Стены |
| `BC_Slab/{uuid}.json` | Перекрытия |
| `BC_Roof/{uuid}.json` | Крыша |
| `BC_Engineering/{uuid}.json` | Инженерия |
| `BC_Windows/{uuid}.json` | Окна |
| `BC_Finishing/{uuid}.json` | Отделка |
| `BC_Landscaping/{uuid}.json` | Благоустройство |
| `BC_Media/Images/` | JPEG пунктов и общих фото |
| `BC_Media/PDF/` | PDF вложений |
| `ProjectCovers/cover_{uuid}.jpg` | Обложка карточки |
| `BCNotes/{itemID}.txt` | Заметки пунктов чек-листа |

Кодирование JSON: `JSONEncoder`, даты ISO-8601, prettyPrinted + sortedKeys.

В DEMO `persistProjects/Expenses/Tasks` не вызывают запись трёх основных JSON. ProgressStore и медиа при этом **могут** писать на диск. См. `DEMO_MODE.md`.

---

## Что хранится в UserDefaults / AppStorage

| Ключ | Смысл |
|---|---|
| `bc_has_seen_onboarding` | Онбординг пройден |
| `bc_is_registered` | Локальный аккаунт есть |
| `bc.user.role` | Последняя сохранённая роль |
| `bc.ui.selectedTab` | Выбранный таб |
| `bc_last_demo_project_id` | UUID последней DEMO-сессии для зачистки |
| `bc_last_seen_whats_new_version` | Версия, для которой закрыли «Что нового» |
| `appColorScheme` | `system` / `light` / `dark` |
| `profileName` | Имя в профиле (не AuthService) |
| `profileAvatarData` | Аватар профиля |
| `bc.notifications.authRequested` | Системный запрос уведомлений уже показывали |
| `roofcover_progress_{uuid}` | Прогресс покрытия крыши |
| `doors_progress_{uuid}` | Прогресс дверей |

StoreKit entitlements в UserDefaults приложения не дублируются: их хранит система.

---

## Как создаётся проект

Единственный доменный метод: `AppStore.createProject(_ input: NewProjectInput)`.

```
ProjectsListView
    └── sheet ProjectFormView
            │  имя, адрес, даты, общий бюджет, прораб, описание
            ▼
    NewProjectInput
            │
            ▼
    AppStore.createProject
            ├── ensureCanMutate()          DEMO ок, read-only нет
            ├── USER: не больше 2 проектов
            ├── создаётся Project с новым UUID
            ├── stages = seeds.map { $0.materialize(...) }
            ├── projects.insert(at: 0)
            └── если не DEMO → persistProjects()
                    │
                    ▼
            UI: переход к выбору типа фундамента
```

После создания пользователь выбирает типы конструкций (фундамент, стены, перекрытия, крыша, покрытие). Это поля `Project`, не создание второго проекта.

DEMO идёт тем же `createProject`, затем дописывает даты, таймлайн, план бюджета, ProgressStore и расходы. См. `DEMO_MODE.md`.

Правка карточки (`EditProjectView`) вызывает `updateProject` и отдельно `CoverImageStore` — это не создание.

Удаление: `deleteProject` снимает медиа по сохранённым путям, обложку, проект и связанные расходы, затем `persistAll()`.

---

## Как создаются расходы

Единственный метод: `AppStore.addExpense(_ input: NewExpenseInput)`.

```
ProjectDashboard / Budget
    └── ProjectExpensesView
            └── sheet AddExpenseView
                    │  сумма, дата, категория, подкатегория,
                    │  опционально этап и пункт
                    ▼
            NewExpenseInput
                    │
                    ▼
            AppStore.addExpense
                    ├── ensureCanMutate()
                    ├── ExpenseItem вставляется в начало массива
                    └── persistExpenses()   (пропуск в DEMO)
```

Правка: `EditExpenseView` → `updateExpense` (тот же `id`).  
Удаление: `deleteExpense`.

Факт бюджета — это сумма `expenses` по проекту и стадии. План бюджета в расходы не пишется.

DEMO наполняет расходы через тот же `addExpense` списком заготовленных строк.

Категории расходов (`ExpenseCategory`) не содержат отдельного «Покрытие крыши». Глобальные стадии (`GlobalStageCategory`) — содержат. При привязке расхода это нужно учитывать.

---

## Как создаются задачи

Методы: `AppStore.addTask(...)` / `addTask(_ NewTaskInput)` → внутренний `addTaskInternal`.

```
TasksCenterView / дашборд проекта
    └── TaskFormView
            ▼
    AppStore.addTaskInternal
            ├── ensureCanMutate()
            ├── TaskItem в tasks[0]
            ├── persistTasks()
            └── TaskNotificationService.rescheduleNotification
```

Переключение выполнения отменяет или ставит уведомление заново.  
Удаление снимает pending-notification по `task.id`.

При `bootstrap` (не DEMO) все активные будущие задачи перепланируются: `rescheduleAllNotifications`.

Системный prompt уведомлений показывается один раз, в т.ч. при входе в DEMO с Welcome.

---

## Как работает ProgressStore

Шаблон (на примере фундамента):

```
FoundationStagesScreen.onAppear
        │
        ├── FoundationProgressStore.load(projectID, typeID:)
        │       ├── читает Documents/BC_Foundation/{uuid}.json
        │       ├── грузит шаблон FoundationStagesProvider.loadStages(named:)
        │       └── merge по title: сохраняет статусы/фото/заметки,
        │           подтягивает новые пункты и актуальный infoSlug
        │
        └── если файла нет — берётся чистый шаблон из JSON-пака
                │
                ▼
        @State stages
                │
        пользователь отмечает пункты, добавляет фото
                │
        onChange(of: stages)
                ├── FoundationProgressStore.save(...)
                └── NotificationCenter .bcProgressDidChange
```

Фото пункта (рабочий путь):

```
ChecklistItemRow2
    PhotosPicker → MediaService.save(image:) → путь в BC_Media/Images
    item.photoPaths.append(path)
    экран стадии сохраняет весь [Stage] в ProgressStore
```

Заметки пункта дополнительно пишутся в `BCNotes/{item.id}.txt`. Если UUID пункта сменится при пересоздании шаблона, файл заметки отвяжется.

Старый путь `ItemCardView` → `AppStore.addPhoto` пишет в `Project.stages` (таймлайн), не в ProgressStore. Рабочие экраны стадий используют `StageDetailView2`.

---

## Как обновляется UI

| Событие | Механизм |
|---|---|
| Создали/изменили проект, расход, задачу, роль | `@Published` AppStore |
| Изменили пункт рабочего чек-листа | файл ProgressStore + `bcProgressDidChange` |
| Сменили вкладку | `selectedTab` + UserDefaults `bc.ui.selectedTab` |
| Сменили тему | `@AppStorage("appColorScheme")` на корне и табах |
| StoreKit прислал транзакцию | listener в SubscriptionService → refresh → AppStore применяет роль |
| Закрыли «Что нового» | UserDefaults версии; sheet больше не откроется до следующей версии |

Карточка проекта и дашборд считают `%` как среднее по ProgressStore (10 сторов, **без дверей**).  
`AppStore.projectProgress` считает `Project.stages` и для карточки не является источником истины.

Вкладка «Фото» только читает `project.photoPaths` и `item.photoPaths` из всех ProgressStore. Новые снимки там не создаются.

---

## Как создаётся / меняется бюджет

Бюджет — план, не расход.

| Поле | Когда появляется |
|---|---|
| `Project.budget` | Поле в `ProjectFormView` при создании; в DEMO = 12 000 000; можно перезаписать суммой планов в `BudgetProjectView.syncOverallBudgetToStages()` |
| `Project.plannedBudgetByStage` | Форма плана внутри `BudgetProjectView`; в DEMO — фиксированная таблица сумм |

`EditProjectView` общий бюджет не редактирует.

План/факт на экране бюджета:

- план — `plannedBudgetByStage`;
- факт — агрегация `expenses` по `stageCategory` / категории расхода.

Оба пишутся только через `AppStore.updateProject` / `addExpense` (кроме DEMO, где persist JSON пропускается).
