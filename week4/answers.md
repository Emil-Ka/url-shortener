# Неделя 4 — ответы (подсказки)

Подсматривай, только если застрял. Сначала попробуй сам.

---

## Шаг 4. `shared/proto/analytics/v1/analytics.proto`

```protobuf
syntax = "proto3";

package analytics.v1;

option go_package = "github.com/yourname/url-shortener/shared/pkg/proto/analytics/v1;analytics_v1";

service AnalyticsService {
  rpc GetAnalytics(GetAnalyticsRequest) returns (GetAnalyticsResponse);
}

message GetAnalyticsRequest {
  string short_code = 1;
  string user_id = 2;   // от Gateway (проверенный)
  int32 days = 3;       // окно в днях; 0 -> сервис подставит 30
}

message DayClicks     { string date = 1; int64 clicks = 2; }
message RefererClicks { string referer = 1; int64 clicks = 2; }

message GetAnalyticsResponse {
  string short_code = 1;
  int64 total_clicks = 2;
  repeated DayClicks clicks_by_day = 3;
  repeated RefererClicks top_referers = 4;
}
```

---

## Шаг 3. DDL таблицы ClickHouse

```sql
CREATE TABLE IF NOT EXISTS click_events (
    short_code  String,
    user_id     String,
    clicked_at  DateTime,
    ip          String,
    user_agent  String,
    referer     String
) ENGINE = MergeTree()
PARTITION BY toYYYYMM(clicked_at)
ORDER BY (short_code, clicked_at);
```

---

## Шаг 6. Структура события (парсинг из Kafka)

```go
type ClickEvent struct {
    ShortCode string    `json:"short_code"`
    UserID    string    `json:"user_id"`
    ClickedAt time.Time `json:"clicked_at"`
    IP        string    `json:"ip"`
    UserAgent string    `json:"user_agent"`
    Referer   string    `json:"referer"`
}
```
