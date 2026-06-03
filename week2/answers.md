# Неделя 2 — ответы (подсказки)

Подсматривай сюда, **только если реально застрял**. Смысл задания — написать код самому. Сначала попробуй сам, потом сверься.

---

## Шаг 2. `shared/proto/url/v1/url.proto`

```protobuf
syntax = "proto3";

package url.v1;

option go_package = "github.com/yourname/url-shortener/shared/pkg/proto/url/v1;url_v1";

service URLService {
  rpc CreateShortURL(CreateShortURLRequest) returns (CreateShortURLResponse);
  rpc GetURL(GetURLRequest) returns (GetURLResponse);
  rpc DeleteURL(DeleteURLRequest) returns (DeleteURLResponse);
  rpc ListUserURLs(ListUserURLsRequest) returns (ListUserURLsResponse);
  rpc Redirect(RedirectRequest) returns (RedirectResponse);
}

message CreateShortURLRequest {
  string original_url = 1;
  string user_id = 2;
  optional int64 expires_in = 3; // секунды; нет — бессрочно
}
message CreateShortURLResponse {
  string short_code = 1;
  string short_url = 2;
}

message GetURLRequest  { string short_code = 1; }
message GetURLResponse {
  string original_url = 1;
  string user_id = 2;
  int64 created_at = 3;
  int64 expires_at = 4; // 0 — бессрочно
  bool is_active = 5;
}

message DeleteURLRequest  { string short_code = 1; string user_id = 2; }
message DeleteURLResponse {}

message ListUserURLsRequest {
  string user_id = 1;
  int32 limit = 2;
  string cursor = 3;
}
message ListUserURLsResponse {
  repeated URLItem urls = 1;
  string next_cursor = 2;
}
message URLItem {
  string short_code = 1;
  string original_url = 2;
  int64 created_at = 3;
  int64 expires_at = 4;
  bool is_active = 5;
}

message RedirectRequest  { string short_code = 1; }
message RedirectResponse { string original_url = 1; }
```
