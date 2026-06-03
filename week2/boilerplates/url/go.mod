module github.com/yourname/url-shortener/url

go 1.23

// Контракты — из общего модуля shared (резолвится через go.work):
//   github.com/yourname/url-shortener/shared/pkg/proto/url/v1
//   github.com/yourname/url-shortener/shared/pkg/proto/user/v1  (gRPC-клиент GetLimit)
//
// Зависимости подтянутся через `go mod tidy` после первых импортов:
//   google.golang.org/grpc, google.golang.org/protobuf
//   go.mongodb.org/mongo-driver/v2/mongo
//   github.com/redis/go-redis/v9
//   github.com/joho/godotenv      (загрузка url/.env)
//   github.com/stretchr/testify
