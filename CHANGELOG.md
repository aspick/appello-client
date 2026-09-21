# Changelog

## 0.1.1

- `base_url` が `http://` のときは送信前に `Appello::ConfigurationError` を上げる (API キーが平文で流れるのを防ぐ)。`localhost` / `127.0.0.1` / `*.localhost` は対象外。それ以外で平文を許す場合は `config.allow_insecure_http = true`

## 0.1.0

- v1 API クライアント (ミラー用 / 正本用)、操作者ヘッダ、`Idempotency-Key` の自動付与、リトライ
- Webhook の署名検証 (`Appello::Webhook.verify!`) とイベント表現 (`Appello::Event`)
- ローカルキャッシュへのスナップショット反映 (`Appello::Cacheable`)
- 差分 pull (`Appello::EventPuller`)
