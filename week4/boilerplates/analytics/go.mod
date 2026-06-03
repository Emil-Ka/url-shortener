module github.com/yourname/url-shortener/analytics

go 1.23

// Контракты — из общего модуля shared (через go.work):
//   github.com/yourname/url-shortener/shared/pkg/proto/analytics/v1
//   github.com/yourname/url-shortener/shared/pkg/proto/url/v1  (клиент GetURL)
//
// Зависимости подтянутся через `go mod tidy`:
//   github.com/ClickHouse/clickhouse-go/v2
//   github.com/segmentio/kafka-go
//   google.golang.org/grpc, google.golang.org/protobuf
//   github.com/joho/godotenv      (загрузка analytics/.env)
//   github.com/testcontainers/testcontainers-go
