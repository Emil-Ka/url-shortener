# Неделя 1: User Service

Вся домашка первой недели описана в этом одном файле: теория → контракт → пошаговый план.

## Цель

Создать User Service — gRPC-сервис для регистрации, аутентификации и управления подписками пользователей.

> На этой неделе делаем **только User Service**. В теории и на схемах ниже встретится **Gateway** — это публичный REST-вход, который соберём на третьей неделе. Пока достаточно понимать: кто-то снаружи по gRPC зовёт методы User Service. На этой неделе «кем-то» будет утилита `grpcurl` (ей и проверяем).

---

## Как это работает (теория, коротко)

Прочитай перед кодом — дальше будут решения «потому что так договорились», и важно понимать, откуда они.

### Токены и сессия

- **Access token** — JWT, живёт 15 минут. **Refresh token** — JWT, живёт 7 дней. Оба несут `user_id` и `session_id` (`sid`).
- **Сессия** — строка в таблице `sessions` (Postgres = источник правды) плюс кеш в Redis. Токены привязаны к сессии через `sid`.
- **Один вход (Login) = одна сессия.** Зашёл из другого браузера — вторая, независимая сессия со своим `sid`.
- **Logout** помечает сессию `is_revoked = true` и убирает из кеша. Оба токена этой сессии сразу перестают работать (оба несут её `sid`, а сессия мертва). Другие сессии живут.

> 15 минут / 7 дней — индустриальная норма: короткий access, длинный refresh. Короче access = чаще refresh; длиннее = дольше живёт украденный токен.

### Проверка и мгновенный отзыв

На каждый защищённый запрос Gateway зовёт `User.ValidateSession`: проверяем подпись JWT + `exp`, затем по `sid` смотрим, жива ли сессия — сначала Redis `session:{sid}`, при промахе Postgres (`is_revoked = false`, не истекла).

Refresh работает так же: когда access истёк, клиент шлёт refresh, мы убеждаемся, что сессия жива по `sid`, и выдаём новый access. `sid` не меняется.

### JWT вкратце

JWT — это три base64-куска через точку: `header.payload.signature`. Payload (claims) — читаемый JSON, секреты туда не кладём; целостность гарантирует подпись `HMAC-SHA256` нашим `JWT_SECRET`. Подделать токен без секрета нельзя.

Claims access-токена:

```json
{
  "sub": "550e8400-...",   // user_id
  "sid": "7c9e6679-...",   // session_id
  "iat": 1735689600,        // когда выпущен
  "exp": 1735690500,        // iat + 15 минут
  "iss": "url-shortener-user"
}
```

Refresh — те же claims, но `exp = iat + 7 дней`. Email, план подписки и т.п. в токен НЕ кладём: они могут устареть за 15 минут, а источник правды — Postgres.

