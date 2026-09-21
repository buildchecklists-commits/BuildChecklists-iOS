# Архитектура BuildChecklists iOS

Документ фиксирует архитектуру релиза **1.0.3 (Build 9)**.  
Это SwiftUI-приложение с одним глобальным store, без сервера, без SwiftData/Core Data.

---

## Слои

```
App
 ↓
AppStore
 ↓
Models
 ↓
Services
 ↓
ProgressStore
 ↓
Views
 ↓
Components
 ↓
Resources
```

Стрелка — направление зависимости сверху вниз, а не единственный путь данных. Views читают AppStore и ProgressStore; Resources читаются сервисами и провайдерами; AppStore оркестрирует Models и часть Services.

---

## Назначение слоёв

### App

Точка входа: `App/BuildChecklistsApp.swift`.

- Создаёт единственный `AppStore` (`@StateObject`).
- Прокидывает его через `.environmentObject`.
- Задаёт акцент `AccentYellow` и тему (`appColorScheme`).
- `RootView` выбирает Onboarding / Welcome / MainTab.
- После появления основного UI вызывает `store.bootstrap()`.

### AppStore

`Store/AppStore.swift` — единственный доменный фасад.

Держит в памяти проекты, расходы, задачи, seeds, флаги доступа и DEMO.  
Содержит CRUD, бюджетную аналитику, экспорт, bootstrap DEMO, миграцию `Project.stages`.

Рядом: `Store/SubscriptionService.swift` (StoreKit 2). AppStore применяет результат StoreKit к `userRole` и `isReadOnlyMode`.

Views не должны писать JSON проектов/расходов/задач напрямую.

### Models

Codable-структуры в `Models/`. Описывают данные, не знают о UI и диске.

Ключевые типы: `Project`, `Stage`, `StageItem`, `ExpenseItem`, `TaskItem`, `ProjectContact`, enum’ы типов конструкций, seed/pack-модели.

### Services

Работа с диском, медиа, auth, контентом бандла, уведомлениями.

Не держат экранное состояние. ProgressStore формально тоже сервисы (часть лежит в `Services/`, часть в `Resources/Seeds/`).

### ProgressStore

Отдельное хранилище **рабочих** чек-листов на каждый тип стадии и каждый `projectID`.

Это не `Project.stages`. Это второй контур данных, от которого зависят карточка проекта, дашборд, вкладка «Фото» и проценты в бюджете.

### Views

Экраны в `Views/`. Почти все получают `AppStore` из environment.  
Экраны стадий держат локальный `@State [Stage]` и сами сохраняют его в ProgressStore.

### Components

Переиспользуемые куски UI: строка пункта, sheet «Инфо», шаринг, стили кнопок.

### Resources

Контент бандла: JSON-паки чек-листов и markdown «Инфо». Пользовательские данные сюда не пишутся.

---

## Схема запуска

```
BuildChecklistsApp
        │
        ▼
   RootView
        │
        ├── !hasSeenOnboarding ──► OnboardingView
        │
        └── иначе
              ├── isRegistered || isDemoMode ──► MainTabView
              │                                      │
              │                                      ├── Проекты
              │                                      ├── Сроки
              │                                      ├── Бюджет
              │                                      ├── Фото
              │                                      └── Профиль
              │
              └── иначе ──► WelcomeView
                              ├── «Попробовать демо» → enterDemoMode()
                              └── «Создать профиль» → RegisterView → Paywall
```

`bootstrap()` выполняется в `.task` у NavigationStack после онбординга.

---

## Два контура чек-листов

Это центральный факт архитектуры.

```
                    Project (JSON проекта)
                           │
                           ├── metadata, контакты, файлы, бюджет
                           └── stages[]  ◄── stages.json (глобальный таймлайн)
                                    │
                                    └── вкладка «Сроки», причины просрочки

                    ProgressStore (на projectID)
                           │
                           └── [Stage] из JSON-пака типа конструкции
                                    │
                                    └── дашборд, % на карточке, фото пунктов, «Инфо»
```

Пример: у проекта выбран `foundationType = strip`.  
Таймлайн показывает этап «Фундамент» из `stages.json`.  
Рабочий чек-лист открывается из дашборда и берётся из `foundation_strip.json` через `FoundationStagesProvider` + `FoundationProgressStore`.

`SeedStage.materialize` **намеренно не подгружает паки**. Паки грузят экраны стадий.

---

## Поток данных

