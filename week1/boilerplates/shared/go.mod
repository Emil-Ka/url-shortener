module github.com/yourname/url-shortener/shared

go 1.23

// Общий модуль с контрактами всех сервисов:
//   shared/proto/<service>/v1/*.proto   — исходники (пишешь руками)
//   shared/pkg/proto/<service>/v1/*.go  — сгенерированный buf'ом Go-код
//
// Зависимости сгенерированного кода (google.golang.org/grpc,
// google.golang.org/protobuf) подтянутся через `go mod tidy`.