Клиент присылает access в заголовке `Authorization: Bearer <access_token>`. Подробнее про JWT — [RFC 7519](https://datatracker.ietf.org/doc/html/rfc7519).

### Пароли — bcrypt

В Postgres лежит `password_hash`, не пароль. Алгоритм — **bcrypt, cost 10** (`golang.org/x/crypto/bcrypt`): он медленный (≈100 мс) и сам генерирует соль, поэтому перебор по утёкшей базе невыгоден. SHA-256/MD5 не подходят — слишком быстрые, на GPU миллиарды хешей в секунду.

### Redis

Redis — это key-value хранилище, которое держит данные в оперативной памяти. Поэтому чтение/запись занимают доли миллисекунды — на порядки быстрее похода в Postgres. Используем его как **кеш** (горячие чтения) и для **каунтеров** (счётчиков). Источник правды всё равно Postgres/MongoDB; потеря Redis = потеря скорости, но не данных (сессии перепроверятся из Postgres).

Redis хранит значения разных типов; нам нужны два:
- **string** — обычная пара ключ → значение, можно с TTL (временем жизни). Кеш сессии.
- **каунтер** — та же string, но с атомарным инкрементом. Лимит активных ссылок (на второй неделе).

Ключи, которые заводим:

| Ключ | Тип | TTL | Зачем |
|------|-----|-----|-------|
| `session:{sid}` | string | 15 мин | кеш живой сессии (`= user_id`), горячий путь проверки |
| `counter:{user_id}` | каунтер | — | сколько активных ссылок у пользователя (на второй неделе) |

Команды Redis, которые встретятся ниже:

| Команда | Что делает |
|---------|-----------|
| `SET key val EX 900` | записать строку; ключ сам истечёт через 900 секунд (15 мин) |
| `GET key` | прочитать строку (вернёт пусто, если ключа нет или он истёк) |
| `DEL key` | удалить ключ |
| `INCR key` | атомарно увеличить каунтер на 1 (создаст ключ со значением 1, если его не было) |
| `DECR key` | атомарно уменьшить каунтер на 1 |

«Атомарно» в `INCR`/`DECR` означает: даже если 100 запросов придут одновременно, каждый получит своё уникальное значение, без гонки. Это пригодится для лимита ссылок на второй неделе.

### Поток (sequence-диаграммы)

Диаграммы в формате Mermaid — GitHub рендерит их автоматически.

**Login — создание сессии**

```mermaid
sequenceDiagram
    autonumber
    actor C as Client
    participant G as Gateway
    participant U as User Service
    participant P as Postgres
    participant R as Redis

    C->>G: POST /login {email, pwd}
    G->>U: Login(email, pwd)
    U->>P: SELECT users + bcrypt.Compare
    U->>P: INSERT sessions (sid, expires_at)
    U->>R: SET session sid = user_id (EX 15m)
    U-->>G: access + refresh
    G-->>C: 200 {access, refresh}
```

**Защищённый запрос — валидация на каждый запрос**

```mermaid
sequenceDiagram
    autonumber
    actor C as Client
    participant G as Gateway
    participant U as User Service
    participant P as Postgres
    participant R as Redis

    C->>G: POST /urls (Authorization Bearer access)
    G->>U: ValidateSession(access)
    U->>U: verify подпись + exp
    U->>R: GET session sid
    alt сессия в кеше
        R-->>U: user_id (hit)
    else промах кеша
        U->>P: SELECT session (is_revoked=false)
        P-->>U: сессия жива
        U->>R: SET session sid (прогрев, EX 15m)
    end
    U-->>G: user_id
    G-->>C: 201 {short_code}
```

**Logout — мгновенный отзыв**

```mermaid
sequenceDiagram
    autonumber
    actor C as Client
    participant G as Gateway
    participant U as User Service
    participant P as Postgres
    participant R as Redis

    C->>G: POST /logout (Bearer access)
    G->>U: Logout(access)
    U->>P: UPDATE sessions SET is_revoked=true WHERE id=sid
    U->>R: DEL session sid
    U-->>G: ok
    G-->>C: 200 {}

    Note over C,R: тот же access сразу после logout
    C->>G: POST /urls (Bearer access)
    G->>U: ValidateSession(access)
    U->>R: GET session sid
    R-->>U: MISS (ключ удалён)
    U->>P: SELECT session
    P-->>U: is_revoked=true
    U-->>G: UNAUTHENTICATED
    G-->>C: 401 — сессия отозвана
```

**Refresh — access истёк по времени**

```mermaid
sequenceDiagram
    autonumber
    actor C as Client
    participant G as Gateway
    participant U as User Service
    participant P as Postgres

    C->>G: POST /refresh {refresh}
    G->>U: RefreshToken(refresh)
    U->>U: verify подпись + exp -> sid
    U->>P: SELECT session by sid (жива?)
    alt сессия жива
        U->>U: sign НОВЫЙ access (sid тот же)
        U-->>G: новый access
        G-->>C: 200 {access}
    else сессия отозвана / истекла
        U-->>G: UNAUTHENTICATED
        G-->>C: 401
    end
```

---

## Что нужно сделать (пошагово)

Делай шаги по порядку. У каждого в конце — **Проверка**: как убедиться, что шаг закрыт.

Как пользоваться заданием:
- **Пишешь в своём репозитории.** Этот файл и папка `boilerplates/` лежат в скачанном шаблоне (`url-shortener-template`). Свой код держишь в отдельном репозитории и копируешь в него boilerplate из шаблона. Как разложить две папки — см. [README, раздел «С чего начать»](../README.md#с-чего-начать).
- **Код пишешь сам** — это и есть смысл: `.proto`-контракт и весь Go-код руками. Готовые ответы для самопроверки (когда реально застрял) лежат в соседнем файле [`answers.md`](answers.md).
- **Команды и конфиги можно копировать** — установка инструментов, `buf generate`, `migrate`, docker и т.п. Их зубрить не нужно.
- Готовые инфра-файлы (go.work, Makefile, docker-compose, .golangci, .mockery, buf.yaml/buf.gen.yaml, `user/.env.template`) лежат в `boilerplates/` — их копируешь как есть. У каждого сервиса свой `.env`.

### Шаг 0. Установить инструменты

Один раз на машину. Проверь, что всё стоит:

```bash
go version                 # нужен Go 1.23+
docker --version
docker compose version

# buf — инструмент для работы с protobuf (компиляция, линт, генерация).
# В нём уже встроен компилятор proto, отдельный protoc не нужен.
brew install bufbuild/buf/buf

# плагины генерации Go-кода (buf вызывает их из $PATH)
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# миграции, линтер, моки, ручное тестирование gRPC
brew install golang-migrate golangci-lint grpcurl
go install github.com/vektra/mockery/v2@latest
```

Добавь `$(go env GOPATH)/bin` в `PATH` (например, строкой `export PATH="$PATH:$(go env GOPATH)/bin"` в `~/.zshrc` или `~/.bashrc`), иначе `protoc-gen-go`, `mockery` не найдутся.

> Команды `brew install` — для macOS (Homebrew). На Linux ставь через свой пакетный менеджер (`apt`, `dnf`...) или скачивай готовые бинарники: у `buf`, `golang-migrate`, `grpcurl` они есть в релизах на GitHub. Инструменты, которые ставятся через `go install`, одинаковы на всех ОС.

**Проверка:** `buf --version`, `migrate -version`, `mockery --version` отвечают без ошибок.

### Шаг 1. Инициализация монорепо

Монорепо на Go Workspaces: один репозиторий, несколько Go-модулей, объединённых файлом `go.work`. Каждый сервис — отдельный модуль в корне (`user/`, позже `url/`, `gateway/`...), а контракты всех сервисов лежат в общем модуле `shared/`.

1. Создай корневую папку и репозиторий. Это **твой** проект, отдельная папка рядом со скачанным `url-shortener-template`:
   ```bash
   mkdir url-shortener && cd url-shortener
   git init
   ```
2. Создай дерево папок:
   ```bash
   mkdir -p user/cmd user/internal user/migrations
   mkdir -p shared/proto/user/v1
   ```
3. Инициализируй два модуля (замени `yourname` на свой github-логин):
   ```bash
   (cd user   && go mod init github.com/yourname/url-shortener/user)
   (cd shared && go mod init github.com/yourname/url-shortener/shared)
   ```
4. Создай `go.work` в корне:
   ```bash
   go work init ./user ./shared
   ```
   Благодаря `go.work` модуль `user` видит `shared` локально (без публикации в git/прокси).
5. Скопируй готовые файлы из шаблона (`../url-shortener-template/week1/boilerplates/`) в корень своего репозитория: `.gitignore`, `.golangci.yml`, `.mockery.yaml`, `Makefile`, `docker-compose.yml`. Конфиги buf — в `shared/proto/`: `buf.yaml`, `buf.gen.yaml`. И `user/.env.template` → переименуй в `user/.env` (у каждого сервиса свой `.env` со своими переменными).

Должно получиться:
```
url-shortener/
├── go.work                       (use ./user ./shared)
├── Makefile
├── docker-compose.yml
├── shared/                       (модуль …/shared — контракты)
│   ├── go.mod
│   └── proto/
│       ├── buf.yaml
│       ├── buf.gen.yaml
│       └── user/v1/              (сюда напишешь user.proto)
└── user/                         (модуль …/user — сервис)
    ├── go.mod
    ├── .env                      (конфиг ТОЛЬКО User Service)
    ├── cmd/
    ├── internal/
    └── migrations/
```

Почему так (по аналогии с реальными проектами): сервисы — независимые модули в корне; контракты вынесены в `shared`, чтобы их импортировал и сервер (User), и будущие клиенты (Gateway, URL). Версия `v1` в пути и пакете заложена сразу — когда появится несовместимая `v2`, старые клиенты продолжат жить на `v1`.

**Проверка:** `go work sync` отрабатывает без ошибок.

### Шаг 2. Контракт: описать `.proto` самому и сгенерировать Go-код

gRPC работает так: ты описываешь сервис и сообщения в `.proto`-файле, а `buf` генерирует из него Go-код (структуры запросов/ответов, интерфейс сервера, клиент). **Этот `.proto` ты пишешь сам** — это и есть навык, который тренируем. Если совсем застрял — эталон лежит в [`answers.md`](answers.md), но сначала попробуй сам.

#### Контракт `UserService`

Опиши в `shared/proto/user/v1/user.proto` сервис `UserService` с шестью методами. Вот что каждый принимает и отдаёт (раздел «Поведение» понадобится позже, в Шагах 8-9):

**Register** — создаёт пользователя + базовую подписку в одной транзакции.
- Запрос: `email` (string), `password` (string)
- Ответ: `user_id` (string)
- Ошибки: `ALREADY_EXISTS` (email занят), `INVALID_ARGUMENT` (невалидный email / короткий пароль)
- Поведение: валидация → bcrypt(pwd) → транзакция `INSERT users` + `INSERT subscriptions` (plan=`basic`, links_limit=1000) → вернуть `user_id`

**Login** — аутентифицирует и создаёт новую сессию.
- Запрос: `email` (string), `password` (string)
- Ответ: `access_token` (string, JWT 15 мин), `refresh_token` (string, JWT 7 дней)
- Ошибки: `NOT_FOUND`, `UNAUTHENTICATED` (неверный пароль)
- Поведение: найти юзера → `bcrypt.Compare` → создать сессию (`sid`, `expires_at = now + 7д`) → подписать access + refresh → `SET session:{sid}=user_id EX 15m` → вернуть оба токена

**Logout** — гасит одну сессию.
- Запрос: `session_id` (string; gateway достаёт `sid` из claims access-токена)
- Ответ: пустой
- Поведение: `UPDATE sessions SET is_revoked=true WHERE id=sid` + `DEL session:{sid}`

**ValidateSession** — проверяет access (Gateway зовёт на каждый защищённый запрос).
- Запрос: `access_token` (string)
- Ответ: `user_id` (string), `session_id` (string)
- Ошибки: `UNAUTHENTICATED`
- Поведение: проверить подпись + `exp` → достать `sid` → `GET session:{sid}` (промах → Postgres `is_revoked=false AND expires_at>now`, прогреть кеш) → вернуть `user_id` / `session_id`

**RefreshToken** — новый access по refresh.
- Запрос: `refresh_token` (string)
- Ответ: `access_token` (string)
- Ошибки: `UNAUTHENTICATED`
- Поведение: проверить подпись + `exp` → `sid` → сессия жива? → подписать новый access → продлить кеш. Refresh не меняется.

**GetLimit** — лимит подписки (зовёт `URLService` на второй неделе).
- Запрос: `user_id` (string)
- Ответ: `links_limit` (int32)
- Ошибки: `NOT_FOUND`
- Поведение: `SELECT links_limit FROM subscriptions WHERE user_id=?`

#### Что прописать в `.proto`

- `syntax = "proto3";` и `package user.v1;` (версия `v1` прямо в имени пакета).
- `option go_package = "github.com/yourname/url-shortener/shared/pkg/proto/user/v1;user_v1";` — указывает, в какой Go-пакет сложить сгенерированный код (в общий модуль `shared`, его импортируют и User Service, и потом Gateway). После `;` — имя Go-пакета (`user_v1`). Путь должен совпадать с модулем `shared`.
- `service UserService { ... }` с шестью `rpc` и парой `message` (Request/Response) на каждый метод. Типы полей: `string`, для `links_limit` — `int32`; пустой ответ — это просто `message LogoutResponse {}`.
- Числа после `=` (`string email = 1;`) — это **теги полей**: уникальные номера внутри сообщения, по ним поле кодируется в бинарь. Нумеруй с 1; после релиза теги не меняют (иначе сломается совместимость со старыми клиентами).

#### Сгенерировать код через buf

Конфиги `buf.yaml` и `buf.gen.yaml` уже лежат в `shared/proto/` (скопированы в Шаге 1). `buf.gen.yaml` говорит, какими плагинами и куда генерировать. Запуск завёрнут в `make proto-gen`:

```bash
cd shared/proto && buf generate
```

`buf.gen.yaml` (для понимания, что происходит):
```yaml
version: v2
clean: true                 # очистить прошлую генерацию
plugins:
  - local: protoc-gen-go      # структуры сообщений
    out: ../pkg/proto
    opt: [paths=source_relative]
  - local: protoc-gen-go-grpc # интерфейс сервера и клиент
    out: ../pkg/proto
    opt: [paths=source_relative]
```
`paths=source_relative` сохраняет структуру папок: `proto/user/v1/user.proto` → `pkg/proto/user/v1/`.

Появятся `shared/pkg/proto/user/v1/user.pb.go` и `user_grpc.pb.go` — их не редактируют руками, они перегенерируются.

**Проверка:** `make proto-gen` отрабатывает без ошибок, оба файла появились в `shared/pkg/proto/user/v1/`, `go build ./...` проходит. Если застрял — сверься с [`answers.md`](answers.md).

### Шаг 3. Поднять Postgres и Redis

1. Запусти инфраструктуру:
   ```bash
   make up        # = docker compose up -d
   ```
2. `docker-compose.yml` поднимает Postgres 16 и Redis 7 (порты 5432 и 6379). Логин/пароль/база Postgres заданы дефолтами прямо в compose (`postgres`/`postgres`/`url_shortener`) — они должны совпадать с `DATABASE_URL` в `user/.env`.

**Проверка** (через `docker compose exec` — не нужны локально установленные `psql`/`redis-cli`):
```bash
docker compose ps                                              # обе строки healthy
docker compose exec postgres psql -U postgres -d url_shortener -c '\conninfo'
docker compose exec redis redis-cli ping                       # PONG
```

### Шаг 4. Миграции и схема БД

Миграции — это версионированные SQL-файлы, которые приводят схему БД к нужному виду. Используем `golang-migrate`.

1. Создай пару файлов миграции:
   ```bash
   migrate create -ext sql -dir user/migrations -seq init_schema
   ```
   Появятся `000001_init_schema.up.sql` (применить) и `..._down.sql` (откатить).

2. В `up.sql` опиши три таблицы (схема — ниже). В `down.sql` — `DROP TABLE` в обратном порядке (`sessions`, `subscriptions`, `users`).

3. Применить:
   ```bash
   make migrate-up
   ```

4. На старте сервиса миграции тоже стоит применять автоматически — чтобы свежеподнятый сервис всегда имел актуальную схему. `golang-migrate` умеет работать как Go-библиотека:
   ```go
   m, err := migrate.New("file://user/migrations", cfg.DatabaseURL)
   if err != nil { /* ... */ }
   if err := m.Up(); err != nil && !errors.Is(err, migrate.ErrNoChange) {
       /* ErrNoChange = миграции уже применены, это не ошибка */
   }
   ```
   Вызови это в `main.go` после загрузки конфига (Шаг 9). `make migrate-up` остаётся для ручного применения.

#### Схема БД

**Таблица `users`** — зарегистрированные пользователи.

| Поле | Тип | Ограничения | Описание |
|------|-----|-------------|----------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | Идентификатор пользователя |
| email | VARCHAR(255) | UNIQUE, NOT NULL | Email (логин) |
| password_hash | VARCHAR(255) | NOT NULL | Хеш пароля (bcrypt) |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Время регистрации |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | Время последнего обновления |

**Таблица `subscriptions`** — подписка и лимиты. Один пользователь = одна подписка.

| Поле | Тип | Ограничения | Описание |
|------|-----|-------------|----------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | Идентификатор подписки |
| user_id | UUID | UNIQUE, NOT NULL, FK → users(id) ON DELETE CASCADE | Пользователь |
| plan | VARCHAR(50) | NOT NULL, DEFAULT 'basic' | Название тарифа |
| links_limit | INT | NOT NULL, DEFAULT 1000 | Лимит активных ссылок |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | |

Текущее использование (`links_used`) тут НЕ храним — число активных ссылок считается в Redis (каунтер `counter:{user_id}`) на второй неделе, источник правды — `COUNT` активных ссылок в MongoDB. В Postgres — только лимит.

**Таблица `sessions`** — активные сессии. У пользователя их может быть несколько (разные устройства).

| Поле | Тип | Ограничения | Описание |
|------|-----|-------------|----------|
| id | UUID | PRIMARY KEY, DEFAULT gen_random_uuid() | ID сессии (`sid` в JWT обоих токенов) |
| user_id | UUID | NOT NULL, FK → users(id) ON DELETE CASCADE | Владелец сессии |
| expires_at | TIMESTAMP | NOT NULL | Когда истечёт сессия (now + 7 дней) |
| is_revoked | BOOLEAN | NOT NULL, DEFAULT FALSE | Отозвана ли (Logout выставляет TRUE) |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | = время логина |
| updated_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | |

Индексы `sessions`: по `user_id` (поиск сессий юзера, аналитика), по `expires_at` (опционально, для cleanup-job).

Заметки:
- `gen_random_uuid()` доступна в PostgreSQL 13+ без расширений. У нас Postgres 16 — работает из коробки.
- Сам refresh-токен в БД не храним: он JWT, доверяем подписи. Жива сессия или нет — решают `is_revoked` + `expires_at`.
- `ON DELETE CASCADE`: при удалении пользователя сами удалятся его подписка и сессии (удаления юзера в задании нет, но FK настраиваем правильно).

**Транзакция регистрации** (Register оборачивает оба INSERT в одну транзакцию):
```sql
BEGIN;
  INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id;
  INSERT INTO subscriptions (user_id, plan, links_limit) VALUES ($3, 'basic', 1000);
COMMIT;
```
Если второй INSERT упал — ROLLBACK, пользователь не создаётся.

`make migrate-up` берёт `DATABASE_URL` из `user/.env` (Makefile подгружает его сам, см. boilerplate).

**Проверка:** после `make migrate-up` команда `docker compose exec postgres psql -U postgres -d url_shortener -c '\dt'` показывает три таблицы (`users`, `subscriptions`, `sessions`).

### Шаг 5. Конфиг (свой пакет `config`)

У каждого сервиса свой `.env`. У User Service это `user/.env` (скопирован из `user/.env.template` в Шаге 1) со следующими переменными:

| Переменная | Что это | Пример |
|------------|---------|--------|
| `DATABASE_URL` | строка подключения к Postgres (логин/пароль/база совпадают с дефолтами в `docker-compose.yml`) | `postgres://postgres:postgres@localhost:5432/url_shortener?sslmode=disable` |
| `REDIS_HOST` / `REDIS_PORT` | хост и порт Redis (один общий инстанс на все сервисы) | `localhost` / `6379` |
| `JWT_SECRET` | секрет для подписи/проверки JWT (знает только User Service) | случайная длинная строка |
| `ACCESS_TOKEN_TTL` | время жизни access-токена | `15m` |
| `REFRESH_TOKEN_TTL` | время жизни refresh-токена | `168h` (7 дней) |
| `USER_SERVICE_PORT` | порт, на котором слушает User Service (gRPC) | `50051` |

Сделай пакет `user/internal/config`, который читает эти переменные и отдаёт готовую структуру. Дальше весь код берёт настройки из неё, а не из `os.Getenv` напрямую.

1. Опиши структуру `Config` — поле под каждую настройку (строки для адресов/секретов; для TTL — `time.Duration`; адрес Redis собери из host+port в одно поле).
2. Напиши функцию `Load() (*Config, error)`:
   - подгрузи `.env` в окружение: `godotenv.Load("user/.env")` — Go сам файл не читает;
   - прочитай каждую переменную через `os.Getenv`;
   - обязательные (`DATABASE_URL`, `JWT_SECRET` и т.д.) — если пусто, верни ошибку с понятным текстом;
   - `ACCESS_TOKEN_TTL` / `REFRESH_TOKEN_TTL` распарси через `time.ParseDuration` (`"15m"`, `"168h"`);
   - верни заполненный `*Config`.

`main.go` вызовет `config.Load()` первым делом и дальше будет передавать `cfg` туда, где он нужен (Шаг 9).

> В реальных проектах env разбирают готовые либы (`github.com/caarlos0/env`, `viper`) по тегам структуры. Мы пишем сами, чтобы видеть механику.

**Проверка:** `config.Load()` возвращает заполненный конфиг; при отсутствии обязательной переменной — внятная ошибка.

### Шаг 6. Слои и внедрение зависимостей

Раздели код на слои. Каждый слой — структура со своим конструктором `New...(зависимости)`: зависимости приходят **снаружи** (через аргументы конструктора), а не создаются внутри. Сшиваются все слои в `main.go` (Шаг 9).

```
user/internal/
├── config/       # Config + Load()  (Шаг 5)
├── handler/      # gRPC-обработчики (тонкий слой)
├── service/      # бизнес-логика + интерфейсы repository/cache/auth
├── repository/   # Postgres (pgx)
├── cache/        # Redis (go-redis)
└── auth/         # JWT + bcrypt  (Шаг 7)
```

Правило: **интерфейсы объявляет тот, кто их использует.** Service сам описывает, какой репозиторий, кеш и `auth` ему нужны (интерфейсы лежат в `service`), а `repository`/`cache`/`auth` их реализуют. Конструкторы принимают интерфейсы/зависимости и возвращают конкретные структуры:
- `repository.New(pool)` — поверх пула Postgres
- `cache.New(rdb)` — поверх клиента Redis
- `service.New(repo, cache, auth)` — получает репозиторий, кеш и **`auth`** — это пакет из Шага 7 (подпись/проверка JWT + хеширование паролей bcrypt). Service зовёт у него `HashPassword`/`ComparePassword` (в Register/Login) и `SignAccess`/`SignRefresh`/`Parse` (в Login/Refresh/ValidateSession).
- `handler.New(svc)` — получает service

В `repository` нужны методы: создать пользователя+подписку **в транзакции** (см. ниже), найти пользователя по email, создать сессию, получить сессию по id, отозвать сессию (`is_revoked=true`), отдать лимит подписки.

В `cache` нужны: `SetSession(sid, userID, ttl)`, `GetSession(sid)`, `DelSession(sid)`.

#### Как написать транзакцию в Go (pgx)

Register должен создать пользователя **и** подписку атомарно — либо обе строки, либо ни одной. С `pgxpool` транзакция строится так:

```go
tx, err := r.pool.Begin(ctx)
if err != nil {
    return err
}
defer tx.Rollback(ctx) // не дошли до Commit — откат; после Commit это безвредный no-op

// запросы внутри транзакции идут через tx, а НЕ через pool:
var userID string
err = tx.QueryRow(ctx,
    `INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id`,
    email, passwordHash,
).Scan(&userID)
if err != nil {
    return err // defer выше сделает Rollback
}

_, err = tx.Exec(ctx,
    `INSERT INTO subscriptions (user_id, plan, links_limit) VALUES ($1, 'basic', 1000)`,
    userID,
)
if err != nil {
    return err // defer выше сделает Rollback
}

return tx.Commit(ctx) // фиксируем обе вставки разом
```

Запомни:
- `Begin` открывает транзакцию, `Commit` фиксирует изменения, `Rollback` откатывает.
- `defer tx.Rollback(ctx)` сразу после `Begin` — страховка: если выйдешь с ошибкой до `Commit`, всё откатится. После успешного `Commit` повторный `Rollback` ничего не делает (его ошибку можно игнорировать).
- Внутри транзакции **все** запросы делаются через `tx` (`tx.Exec`, `tx.QueryRow`), а не через `pool`.

Здесь транзакция целиком в одном методе репозитория, потому что обе таблицы в одной БД. Когда транзакция охватывает несколько репозиториев, её открывают на уровне сервиса и прокидывают `tx` в методы — но в этом задании это не нужно.

**Проверка:** `go build ./...` проходит; каждый конструктор принимает зависимости параметрами, ничего не создаёт внутри себя.

### Шаг 7. JWT и пароли (пакет `auth`)

Сделай пакет `user/internal/auth` — структуру с конструктором `New(secret string, accessTTL, refreshTTL time.Duration)` (секрет и сроки приходят из конфига, не зашиты в код) и методами:
- `HashPassword(pwd) (string, error)` и `ComparePassword(hash, pwd) error` — обёртки над `bcrypt`.
- `SignAccess(userID, sid) (string, error)` и `SignRefresh(userID, sid) (string, error)` — подписывают JWT (`github.com/golang-jwt/jwt/v5`, метод HS256, claims из теории, разные `exp`).
- `Parse(token) (claims, error)` — проверяет подпись и `exp`, возвращает `sub` и `sid`.

**Проверка:** unit-тест «подписал access → распарсил → получил те же `sub`, `sid`».

### Шаг 8. Service-слой (бизнес-логика)

Реализуй 6 методов **строго по контракту из Шага 2** (раздел «Поведение» у каждого метода): Register, Login, Logout, ValidateSession, RefreshToken, GetLimit. Здесь живёт вся логика (валидация, транзакция регистрации, проверка пароля, создание/отзыв сессии, проверка живости сессии). Доменные ошибки объявляй как `var Err... = errors.New(...)` — их потом маппит handler.

**Проверка:** `go build ./...` проходит.

### Шаг 9. Сборка в main.go (composition root)

`cmd/main.go` — единственное место, где создаются конкретные реализации и прокидываются друг в друга (это и есть «внедрение зависимостей»). Собери снизу вверх:

1. `cfg, err := config.Load()` — конфиг (Шаг 5).
2. Клиенты БД: `pool := pgxpool.New(ctx, cfg.DatabaseURL)`, `rdb := redis.NewClient(&redis.Options{Addr: cfg.RedisAddr})`. Сделай `Ping` к обоим — не отвечают, падай с понятной ошибкой.
3. `repo := repository.New(pool)`.
4. `cache := cache.New(rdb)`.
5. `authn := auth.New(cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)` — экземпляр пакета `auth` (JWT + bcrypt). Переменную называем `authn`, чтобы не путать с именем пакета `auth`.
6. `svc := service.New(repo, cache, authn)`.
7. `h := handler.New(svc)`.
8. `grpcServer := grpc.NewServer()`; зарегистрируй `userv1.RegisterUserServiceServer(grpcServer, h)`; включи **reflection** — `reflection.Register(grpcServer)` (`google.golang.org/grpc/reflection`), иначе `grpcurl` не увидит методы без `.proto`; открой `net.Listen("tcp", ":"+cfg.GRPCPort)` и `grpcServer.Serve(lis)`.
9. Graceful shutdown по SIGINT/SIGTERM: `grpcServer.GracefulStop()`, затем закрой пул Postgres и клиент Redis.

`handler` реализует сгенерированный интерфейс `UserServiceServer` (импорт `github.com/yourname/url-shortener/shared/pkg/proto/user/v1`, алиас `userv1`): зовёт service, мапит доменные ошибки в gRPC-коды (`codes.AlreadyExists`, `codes.NotFound`, `codes.Unauthenticated`, `codes.InvalidArgument`, иначе `codes.Internal`) через `status.Error`.

**Проверка:** `make run` стартует сервис; ручной вызов через grpcurl работает:
```bash
grpcurl -plaintext -d '{"email":"a@b.com","password":"password123"}' \
  localhost:50051 user.v1.UserService/Register
grpcurl -plaintext -d '{"email":"a@b.com","password":"password123"}' \
  localhost:50051 user.v1.UserService/Login
```

### Шаг 10. Тесты

1. Сгенерируй моки интерфейсов repository/cache: `mockery` (конфиг `.mockery.yaml` уже скопирован).
2. Напиши минимум 3 unit-теста на service-слой: Register (успех), Register (дубликат email → ALREADY_EXISTS), Login (неверный пароль → UNAUTHENTICATED).

**Проверка:** `make test` зелёный.

---

## Чек-лист

- [ ] `make up` поднимает PostgreSQL + Redis (оба healthy)
- [ ] `make migrate-up` создаёт таблицы `users`, `subscriptions`, `sessions`; миграции применяются и при старте сервиса
- [ ] `make proto-gen` генерирует Go-код из `.proto`
- [ ] Register создаёт пользователя + подписку в одной транзакции (ROLLBACK при сбое)
- [ ] Login возвращает access + refresh
- [ ] ValidateSession проверяет access (подпись + exp + сессия жива) и возвращает user_id
- [ ] RefreshToken выдаёт новый access по живой сессии (`sid` не меняется); отозванная сессия → UNAUTHENTICATED
- [ ] Logout мгновенно гасит сессию: запрос с тем же access сразу после logout → UNAUTHENTICATED
- [ ] Вход во втором «браузере» создаёт независимую сессию; logout первой не трогает вторую
- [ ] GetLimit возвращает лимит подписки
- [ ] Redis кеширует сессию `session:{sid}` с TTL
- [ ] Unit-тесты проходят (`make test`)
- [ ] `make run` запускает сервис, методы отвечают через grpcurl

## Подсказки (библиотеки)

- bcrypt: `golang.org/x/crypto/bcrypt`
- JWT: `github.com/golang-jwt/jwt/v5`
- PostgreSQL: `github.com/jackc/pgx/v5` (+ `pgxpool`)
- Redis: `github.com/redis/go-redis/v9`
- Миграции: `github.com/golang-migrate/migrate/v4`
- Моки: `github.com/vektra/mockery/v2`
- gRPC: `google.golang.org/grpc`, `google.golang.org/protobuf`
