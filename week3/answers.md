# Неделя 3 — ответы (подсказки)

Подсматривай, только если застрял. Сначала попробуй сам.

---

## Шаг 3. Расширение `RedirectRequest`

В `shared/proto/url/v1/url.proto` сообщение `RedirectRequest` становится таким (добавлены три поля; теги продолжаются с 2):

```protobuf
message RedirectRequest {
  string short_code  = 1;
  string ip          = 2;
  string user_agent  = 3;
  string referer     = 4;
}
```

`RedirectResponse` не меняется. После правки — `make proto-gen`.

---

## Шаг 4. Структура click event (для JSON в Kafka)

```go
type ClickEvent struct {
    ShortCode string    `json:"short_code"`
    UserID    string    `json:"user_id"`     // владелец ссылки
    ClickedAt time.Time `json:"clicked_at"`
    IP        string    `json:"ip"`
    UserAgent string    `json:"user_agent"`
    Referer   string    `json:"referer"`
}
```

В `Redirect`: заполнить структуру (поля `ip`/`user_agent`/`referer` — из запроса, `user_id` — из найденного документа ссылки, `clicked_at` — `time.Now()`), сериализовать `json.Marshal`, отправить в topic `click_events`.
