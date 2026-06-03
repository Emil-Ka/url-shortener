module github.com/yourname/url-shortener/gateway

go 1.23

// Контракты сервисов — из общего модуля shared (через go.work):
//   github.com/yourname/url-shortener/shared/pkg/proto/user/v1
//   github.com/yourname/url-shortener/shared/pkg/proto/url/v1
//
// Зависимости подтянутся через `go mod tidy` после первых импортов:
//   github.com/go-chi/chi/v5
//   google.golang.org/grpc, google.golang.org/protobuf
//   github.com/joho/godotenv      (загрузка gateway/.env)
//   github.com/testcontainers/testcontainers-go  (интеграционные тесты)
