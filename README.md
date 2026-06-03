# URL Shortener — микросервисный пет-проект

Сокращатель ссылок с микросервисной архитектурой. Проект закрепляет все технологии из трека: Go, gRPC, PostgreSQL, MongoDB, Redis, Kafka, ClickHouse, Docker, CI/CD, чистая архитектура, транзакции, Saga, observability.

## С чего начать

Этот репозиторий — **шаблон-источник**, а не место, где ты пишешь код. Здесь лежат:
- задания по неделям: `week1/hw.md` … `week5/hw.md`;
- готовый **boilerplate** (go.work, Makefile, docker-compose, конфиги, `go.mod`, `.env.template`) в папках `weekN/boilerplates/`;
- эталонные ответы для самопроверки: `weekN/answers.md`.

**Откуда качать:** https://github.com/Emil-Ka/url-shortener

### 1. Скачай шаблон

```bash
git clone git@github.com:Emil-Ka/url-shortener.git url-shortener-template
```

Папку называем `url-shortener-template`, чтобы не путать со своим проектом. Без git подойдёт кнопка **Code → Download ZIP** на GitHub.

### 2. Рядом создай свой репозиторий

Свой проект ты создаёшь **сам, в отдельной папке и своём git-репозитории**. Весь твой код живёт там; в шаблон ты ничего не коммитишь.

```bash
mkdir url-shortener && cd url-shortener
git init
```

Должно получиться две независимые папки бок о бок:

```
~/projects/
├── url-shortener-template/   скачанный шаблон: задания, boilerplate, эталоны (только читаешь)
└── url-shortener/            твой репозиторий: сюда пишешь код и коммитишь
```

### 3. Копируй boilerplate по мере надобности

Базовую структуру руками не пишут, её ты всё равно копируешь как есть. Каждую неделю берёшь готовые файлы из шаблона и кладёшь в свой репозиторий:

```bash
# выполняешь из своей папки url-shortener; пример для первой недели
cp ../url-shortener-template/week1/boilerplates/Makefile .
cp ../url-shortener-template/week1/boilerplates/docker-compose.yml .
# полный список файлов недели смотри в weekN/hw.md, Шаг 1
```

Весь остальной код (`.proto`-контракты, бизнес-логику, репозитории, тесты) **пишешь сам**, в этом и смысл проекта. Эталоны в `answers.md` смотри только когда реально застрял.

## Архитектура

```
Client (HTTP)
    │
    ▼
API Gateway (REST, chi router)
    │
    ├──── gRPC ────► User Service
    │                   ├── PostgreSQL (users, sessions, subscriptions)
    │                   └── Redis (session cache, counter)
    │
    ├──── gRPC ────► URL Service
    │                   ├── MongoDB (links)
    │                   ├── Redis (link cache, LRU)
    │                   └── Kafka producer (click events)
    │
    └──── REST ────► Analytics Service
                        ├── Kafka consumer
                        └── ClickHouse (events)
```

## Сервисы

| Сервис | Протокол | БД | Кеш | Очередь |
|--------|----------|-----|------|---------|
| User Service | gRPC | PostgreSQL | Redis (sessions + counters) | — |
| URL Service | gRPC | MongoDB | Redis (links, LRU) | Kafka producer |
| Analytics Service | REST | ClickHouse | — | Kafka consumer |
| API Gateway | REST (chi) | — | — | — |

## Технологии

Go, gRPC + Protobuf, REST (chi), PostgreSQL, MongoDB, Redis (TTL + LRU), Kafka, ClickHouse, Docker + Compose, GitHub Actions, golang-migrate, JWT (access + refresh), Saga pattern, Prometheus, Grafana, Jaeger, Loki, OpenTelemetry, slog, pprof, k6.

## Разбивка на 5 недель

| Неделя | Что делаем | Результат |
|--------|-----------|-----------|
| 1 | User Service (gRPC, PostgreSQL, Redis, JWT, транзакции) | Регистрация, логин, сессии, подписки |
| 2 | URL Service (gRPC, MongoDB, Redis LRU, Saga) | Создание/редирект ссылок с проверкой лимита |
| 3 | API Gateway + Kafka (REST, интеграция, тесты) | Полностью работающее приложение |
| 4 | Analytics Service (Kafka consumer, ClickHouse) | Аналитика по кликам |
| 5 | Observability + Docker + CI/CD + pprof + нагрузочное | Мониторинг, деплой, профилирование |

## Монорепо (Go Workspaces)

```
url-shortener/
├── go.work                      (use ./user ./url ./gateway ./analytics ./shared)
├── user/                        (сервис, свой go.mod)
├── url/
├── gateway/
├── analytics/
├── shared/                      (общий модуль: контракты)
│   ├── proto/<service>/v1/*.proto      — исходники (buf)
│   └── pkg/proto/<service>/v1/*.go     — сгенерированный Go-код
├── docker-compose.yml
├── Makefile
└── .github/workflows/ci.yml
```

Каждый сервис — отдельный модуль в корне (свой `go.mod`). Контракты всех сервисов
лежат в общем модуле `shared`; генерируются через `buf`. Версия `v1` заложена сразу
(в пути, в `package <svc>.v1`, в `go_package`) — best practice на будущее.

## Как работать

Каждая неделя в отдельной папке:
- `hw.md` — задание (что сделать, критерии приёмки)
- `contracts/` — описание API сервиса (эндпоинты, запросы/ответы, статус-коды)
- `boilerplates/` — готовые файлы (docker-compose, Makefile, buf-конфиги, `<сервис>/.env.template` — у каждого сервиса свой `.env`)

Фокус на Go-код, не на инфраструктуру.

## Prerequisites

Локальные инструменты:

```bash
# Go 1.23+
go version

# Docker + Docker Compose
docker --version
docker compose version

# buf (работа с protobuf) + плагины Go
brew install bufbuild/buf/buf
go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# Миграции
brew install golang-migrate

# Линтер
brew install golangci-lint

# Моки
go install github.com/vektra/mockery/v2@latest

# gRPC CLI (для ручного тестирования)
brew install grpcurl
```

Убедись, что `$(go env GOPATH)/bin` в `$PATH` — иначе `protoc-gen-go` и `mockery` не найдутся.

## Makefile

В корне репозитория один `Makefile`. Стартовая версия (под User Service) лежит в `week1/boilerplates/Makefile` — скопируй её в корень на первой неделе и **дописывай новые таргеты по мере добавления сервисов**: на второй неделе добавь правила для `url`, на третьей — для `gateway`, и т.д. Таргеты `run`, `test`, `lint` параметризуй через переменную (например, `SERVICE=user make test`) или сделай отдельные таргеты `test-user`, `test-url`. `proto-gen` один на всех — `buf` генерит все сервисы из `shared/proto`.