### Чтение проекта в UI списка / дашборда

```
StorageService.loadProjects()
        │
        ▼
AppStore.projects
        │
        ├── метаданные карточки
        └── overallProgress() ──► GeologyProgressStore.load
                                  FoundationProgressStore.load
                                  Walls / Slab / Roof / RoofCover
                                  Engineering / Windows / Finishing / Landscaping
                                  (Doors в среднем % сейчас не входит)
```

### Изменение пункта рабочего чек-листа

```
ChecklistItemRow2 / StageDetailView2
        │  меняет Binding<Stage>
        ▼
*StagesScreen.onChange(stages)
        │
        ├── *ProgressStore.save(projectID, stages)
        └── NotificationCenter.post(.bcProgressDidChange)
                │
                ▼
     ProjectsListView / ProjectDashboardView / Budget / Photos
     пересчитывают прогресс
```

`AppStore` в этом пути обычно не участвует.

### Изменение сроков / контактов / бюджета плана

```
View → AppStore.updateProject / mutateStage
            │
            ▼
    persistProjects()  ──если не DEMO──► StorageService.saveProjects
            │
            ▼
    @Published projects → SwiftUI перерисовка
```

### Расходы и задачи

```
View → AppStore.addExpense / addTask
            │
            ├── persistExpenses / persistTasks   (пропуск в DEMO)
            └── для задач: TaskNotificationService
```

### Подписка

```
StoreKit (Transaction.currentEntitlements)
        │
        ▼
SubscriptionService.tier / isReadOnlyExpired
        │
        ▼
AppStore.applySubscriptionToRoleAndAccess()
        │
        ├── userRole = .user | .pro
        └── isReadOnlyMode
                │
                ▼
         Views блокируют запись, показывают Paywall
```

DEMO этот путь обходит: `isDemoMode == true` → редактирование разрешено, StoreKit не ограничивает сессию.

---

## Хранилища ProgressStore

| Store | Файлы | Каталог / ключ |
|---|---|---|
| Geology | `Services/GeologyProgressStore.swift` | `Documents/BC_Geology/{uuid}.json` |
| Foundation | `Services/FoundationProgressStore.swift` | `Documents/BC_Foundation/{uuid}.json` |
| Walls | `Services/WallsProgressStore.swift` | `Documents/BC_Walls/{uuid}.json` |
| Slab | `Services/SlabProgressStore.swift` | `Documents/BC_Slab/{uuid}.json` |
| Roof | `Services/RoofProgressStore.swift` | `Documents/BC_Roof/{uuid}.json` |
| Engineering | `Services/EngineeringProgressStore.swift` | `Documents/BC_Engineering/{uuid}.json` |
| Windows | `Services/WindowsProgressStore.swift` | `Documents/BC_Windows/{uuid}.json` |
| Finishing | `Services/FinishingProgressStore.swift` | `Documents/BC_Finishing/{uuid}.json` |
| Landscaping | `Services/LandscapingProgressStore.swift` | `Documents/BC_Landscaping/{uuid}.json` |
| RoofCover | `Resources/Seeds/RoofCoverProgressStore.swift` | UserDefaults `roofcover_progress_{uuid}` |
| Doors | `Resources/Seeds/DoorsProgressStore.swift` | UserDefaults `doors_progress_{uuid}` |

Merge сохранённых данных с шаблоном идёт **по `title` этапа и пункта**, не по UUID. Переименование title в JSON ломает прогресс пользователя.

---

## Обновление UI

1. `@Published` в `AppStore` — проекты, расходы, задачи, флаги режима.
2. `Notification.Name.bcProgressDidChange` — прогресс чек-листов, который AppStore не публикует.
3. Локальный `@State` на экранах стадий — список пунктов до сохранения.
4. `@AppStorage` — тема, онбординг, имя/аватар профиля.

Нет единой реактивной модели прогресса. Любой новый экран, который показывает %, должен подписаться на `bcProgressDidChange` или читать store в момент появления.

---

## Что архитектура сознательно не делает

- Нет облачной синхронизации и аккаунта на сервере.
- Нет единого репозитория «все данные проекта в одном файле».
- Нет проверки пароля при login (и `LoginView` нигде не открывается).
- `AppStore.projectProgress(Project.stages)` не используется карточкой проекта; карточка считает ProgressStore.

Эти факты нельзя «исправить по пути» в мелкой задаче. См. `DEVELOPMENT_RULES.md`.
