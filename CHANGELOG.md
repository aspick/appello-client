# Changelog

## 0.1.0

- v1 API クライアント (ミラー用 / 正本用)、操作者ヘッダ、`Idempotency-Key` の自動付与、リトライ
- Webhook の署名検証 (`Appello::Webhook.verify!`) とイベント表現 (`Appello::Event`)
- ローカルキャッシュへのスナップショット反映 (`Appello::Cacheable`)
- 差分 pull (`Appello::EventPuller`)
