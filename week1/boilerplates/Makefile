# Подгружаем переменные User Service (нужен DATABASE_URL для migrate-таргетов).
# `-include` не падает, если файла ещё нет; export пробрасывает их в команды.
-include user/.env
export

.PHONY: proto-gen run test lint up down migrate-up migrate-down

# Генерация Go-кода из .proto через buf (конфиг — shared/proto/buf.gen.yaml)
proto-gen:
	cd shared/proto && buf generate

# Запуск User Service
run:
	go run ./user/cmd

# Тесты
test:
	go test -race -v ./user/...

# Линтер
lint:
	golangci-lint run ./user/...

# Docker Compose
up:
	docker compose up -d

down:
	docker compose down

# Миграции
migrate-up:
	migrate -path user/migrations -database "$(DATABASE_URL)" up

migrate-down:
	migrate -path user/migrations -database "$(DATABASE_URL)" down 1
