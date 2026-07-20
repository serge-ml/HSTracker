# План разработки HSTracker Arena

Форк HSTracker для macOS с автоматическим отображением публичных оценок HearthArena во время драфта Arena.

**Статус:** проектный план
**Дата:** 19 июля 2026 года
**Базовый проект:** [HearthSim/HSTracker](https://github.com/HearthSim/HSTracker)
**Источник рейтингов:** [публичная tier list HearthArena](https://www.heartharena.com/tierlist)

## 1. Краткое резюме

Нужно создать тонкий форк HSTracker, который во время обычного Arena-драфта:

1. автоматически распознаёт очередное предложение карт;
2. получает идентификаторы предложенных карт из уже существующего механизма HSTracker;
3. сопоставляет карты с публичными классовыми оценками HearthArena;
4. показывает оценки поверх или рядом с тремя картами;
5. скрывает оверлей сразу после выбора;
6. продолжает получать исправления и поддержку новых версий Hearthstone из официального HSTracker.

Пользователь будет использовать только форк. Официальное приложение можно удалить после создания резервной копии данных и проверки первой рабочей сборки.

Основные архитектурные решения:

- не использовать OCR и распознавание скриншотов;
- опираться на существующий ArenaWatcher и HearthMirror внутри HSTracker;
- не пытаться воспроизвести закрытый динамический алгоритм HearthArena;
- использовать только публичные базовые рейтинги карт;
- держать код расширения в отдельном модуле/каталоге;
- автоматически готовить обновления из upstream, но выпускать их только после тестов;
- обновлять рейтинги HearthArena независимо от обновления приложения;
- не использовать официальный канал Sparkle, чтобы официальный HSTracker не заменил форк.

## 2. Цель и границы проекта

### 2.1. Целевой пользовательский сценарий

Во время драфта Hearthstone Arena на экране появляются три карты. Не позднее чем через одну секунду над каждой картой появляется:

- числовая оценка HearthArena;
- цветовая категория качества;
- место карты среди текущих трёх вариантов.

После выбора карты информация исчезает. При следующем предложении появляются новые оценки.

### 2.2. Что входит в MVP

- обычный Arena-драфт с тремя отдельными картами;
- определение класса и предложенных карт через HSTracker;
- классовые рейтинги HearthArena;
- прозрачный click-through оверлей;
- локальный кэш рейтингов;
- работа без сети на последнем успешном наборе данных;
- ручное обновление рейтингов;
- диагностический статус источника данных;
- сборка форка на основе актуального upstream HSTracker;
- документированная процедура синхронизации с upstream.

### 2.3. Что не входит в MVP

- копирование полного динамического совета HearthArena;
- анализ синергий и архетипа колоды по закрытому алгоритму HearthArena;
- автоматический выбор или клик по карте;
- подсказки во время матча;
- отправка данных драфта на HearthArena;
- авторизация на HearthArena;
- публичная массовая дистрибуция до проверки условий использования данных;
- собственный алгоритм оценки карт;
- агрегированная оценка Legendary Groups без явно выбранного правила агрегации.

## 3. Почему задача технически реализуема

HSTracker уже содержит почти всю сложную инфраструктуру:

- отслеживает состояние Arena;
- различает drafting, midrun, redrafting и другие состояния;
- знает текущий слот драфта;
- получает текущую колоду;
- различает обычную и Underground Arena;
- вызывает MirrorHelper.getArenaDraftChoices();
- получает choices, packages и версию текущего предложения.

В [ArenaWatcher.swift](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/HearthWatcher/ArenaWatcher.swift) уже присутствует закомментированная точка onChoicesChanged. Следовательно, базовая реализация требует не нового механизма распознавания, а аккуратного подключения к существующему событию.

Публичная [tier list HearthArena](https://www.heartharena.com/tierlist) содержит классовые названия и числовые оценки карт. Её можно преобразовывать в локальный нормализованный snapshot.

## 4. Ключевые продуктовые решения

### 4.1. Название приложения

Рабочее название: **HSTracker Arena**.

Даже если официальный HSTracker будет удалён, отдельное название полезно для:

- различения официальной и собственной сборки;
- корректного отображения в crash reports;
- предотвращения случайной установки официального обновления;
- однозначного именования GitHub Releases.

### 4.2. Идентичность приложения

Перед первой release-сборкой выбрать:

- PRODUCT_NAME: HSTracker Arena;
- уникальный PRODUCT_BUNDLE_IDENTIFIER, например идентификатор в принадлежащем владельцу namespace;
- URL scheme, отличную от hstracker;
- собственную подпись приложения.

Не следует использовать namespace net.hearthsim для нового Bundle ID.

### 4.3. Совместимость с существующими данными

В текущем HSTracker пути к колодам, реплеям, изображениям и Arena JSON жёстко основаны на каталоге:

~~~text
~/Library/Application Support/HSTracker
~~~

Это видно в [Paths.swift](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/Core/Paths.swift). Поскольку официальное приложение и форк не будут использоваться одновременно, рекомендуется:

- сохранить этот каталог без переименования;
- перед первым запуском форка создать его резервную копию;
- не удалять данные при удалении официального приложения;
- добавить отдельный подкаталог для HearthArena-кэша:

~~~text
~/Library/Application Support/HSTracker/heartharena
~~~

Настройки HSTracker хранятся через UserDefaults.standard и зависят от Bundle ID. При изменении Bundle ID форк автоматически не увидит старые настройки. Поэтому нужен одноразовый импорт настроек из официального домена net.hearthsim.hstracker.

Рекомендуемая политика миграции:

1. при первом запуске проверить наличие старого preferences domain;
2. предложить импортировать настройки;
3. копировать только известные ключи;
4. отдельно предупредить о токенах HSReplay;
5. записать флаг migrationCompleted;
6. никогда не удалять старые preferences автоматически.

## 5. Архитектура решения

~~~mermaid
flowchart TD
    A["Hearthstone"] --> B["HearthMirror / HSTracker"]
    B --> C["ArenaWatcher"]
    C --> D["ArenaChoiceAdapter"]
    D --> E["HearthArena Overlay"]
    F["HearthArena tier list"] --> G["Parser + Cache"]
    G --> D
~~~

### 5.1. Предлагаемая структура исходников

~~~text
HSTracker/
└── HearthArenaOverlay/
    ├── Domain/
    │   ├── ArenaOffer.swift
    │   ├── ArenaRatedCard.swift
    │   └── TierRating.swift
    ├── Integration/
    │   ├── ArenaChoiceAdapter.swift
    │   └── HearthArenaFeatureBootstrap.swift
    ├── Data/
    │   ├── HearthArenaClient.swift
    │   ├── HearthArenaHTMLParser.swift
    │   ├── HearthArenaTierListStore.swift
    │   ├── TierListCache.swift
    │   └── CardIdentityResolver.swift
    ├── UI/
    │   ├── ArenaOverlayController.swift
    │   ├── ArenaOverlayWindow.swift
    │   ├── ArenaCardRatingView.swift
    │   └── ArenaOverlayLayout.swift
    ├── Settings/
    │   ├── HearthArenaSettings.swift
    │   └── HearthArenaPreferencesController.swift
    └── Diagnostics/
        └── HearthArenaDiagnostics.swift
~~~

### 5.2. Минимальные изменения в upstream-коде

Цель — ограничиться несколькими маленькими интеграционными патчами:

1. В ArenaWatcher:
   - определить ChoicesChangedEventArgs;
   - добавить onChoicesChanged;
   - вызывать событие после получения нового набора choices;
   - вызывать отдельное событие или передавать состояние при закрытии предложения.

2. В Watchers.initialize():
   - подписать HearthArenaFeatureBootstrap на ArenaWatcher.

3. В WindowManager/AppDelegate:
   - создать и зарегистрировать ArenaOverlayController.

4. В Settings/Preferences:
   - добавить небольшой раздел HearthArena.

Вся бизнес-логика должна находиться в HearthArenaOverlay, а upstream-классы не должны знать о формате данных HearthArena.

### 5.3. Доменная модель

Пример внутренней модели предложения:

~~~swift
struct ArenaOffer {
    let offerVersion: Int
    let draftSlot: Int
    let heroClass: String
    let isUnderground: Bool
    let cards: [OfferedCard]
    let packages: [[OfferedCard]]
}

struct OfferedCard {
    let cardId: String
    let dbfId: Int?
    let englishName: String
}

struct RatedCard {
    let card: OfferedCard
    let score: Int?
    let sourceStatus: RatingStatus
}
~~~

UI не должна работать непосредственно с MirrorCard. Это уменьшит зависимость от изменений типов upstream.

## 6. Получение и сопоставление рейтингов

### 6.1. Источник данных

Источник MVP:

~~~text
https://www.heartharena.com/tierlist
~~~

Использовать HTTPS GET без авторизации и cookies. Не выполнять запрос при каждом предложении карт.

### 6.2. Обновление данных

Алгоритм:

1. При запуске загрузить последний валидный локальный snapshot.
2. Если snapshot отсутствует или старше 24 часов, фоново запросить страницу.
3. Распарсить ответ во временную структуру.
4. Выполнить валидацию.
5. Только после успешной валидации атомарно заменить кэш.
6. При любой ошибке продолжить использовать предыдущий snapshot.

Добавить кнопку Refresh now и отображение:

- времени последнего успешного обновления;
- количества рейтингов;
- версии парсера;
- состояния Fresh, Stale или Invalid;
- последней ошибки без чувствительных данных.

### 6.3. Формат локального snapshot

~~~json
{
  "schemaVersion": 1,
  "parserVersion": 1,
  "source": "https://www.heartharena.com/tierlist",
  "fetchedAt": "2026-07-19T00:00:00Z",
  "contentHash": "...",
  "ratings": [
    {
      "heroClass": "MAGE",
      "cardName": "Example Card",
      "score": 92
    }
  ]
}
~~~

В приложение желательно включить bundled last-known-good snapshot. Он нужен для первого запуска без сети. Snapshot следует считать резервным, а не основным источником.

### 6.4. Сопоставление карт

Основной идентификатор в HSTracker — card ID/dbfId. HearthArena на публичной странице представляет карту прежде всего названием. Поэтому сопоставление выполняется в два этапа:

1. HSTracker card ID или dbfId преобразуется во внутреннюю английскую карточную запись.
2. Английское название и класс сопоставляются с нормализованной записью HearthArena.

Нормализация должна учитывать:

- HTML entities;
- типографские и обычные апострофы;
- тире разных типов;
- повторные пробелы;
- регистр;
- пробелы в начале и конце;
- специальные символы в названиях;
- классовые и neutral-варианты оценки.

Правило lookup:

1. точное совпадение heroClass + canonicalName;
2. классовая оценка neutral-карты для текущего героя;
3. neutral + canonicalName;
4. отсутствие результата.

Нечёткое сопоставление в runtime не использовать: неправильная оценка хуже отсутствующей. Для неизвестной карты показывать тире и записывать диагностический event.

Целевая полнота сопоставления:

- не менее 99,5% карт текущей ротации;
- 100% карт в ручном тестовом наборе;
- отсутствие неоднозначных автоматических matches.

### 6.5. Валидация загруженной tier list

Snapshot считается валидным, если:

- HTTP-ответ успешен;
- найдены ожидаемые игровые классы;
- количество записей выше безопасного минимального порога;
- каждая оценка находится в допустимом числовом диапазоне;
- нет критического количества дубликатов;
- покрытие текущей карточной базы не упало резко относительно предыдущего snapshot;
- parser не получил пустые секции.

Если новая версия не проходит проверку, она не заменяет рабочую.

## 7. Arena-события и управление состоянием

### 7.1. Событие нового предложения

Уникальность предложения определяется комбинацией:

- choices.version;
- arena currentSlot;
- isUnderground;
- списка card IDs/packages.

Повторное событие с тем же ключом игнорируется.

### 7.2. Состояния функции

~~~mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Loading: Arena draft detected
    Loading --> Visible: Ratings resolved
    Visible --> Hidden: Card picked
    Hidden --> Loading: Next offer
    Visible --> Idle: Draft closed
    Loading --> Offline: No valid data
    Offline --> Loading: Refresh succeeds
~~~

### 7.3. Требования к поведению

- UI обновляется только на main thread.
- Предыдущее предложение никогда не остаётся поверх нового.
- Оверлей скрывается при выходе из Arena, закрытии окна Hearthstone и смене scene.
- При отсутствии оценки показывается тире, а не ноль.
- При отсутствии сети используется кэш.
- Ошибка HearthArena не должна мешать основной работе HSTracker.
- Исключение или ошибка парсера не должны приводить к падению приложения.

## 8. Оверлей

### 8.1. MVP-интерфейс

Для каждой из трёх карт:

- крупный score;
- цвет score/tier;
- небольшой номер места: 1, 2 или 3;
- опциональная подпись HearthArena.

Рекомендуемый MVP — компактные плавающие badges над верхней частью карт. Они не должны закрывать название, стоимость и текст.

### 8.2. Технические свойства окна

- NSPanel без рамки;
- прозрачный фон;
- always-on-top относительно Hearthstone;
- click-through;
- не получает keyboard focus;
- корректно работает в windowed и fullscreen режимах;
- привязывается к координатам окна Hearthstone;
- масштабируется с разрешением и Retina scale;
- скрывается, когда Hearthstone неактивен, если включена соответствующая настройка.

По возможности использовать существующие механизмы позиционирования overlay в HSTracker, а не создавать независимый поиск окна.

### 8.3. Настройки

Минимальный набор:

- Enable HearthArena ratings;
- Show rank 1–3;
- Use tier colors;
- Overlay scale;
- Vertical offset;
- Refresh tier list;
- Reset overlay position;
- Show data status.

### 8.4. Legendary Groups и packages

ArenaWatcher уже получает packages. Публичная tier list содержит оценки отдельных карт, но не гарантирует корректную общую оценку package.

Безопасное поведение:

- обнаруживать package отдельно;
- показывать оценки входящих карт как список;
- не рассчитывать среднее и не присваивать package место без утверждённого продуктового правила;
- помечать режим как Individual card scores.

Полноценное ранжирование packages вынести после MVP.

## 9. Стратегия тонкого форка

### 9.1. Remotes и ветки

~~~text
upstream -> HearthSim/HSTracker
origin   -> наш fork

upstream-sync -> чистое состояние upstream/master
main          -> стабильный форк с HearthArena Overlay
feature/*     -> рабочие ветки
sync/*        -> ветки очередного обновления upstream
~~~

В upstream-sync запрещены собственные изменения.

### 9.2. Первичная настройка

~~~bash
git remote add upstream https://github.com/HearthSim/HSTracker.git
git fetch upstream

git switch -c upstream-sync upstream/master
git push -u origin upstream-sync

git switch -c main
git push -u origin main
~~~

### 9.3. Ручная синхронизация

~~~bash
git fetch upstream

git switch upstream-sync
git merge --ff-only upstream/master
git push origin upstream-sync

git switch -c sync/hstracker-X.Y.Z main
git merge upstream-sync

# resolve conflicts if any
# build and test
# open PR into main
~~~

Для общего репозитория merge предпочтительнее rebase: он не требует force push и лучше подходит для автоматических sync-PR.

### 9.4. Правила, уменьшающие конфликты

- Не форматировать массово upstream-файлы.
- Не переименовывать upstream-типы без необходимости.
- Не проводить несвязанные рефакторинги.
- Каждый touch upstream-файла должен иметь понятную интеграционную причину.
- Держать adapter boundary между MirrorCard и доменной моделью.
- Не смешивать синхронизацию upstream и разработку функции в одном PR.
- Регулярно синхронизироваться, не накапливая десятки релизов отставания.
- После принятия upstream-аналога удалять собственный патч, а не поддерживать дубликат.

### 9.5. Возможный upstream PR

Можно предложить официальному проекту нейтральное событие Arena choices без интеграции HearthArena. Если callback будет принят, поверхность нашего форка уменьшится.

Принятие такого PR следует считать бонусом, а не зависимостью проекта.

## 10. Три независимые схемы обновления

### 10.1. Обновление кода HSTracker

Цель: получать исправления совместимости с Hearthstone, новые карточные механики и обновления HearthMirror.

Процесс:

1. Scheduled workflow проверяет upstream.
2. При появлении новых commits или release создаёт sync-ветку.
3. Обновляет upstream-sync fast-forward merge.
4. Вливает upstream-sync в sync-ветку на основе main.
5. Открывает PR.
6. CI собирает приложение и запускает тесты.
7. Разработчик разрешает конфликты, если они есть.
8. Выполняется ручной smoke test с Hearthstone.
9. PR вливается в main.
10. Создаётся наш release.

Не следует автоматически публиковать сборку сразу после upstream merge: успешная компиляция не гарантирует корректность memory reading и overlay.

### Ожидаемая стоимость сопровождения

| Сценарий | Ожидаемая работа |
|---|---:|
| Upstream не затронул интеграционные точки | 15–60 минут |
| Изменены MirrorCard/ArenaWatcher/WindowManager | 1–4 часа |
| Крупная перестройка проекта или Swift toolchain | от половины дня |
| Срочный Hearthstone patch | синхронизация сразу после официального исправления |

### 10.2. Обновление данных HearthArena

Цель: получать новые оценки без выпуска новой версии приложения.

Процесс:

1. Проверка кэша при запуске.
2. Не более одного фонового запроса в 24 часа.
3. Парсинг и валидация.
4. Атомарная публикация snapshot.
5. Fallback на последний валидный snapshot.
6. Отображение возраста данных пользователю.

Дополнительный nightly CI-тест может скачивать актуальную страницу и проверять, что parser всё ещё работает. При поломке создаётся issue, но пользовательский кэш не перезаписывается.

### 10.3. Обновление самого HSTracker Arena

Официальный HSTracker использует Sparkle и официальный appcast, указанный в [Info.plist](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/Info.plist). Форк не должен продолжать использовать этот feed и ключ HearthSim.

### Этап A: личный MVP

- удалить SUFeedURL официального приложения либо отключить проверки;
- публиковать HSTracker-Arena.app.zip в GitHub Releases;
- устанавливать новую версию вручную поверх старой;
- хранить минимум один предыдущий рабочий release.

### Этап B: собственное автообновление

- создать собственный Sparkle appcast;
- создать собственные ключи подписи Sparkle;
- публиковать signed update artifact;
- добавить stable update channel;
- показывать upstream version и fork revision;
- проверять upgrade и rollback на отдельной машине/пользовательском профиле.

Рекомендуемый формат версии:

~~~text
<upstream-version>-ha.<fork-revision>

3.6.1-ha.1
3.6.1-ha.2
3.6.2-ha.1
~~~

## 11. CI/CD

### 11.1. Проверки каждого PR

- сборка Debug;
- сборка Release без подписи или с CI development signature;
- существующие HSTracker tests;
- HearthArena parser tests на зафиксированных HTML fixtures;
- CardIdentityResolver tests;
- TierListCache tests;
- Arena state-machine tests;
- проверка отсутствия официального SUFeedURL в release-конфигурации форка;
- проверка корректного Bundle ID;
- проверка формирования версии.

### 11.2. Scheduled jobs

1. Upstream check:
   - ежедневно или раз в неделю;
   - создаёт sync PR только при изменениях.

2. HearthArena parser health:
   - один раз в сутки;
   - скачивает страницу;
   - парсит без публикации;
   - проверяет число классов и записей;
   - создаёт issue при деградации.

### 11.3. Release workflow

1. Tag формата v3.6.2-ha.1.
2. xcodebuild archive на macOS runner.
3. Подпись Developer ID, если настроена.
4. Notarization, если приложение распространяется вне личной машины.
5. Создание zip.
6. SHA-256 checksum.
7. GitHub Release с upstream changelog и fork changelog.
8. Позже — обновление собственного Sparkle appcast.

Apple Developer ID и notarization не нужны для первого локального прототипа, но нужны для удобной публичной установки без предупреждений Gatekeeper.

## 12. Миграция и удаление официального HSTracker

### 12.1. Порядок перехода

1. Закрыть Hearthstone и официальный HSTracker.
2. Создать резервную копию Application Support.
3. Экспортировать preferences.
4. Собрать и запустить форк.
5. Проверить существующие колоды, историю и настройки.
6. Провести один обычный матч.
7. Провести тестовый Arena-драфт.
8. Только после этого удалить HSTracker.app.
9. Не удалять Application Support и preferences до окончания периода проверки.

Пример резервного копирования:

~~~bash
mkdir -p "$HOME/Documents/HSTracker-backup"
cp -a "$HOME/Library/Application Support/HSTracker" "$HOME/Documents/HSTracker-backup/"
defaults export net.hearthsim.hstracker "$HOME/Documents/HSTracker-backup/net.hearthsim.hstracker.plist"
~~~

Файл preferences может содержать токены HSReplay. Резервную копию не следует публиковать или добавлять в Git.

### 12.2. Rollback

Если форк не работает:

1. закрыть форк;
2. установить последнюю официальную версию;
3. вернуть резервную копию Application Support только при повреждении данных;
4. импортировать preferences при необходимости;
5. зафиксировать логи и версию форка до повторной попытки.

## 13. Тестирование

### 13.1. Unit tests

#### HTML parser

- все игровые классы;
- neutral section;
- HTML entities;
- апострофы и тире;
- новые/изменённые badges;
- дубликаты;
- пустая страница;
- частично изменённый DOM;
- некорректные scores.

#### Card identity

- точный class match;
- neutral-карта с классовой оценкой;
- neutral fallback;
- неизвестная карта;
- одинаковое название в разных контекстах;
- русская локализация Hearthstone при английском canonical name.

#### Cache

- первый запуск;
- fresh cache;
- stale cache;
- успешное обновление;
- network failure;
- invalid new snapshot;
- атомарная замена;
- bundled fallback.

#### State machine

- новое предложение;
- повтор того же события;
- выбор карты;
- переход к следующему слоту;
- закрытие драфта;
- смена обычной Arena на Underground;
- отсутствие ratings;
- packages.

### 13.2. Integration tests

- искусственное событие ArenaWatcher с тремя MirrorCard;
- преобразование в ArenaOffer;
- lookup рейтингов;
- формирование view model;
- показ и скрытие окна;
- ошибка источника данных не влияет на основной tracker;
- upstream типы проходят через единственный adapter.

### 13.3. Ручная матрица

| Область | Проверки |
|---|---|
| Режим Hearthstone | обычная Arena, Underground Arena, constructed match |
| Окно | fullscreen, windowed, изменение размера |
| Экран | Retina, внешний монитор, перенос между мониторами |
| Язык | русский и английский клиент |
| Сеть | онлайн, offline, медленный ответ, ошибка сервера |
| Данные | fresh, stale, bundled fallback, неизвестная карта |
| Жизненный цикл | запуск до Hearthstone, запуск после Hearthstone, restart |
| Обновление | upgrade форка, upstream sync, rollback |

## 14. Диагностика

Добавить в Preferences диагностический блок:

- HSTracker upstream version;
- fork revision;
- текущий Arena state;
- текущий offer version;
- возраст tier list;
- число записей;
- match coverage;
- количество неизвестных карт;
- последнее успешное обновление;
- последняя безопасно сформулированная ошибка;
- кнопки Refresh data, Open logs и Reset HearthArena cache.

Логи должны содержать:

- переходы состояний;
- card IDs и canonical names неизвестных карт;
- результат обновления snapshot;
- причины отказа валидации;
- показ/скрытие overlay;
- версию parser/schema.

Не логировать cookies, OAuth-токены и другие секреты.

## 15. Безопасность, приватность и использование данных

- Функция должна быть read-only.
- Она не должна нажимать карты или отправлять команды Hearthstone.
- Для рейтингов не нужны логин и пароль HearthArena.
- Не хранить cookies HearthArena.
- Ограничить частоту запросов.
- Показывать attribution и ссылку на HearthArena.
- До публичного распространения проверить разрешение на перераспространение рейтингов.
- Не выдавать базовые scores за полный динамический совет HearthArena.
- При публикации проекта явно указать, что он не аффилирован с HearthArena, HearthSim и Blizzard.

## 16. Этапы реализации

### Этап 0. Базовый форк и воспроизводимая сборка

**Оценка:** 1–2 рабочих дня.

- [ ] Создать GitHub fork.
- [ ] Добавить upstream remote.
- [ ] Создать upstream-sync и main.
- [ ] Собрать неизменённый HSTracker.
- [ ] Запустить его с текущей Hearthstone.
- [ ] Зафиксировать рабочую версию Xcode/macOS.
- [ ] Добавить базовый CI build.
- [ ] Выбрать имя и Bundle ID.
- [ ] Отключить официальный update feed.
- [ ] Описать резервное копирование пользовательских данных.

**Definition of Done:** чистый форк собирается, запускается и отслеживает обычный матч так же, как официальный HSTracker.

### Этап 1. Технический spike Arena choices

**Оценка:** 1–2 рабочих дня.

- [ ] Добавить ChoicesChangedEventArgs.
- [ ] Подключить callback в ArenaWatcher.
- [ ] Логировать class, slot и card IDs.
- [ ] Проверить три последовательных предложения.
- [ ] Проверить скрытие после выбора.
- [ ] Проверить обычную и Underground Arena.

**Definition of Done:** без OCR получены стабильные идентификаторы карт каждого нового предложения.

### Этап 2. HearthArena data provider

**Оценка:** 2–3 рабочих дня.

- [ ] Сохранить HTML fixtures.
- [ ] Реализовать parser.
- [ ] Реализовать нормализацию названий.
- [ ] Реализовать class-aware lookup.
- [ ] Реализовать snapshot schema.
- [ ] Реализовать валидацию и атомарный cache.
- [ ] Добавить bundled fallback.
- [ ] Добавить parser и mapping tests.

**Definition of Done:** для тестового набора карт возвращаются корректные публичные scores, offline fallback работает.

### Этап 3. MVP overlay

**Оценка:** 2–4 рабочих дня.

- [ ] Реализовать view model.
- [ ] Создать click-through NSPanel.
- [ ] Разместить три badges.
- [ ] Добавить colors и rank.
- [ ] Синхронизировать показ со state machine.
- [ ] Проверить windowed/fullscreen.
- [ ] Обработать неизвестные карты.

**Definition of Done:** при каждом обычном предложении автоматически показываются правильные оценки и исчезают после выбора.

### Этап 4. Настройки, миграция и надёжность

**Оценка:** 2–4 рабочих дня.

- [ ] Добавить настройки overlay.
- [ ] Добавить data status и manual refresh.
- [ ] Добавить одноразовую миграцию UserDefaults.
- [ ] Добавить diagnostics.
- [ ] Обработать packages без ложного агрегирования.
- [ ] Выполнить ручную тестовую матрицу.
- [ ] Проверить отсутствие регрессий основного tracker.

**Definition of Done:** форк пригоден для постоянного личного использования.

### Этап 5. Обновления и release pipeline

**Оценка:** 2–4 рабочих дня.

- [ ] Добавить scheduled upstream check.
- [ ] Автоматизировать sync PR.
- [ ] Добавить nightly parser health check.
- [ ] Добавить release versioning.
- [ ] Публиковать zip и checksum.
- [ ] Описать smoke test и rollback.
- [ ] При необходимости настроить Developer ID/notarization.
- [ ] Позже настроить собственный Sparkle feed.

**Definition of Done:** новая версия upstream подхватывается воспроизводимо, а обновление форка не зависит от официального appcast.

## 17. Оценка трудозатрат

| Результат | Оценка |
|---|---:|
| Технический proof of concept | 2–3 дня |
| Минимальный рабочий overlay | 4–7 дней |
| Надёжная личная версия | 8–14 рабочих дней |
| Подписанный публичный релиз с автообновлением | дополнительно 3–7 дней |

Оценка предполагает знакомство разработчика со Swift и macOS UI. Основная неопределённость связана не с HearthArena, а со сборкой, подписью и позиционированием overlay в разных режимах окна.

## 18. Риски и способы снижения

| Риск | Вероятность | Влияние | Мера |
|---|---:|---:|---|
| HearthArena меняет HTML | Средняя | Высокое | fixtures, строгая валидация, last-known-good cache, nightly test |
| Название карты не сопоставилось | Средняя | Среднее | English canonical names, class-aware lookup, coverage report |
| Показана оценка другой карты | Низкая | Высокое | только exact normalized match, без runtime fuzzy matching |
| Upstream изменяет ArenaWatcher | Средняя | Среднее | тонкий adapter, частые sync PR |
| Hearthstone patch ломает memory reading | Средняя | Высокое | быстро подтягивать исправление официального HSTracker |
| Официальный updater заменяет форк | Высокая без исправления | Высокое | уникальный Bundle ID, удалить официальный SUFeedURL/key |
| Потеря пользовательских данных | Низкая | Высокое | backup до удаления, reuse Application Support, rollback |
| Gatekeeper блокирует сборку | Средняя | Среднее | локальная подпись; Developer ID и notarization для релиза |
| Package получает вводящую в заблуждение оценку | Средняя | Среднее | показывать individual scores без агрегата |
| Вопросы лицензирования рейтингов | Неизвестная | Высокое для публикации | личное использование, attribution, согласование перед массовой дистрибуцией |

## 19. Критерии готовности первой постоянной версии

- [ ] Официальный HSTracker больше не нужен для запуска.
- [ ] Существующие колоды и реплеи доступны.
- [ ] Форк проходит обычный tracking smoke test.
- [ ] Не менее 99,5% актуальных карт сопоставляются.
- [ ] Оценки появляются не позднее одной секунды после предложения.
- [ ] Оверлей не блокирует клики.
- [ ] Оверлей скрывается после выбора и вне Arena.
- [ ] Offline fallback работает.
- [ ] Ошибка HearthArena не роняет HSTracker.
- [ ] Официальный Sparkle feed отключён.
- [ ] Upstream sync воспроизводим через отдельный PR.
- [ ] Есть предыдущий release и проверенный rollback.
- [ ] В интерфейсе видны версия данных и время их обновления.

## 20. Открытые решения перед началом реализации

Рекомендуемые значения отмечены первыми:

1. **Имя приложения:** HSTracker Arena.
2. **Репозиторий:** сначала private, открыть после проверки условий использования данных.
3. **Bundle ID:** уникальный namespace владельца.
4. **Данные HSTracker:** использовать существующий Application Support после backup.
5. **Preferences:** одноразовый allowlist-импорт.
6. **Обновление MVP:** ручные GitHub Releases.
7. **Автообновление:** собственный Sparkle feed после стабилизации.
8. **Packages:** individual scores без итогового ранга.
9. **Публичная дистрибуция:** только после проверки прав на использование рейтингов.

## 21. Итоговый порядок работ

1. Создать тонкий форк и доказать воспроизводимую сборку.
2. Сразу отделить идентичность и обновления форка от официального приложения.
3. Получить и протестировать Arena choices.
4. Реализовать надёжный HearthArena parser/cache.
5. Соединить их через доменный adapter.
6. Добавить минимальный overlay.
7. Провести миграцию пользовательских данных.
8. Довести диагностику и тестирование.
9. Автоматизировать подготовку upstream updates.
10. После стабильного личного использования добавить собственное автообновление.

## 22. Ссылки

- [Официальный репозиторий HSTracker](https://github.com/HearthSim/HSTracker)
- [ArenaWatcher.swift](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/HearthWatcher/ArenaWatcher.swift)
- [Watchers.swift](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/Hearthstone/Watchers.swift)
- [Paths.swift](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/Core/Paths.swift)
- [Settings.swift](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/Core/Settings.swift)
- [Info.plist с официальным Sparkle feed](https://github.com/HearthSim/HSTracker/blob/master/HSTracker/Info.plist)
- [Публичная HearthArena tier list](https://www.heartharena.com/tierlist)
- [HearthArena Companion](https://www.heartharena.com/app)
- [Arena Tracker — пример macOS-приложения с HearthArena tier list](https://github.com/supertriodo/Arena-Tracker)
