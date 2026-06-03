module github.com/yourname/url-shortener/user

go 1.23

// Контракты берём из общего модуля shared (локально резолвится через go.work):
//   github.com/yourname/url-shortener/shared/pkg/proto/user/v1
//
// Остальные зависимости подтянутся через `go mod tidy` после первых импортов:
//   google.golang.org/grpc, google.golang.org/protobuf
//   github.com/jackc/pgx/v5 (+ pgxpool)
//   github.com/redis/go-redis/v9
//   github.com/golang-jwt/jwt/v5
//   golang.org/x/crypto/bcrypt
//   github.com/joho/godotenv      (загрузка user/.env)
//   github.com/stretchr/testify
