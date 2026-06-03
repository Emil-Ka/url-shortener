# Неделя 1 — ответы (подсказки)

Подсматривай сюда, **только если реально застрял**. Смысл задания — написать код самому: если сразу копировать, навык не появится. Сначала попробуй сам, потом сверься.

Ответы добавляются по мере необходимости. Если нужного ответа тут нет — спроси ревьюера.

---

## Шаг 2. `shared/proto/user/v1/user.proto`

```protobuf
syntax = "proto3";

package user.v1;

option go_package = "github.com/yourname/url-shortener/shared/pkg/proto/user/v1;user_v1";

service UserService {
  rpc Register(RegisterRequest) returns (RegisterResponse);
  rpc Login(LoginRequest) returns (LoginResponse);
  rpc Logout(LogoutRequest) returns (LogoutResponse);
  rpc ValidateSession(ValidateSessionRequest) returns (ValidateSessionResponse);
  rpc RefreshToken(RefreshTokenRequest) returns (RefreshTokenResponse);
  rpc GetLimit(GetLimitRequest) returns (GetLimitResponse);
}

message RegisterRequest  { string email = 1; string password = 2; }
message RegisterResponse { string user_id = 1; }

message LoginRequest  { string email = 1; string password = 2; }
message LoginResponse { string access_token = 1; string refresh_token = 2; }

// session_id gateway достаёт из claims access-токена и передаёт сюда
message LogoutRequest  { string session_id = 1; }
message LogoutResponse {}

message ValidateSessionRequest  { string access_token = 1; }
message ValidateSessionResponse { string user_id = 1; string session_id = 2; }

message RefreshTokenRequest  { string refresh_token = 1; }
message RefreshTokenResponse { string access_token = 1; }

message GetLimitRequest  { string user_id = 1; }
message GetLimitResponse { int32 links_limit = 1; }
```

Конфиги buf (можно взять из `boilerplates/shared/proto/`):

`shared/proto/buf.yaml`:
```yaml
version: v2
lint:
  use:
    - STANDARD
breaking:
  use:
    - FILE
```

`shared/proto/buf.gen.yaml`:
```yaml
version: v2
clean: true
plugins:
  - local: protoc-gen-go
    out: ../pkg/proto
    opt:
      - paths=source_relative
  - local: protoc-gen-go-grpc
    out: ../pkg/proto
    opt:
      - paths=source_relative
```

---

## Шаг 4. Миграции

`user/migrations/000001_init_schema.up.sql`:

```sql
CREATE TABLE users (
    id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email         VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    created_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE subscriptions (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id     UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    plan        VARCHAR(50) NOT NULL DEFAULT 'basic',
    links_limit INT NOT NULL DEFAULT 1000,
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE sessions (
    id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    expires_at TIMESTAMP NOT NULL,
    is_revoked BOOLEAN NOT NULL DEFAULT FALSE,
    created_at TIMESTAMP NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_sessions_user_id ON sessions (user_id);
CREATE INDEX idx_sessions_expires_at ON sessions (expires_at);
```

`user/migrations/000001_init_schema.down.sql`:

```sql
DROP TABLE IF EXISTS sessions;
DROP TABLE IF EXISTS subscriptions;
DROP TABLE IF EXISTS users;
```
