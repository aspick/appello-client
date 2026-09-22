# Changelog

## 0.4.0

- `switch_group_to_mirror` を追加 (正本モードからミラーモードへの切り戻し)。`switch_group_to_authoritative` と共に、既に目的のモードなら何もしない
- `create_member` / `create_members` の attributes に `identities` を含められるようにした (作成と本人の紐付けが 1 回の呼び出しで済む)
- `suspend_member` / `reinstate_member` / `leave_member` は、既に目的の状態なら何もせずスナップショットを返すようになった (複数の呼び出しからなる操作を、途中で失敗した後にやり直せる)
- README に、write-through (同期の書き込み) 向けに短いタイムアウトの設定を分ける方法を書いた

## 0.3.0

- `groups` / `each_group` / `groups_page` を追加 (このクライアントが使っているグループの一覧。`groups` と `each_group` はページングを内部で辿る)。使うのをやめたはずのグループが残っていないかを、手元のデータと突き合わせて確かめられる

## 0.2.0

- **破壊的変更**: `create_member` の `external_id:` を必須にした (`create_members` の各要素も同様)。作成とバインディングが不可分になり、誰にも使われていない名簿行が生まれない

## 0.1.1

- `base_url` が `http://` のときは送信前に `Appello::ConfigurationError` を上げる (API キーが平文で流れるのを防ぐ)。`localhost` / `127.0.0.1` / `*.localhost` は対象外。それ以外で平文を許す場合は `config.allow_insecure_http = true`

## 0.1.0

- v1 API クライアント (ミラー用 / 正本用)、操作者ヘッダ、`Idempotency-Key` の自動付与、リトライ
- Webhook の署名検証 (`Appello::Webhook.verify!`) とイベント表現 (`Appello::Event`)
- ローカルキャッシュへのスナップショット反映 (`Appello::Cacheable`)
- 差分 pull (`Appello::EventPuller`)
