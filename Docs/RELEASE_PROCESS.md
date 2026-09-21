# Выпуск новой версии iOS

Процесс для этого репозитория. Bundle ID: `com.mikhail.buildchecklists.arm`.  
Текущая выпущенная точка: **Version 1.0.3**, **Build 9**.

Номер версии и билда живут в `BuildChecklists.xcodeproj/project.pbxproj`:

- `MARKETING_VERSION` — Version (то, что видит пользователь и App Store);
- `CURRENT_PROJECT_VERSION` — Build (должен расти с каждой загрузкой в App Store Connect, даже внутри одной Version).

Минимальная iOS у таргета: **17.6**. Значение `IPHONEOS_DEPLOYMENT_TARGET = 26.0` на уровне project не использовать как истину для релиза.

---

## 1. Перед номером версии

1. Зафиксировать, что в сборку входит только эта папка проекта, не копии BuildChecklists 2/3.
2. Прогнать руками критический контур:
   - онбординг (на чистом симуляторе / сброшенном флаге);
   - DEMO: проект, coachmark’и, расходы, фото, бюджет, сроки;
   - регистрация → Paywall;
   - создание проекта (USER: лимит 2);
   - чек-лист стадии, фото пункта, «Инфо»;
   - расход и план бюджета;
   - задача и уведомление;
   - истечение / отсутствие подписки → read-only;
   - Restore;
   - «Что нового»;
   - удаление аккаунта.
3. Если пользовательские JSON-форматы менялись — описать миграцию. Старые файлы в Documents должны открываться.
4. Если менялся `CFBundleShortVersionString`, обновить тексты `Views/WhatsNew/WhatsNewView.swift`. Экран показывается, пока UserDefaults не совпадёт с новой Version.
5. Product ID подписок не менять без записи в App Store Connect.

Код не коммитить «заодно» с несвязанным рефакторингом.

---

## 2. Version

`MARKETING_VERSION` — семантический номер продукта (`1.0.4`, `1.1.0`, …).

Правило для этого приложения:

- патч (`1.0.x`) — исправления, тексты, устойчивость, не ломая формат данных;
- минор (`1.x.0`) — заметная функция при совместимости данных;
- мажор (`x.0.0`) — несовместимый формат или смена модели доступа.

Version видит пользователь. Её же читает «Что нового».

Поднять Version **в обоих** конфигурациях таргета (Debug и Release) в `project.pbxproj` или в Generic вкладке Xcode (они должны совпасть).

---

## 3. Build

`CURRENT_PROJECT_VERSION` — целое число. Следующая загрузка после Build 9 = **10**, затем 11, 12, …

Apple не примет второй бинарь с тем же Build для того же Version.  
Build увеличивается **на каждую** выгрузку (TestFlight и Store), даже если Version не менялась.

Не сбрасывать Build в 1 при новой Version.

---

## 4. Archive

1. Открыть `BuildChecklists.xcodeproj` в Xcode.
2. Scheme: **BuildChecklists**, Destination: **Any iOS Device (arm64)**.
3. Signing: team и bundle `com.mikhail.buildchecklists.arm`, distribution certificate / App Store profile.
4. Menu: **Product → Archive**.
5. Дождаться появления архива в **Organizer**.

Не архивировать для Simulator.  
Не подменять bundle id.

---

## 5. Upload

В Organizer:

1. Выбрать свежий архив → **Distribute App**.
2. **App Store Connect** → Upload.
3. Опции: bitcode не используется (современный toolchain). Включить символы для крашей, если предлагается.
4. Дождаться обработки в App Store Connect (Processing). Пока Processing, билд нельзя отдать в TestFlight / Review.

---

## 6. TestFlight

1. App Store Connect → приложение Build Checklists → TestFlight.
2. Дождаться «Ready to Test» / отсутствия Missing Compliance (экспорт). Для обычного приложения без нестандартного шифрования — стандартный compliance.
3. При необходимости заполнить «What to Test»: DEMO, подписка, лимит USER, read-only.
4. Internal testing — сразу команде.
5. External testing — если нужен внешний прогон, дождаться Beta Review (не путать с App Review релиза).

Подписки в TestFlight проверять на **Sandbox Apple ID**. Restore должен поднимать USER/PRO. DEMO не должен требовать песочницу.

Не удалять предыдущий успешный TestFlight-билд, пока текущий не подтверждён.

---

## 7. App Store Connect (карточка версии)

Для новой **Version** (не каждого Build):

1. Создать версию с тем же номером, что `MARKETING_VERSION`.
2. Выбрать загруженный Build.
3. Проверить:
   - скриншоты актуальных экранов (включая DEMO, бюджет, чек-листы);
   - описание и «что нового» — согласовать с `WhatsNewView`;
   - Privacy Policy URL (тот же, что в Paywall);
   - возраст, категорию;
   - подписки: группы, ID продуктов совпадают с кодом;
   - App Privacy / nutrition labels, если состав данных не менялся — не трогать зря.
4. Review notes на английском/русском по желанию: приложение полностью локальное; DEMO с Welcome; Delete Account в Профиле очищает Documents.

Удаление аккаунта уже реализовано wipe’ом Documents — это требование 5.1.1(v). Не убирать экран без замены.

---

## 8. Submit на Review

1. Build в статусе Processed.
2. Все обязательные поля версии заполнены.
3. **Add for Review** → **Submit**.
4. Не выкладывать параллельно другой бинарь с тем же Version+Build.
5. Если Review спросит про подписки / DEMO — опереться на `SUBSCRIPTIONS.md` и `DEMO_MODE.md`: DEMO сессионный, без автосохранения JSON проекта; без подписки после регистрации — read-only.

---

## 9. Release

После Approved:

- **Manually release** или **Automatic** — как настроено для этой версии.
- После появления в Store проверить на устройстве не из Xcode: покупка, restore, DEMO, «Что нового».
- Зафиксировать в git тег/сообщение: Version и Build (например `1.0.3 (9)`). Коммит делать только если пользователь его запросил, но **рекомендовать** коммит после закрытия релизного этапа.
- Обновить этот файл и `PROJECT_OVERVIEW.md` / `AI_CONTEXT.md`, когда фактически сменится текущая версия.

Откат в App Store не удаляет данные с устройств. Любая миграция JSON должна переживать и новую, и старую сборку до полного вытеснения.

---

## Чеклист номера

Перед Archive:

- [ ] `MARKETING_VERSION` обновлён (если это новая пользовательская версия)
- [ ] `CURRENT_PROJECT_VERSION` увеличен
- [ ] Debug и Release совпадают
- [ ] `WhatsNewView` соответствует Version
- [ ] Product ID подписок не разъехались
- [ ] Ручной прогон DEMO + USER/PRO + read-only
- [ ] Нет отладочных флагов, включающих DEMO на старте
