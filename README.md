# appello-client

団員名簿の正本サービス appello の Ruby クライアント。appello を利用するアプリケーションのサーバーから使う。

> このリポジトリは、リリースのたびに自動で更新される読み取り専用の複製です。開発は別のリポジトリで行っているため、Issue と Pull Request は受け付けていません。

## インストール

```ruby
gem "appello-client", github: "aspick/appello-client", tag: "v0.2.0"
```

- 対応: Ruby 3.4 以上。実行時の依存 gem なし (HTTP は標準ライブラリ)
- `Appello::Cacheable` だけは取り込み先の Active Record を使う

## 設定

```ruby
# config/initializers/appello.rb
Appello.configure do |config|
  config.base_url = ENV.fetch("APPELLO_URL")
  config.api_key = ENV.fetch("APPELLO_API_KEY")
  config.webhook_secret = ENV.fetch("APPELLO_WEBHOOK_SECRET")
  config.logger = Rails.logger
end
```

## 呼び出し

戻り値は JSON をパースした Hash (キーは文字列) で、Webhook のスナップショットと同じ形。

```ruby
# 書き込みには操作者が必要 (appello の変更履歴に残る)
appello = Appello.client.as(current_user.id, label: current_user.name)
snapshot = appello.update_member(member.appello_id, name: "山田", version: member.appello_version)
member.apply_appello_snapshot(snapshot)

# ユーザーに紐づかない処理 (バックフィル、取り込みジョブ)
Appello.client.as_system.upsert_member_ref(group.id, member.id, name: member.name, identities: [ { subject: user.id, app_role: "admin" } ])

# 読み取りは操作者なしで呼べる
Appello.client.members(group.appello_id, status: "active", bound: false)

# このクライアントが使っているグループのすべて (ページングは内部で辿る)。手元のデータとの突き合わせに使う
Appello.client.groups
Appello.client.each_group { |group| ... } # 全件をメモリに載せたくないとき
```

- POST には `Idempotency-Key` を自動で付けるので、タイムアウト後のリトライで二重作成にならない。ジョブの再実行でも同じ結果にしたいときは `idempotency_key:` を自分で渡す
- 接続エラーと 429 / 502 / 503 / 504 は `max_retries` 回 (既定 2) までリトライする
- `base_url` は `https://` のみ受け付ける (API キーを平文で流さないため)。`localhost` は例外。検証環境などで平文を許す場合は `config.allow_insecure_http = true`

### エラー

| 例外 | 状況 |
|---|---|
| `Appello::ValidationFailed` | 422。`details` に項目ごとのエラー |
| `Appello::Conflict` | 409。`stale_version?` / `group_authoritative?` / `group_not_authoritative?` で原因を見分ける |
| `Appello::NotFound` | 404。存在しないか、自クライアントがバインディングを持たないグループ |
| `Appello::Unauthorized` | 401 |
| `Appello::ServerError` | 5xx (リトライを使い切った後) |
| `Appello::ConnectionError` | 到達できなかった (リトライを使い切った後) |
| `Appello::ActorRequired` | 操作者なしで書き込もうとした (送信前に上がる) |

すべて `Appello::Error` を継承する。

## Webhook

```ruby
class AppelloWebhooksController < ActionController::API
  def create
    event = Appello::Webhook.verify!(payload: request.raw_post, signature: request.headers["Appello-Signature"])

    case event.resource
    when "member", "identity" then Member.apply_appello_snapshot(event.snapshot) unless event.subject_gone?
    when "group" then Group.apply_appello_snapshot(event.snapshot)
    end
    head :no_content
  rescue Appello::Webhook::SignatureError
    head :unauthorized
  end
end
```

配送は at-least-once で、順序も保証されない。`snapshot` は常に対象の最新の全項目なので、受け側は version が新しいときだけ上書きすればよい。`Appello::Cacheable` がそれを行う。

## キャッシュへの反映

対象テーブルに `appello_id` (uuid, unique) と `appello_version` (integer) を足す。

```ruby
class Member < ApplicationRecord
  include Appello::Cacheable

  appello_attributes do |snapshot|
    { name: snapshot["name"], hidden: snapshot["status"] == "left" }
  end
end

Member.apply_appello_snapshot(snapshot)                 # appello_id で探して反映。古い版・対応する行なしは nil
Member.apply_appello_snapshot(snapshot) { Member.new }  # 対応する行がなければ作る
member.apply_appello_snapshot(snapshot)                 # write-through の応答をその場で反映
```

## 差分 pull

Webhook の取りこぼしを回収する。定期ジョブから呼ぶ。カーソルの保存先はアプリが決める (`#read` と `#write(seq)` を持つオブジェクト)。

```ruby
Appello::EventPuller.new(cursor: AppelloCursor.instance).run { |event| AppelloEventHandler.call(event) }
```

## 開発

```sh
bundle install
bundle exec rspec
```

手元の checkout をアプリから使うには、アプリ側で `bundle config set local.appello-client /path/to/checkout`。
