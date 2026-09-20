RSpec.describe Appello::Client do
  let(:sleeps) { [] }

  def build(transport)
    described_class.new(base_url: "https://appello.test", api_key: "apl_test", transport: transport, sleeper: ->(seconds) { sleeps << seconds })
  end

  it "認証・操作者・冪等キーのヘッダを付ける" do
    transport = FakeTransport.new(FakeTransport.json(201, { "id" => "m1" }))
    build(transport).as(42, label: "会計 花子").create_member("g1", { name: "山田" }, external_id: 7)

    request = transport.requests.first
    expect(request.to_h).to include(method: :post, path: "/v1/groups/g1/members")
    expect(JSON.parse(request.body)).to eq("name" => "山田", "external_id" => "7")
    expect(request.headers).to include("Authorization" => "Bearer apl_test", "Appello-Actor-Subject" => "42")
    expect(URI.decode_www_form_component(request.headers["Appello-Actor-Label"])).to eq("会計 花子")
    expect(request.headers["Appello-Actor-Label"]).to be_ascii_only
    expect(request.headers["Idempotency-Key"]).to match(/\A\h{8}-/)
  end

  it "操作者なしの書き込みは送信前に止める" do
    transport = FakeTransport.new
    expect { build(transport).update_member("m1", name: "x") }.to raise_error(Appello::ActorRequired)
    expect(transport.requests).to be_empty
  end

  it "読み取りは操作者なしで呼べ、絞り込みをクエリにする" do
    transport = FakeTransport.new(FakeTransport.json(200, { "members" => [] }))
    build(transport).members("g1", status: %w[active on_leave], bound: false)

    expect(transport.requests.first.query).to eq(status: "active,on_leave", bound: "false")
  end

  it "エラー応答を種類ごとの例外にする" do
    conflict = FakeTransport.json(409, { "error" => { "code" => "stale_version", "message" => "古い" } })
    expect { build(FakeTransport.new(conflict)).as_system.update_member("m1", name: "x", version: 1) }
      .to raise_error(Appello::Conflict) { |error| expect(error).to be_stale_version.and have_attributes(status: 409, message: "古い") }

    invalid = FakeTransport.json(422, { "error" => { "code" => "validation_failed", "message" => "NG", "details" => { "name" => [ "blank" ] } } })
    expect { build(FakeTransport.new(invalid)).as_system.create_member("g1", { name: "" }) }
      .to raise_error(Appello::ValidationFailed) { |error| expect(error.details).to eq("name" => [ "blank" ]) }
  end

  it "接続エラーと 5xx は同じ冪等キーのままリトライする" do
    transport = FakeTransport.new(Appello::ConnectionError.new("timeout"), FakeTransport.json(503, {}), FakeTransport.json(201, { "id" => "m1" }))

    expect(build(transport).as_system.create_member("g1", { name: "山田" })).to eq("id" => "m1")
    expect(transport.requests.map { |request| request.headers["Idempotency-Key"] }.uniq.size).to eq(1)
    expect(sleeps).to eq([ 0.2, 0.4 ])
  end

  it "リトライを使い切ったら例外を上げる" do
    expect { build(FakeTransport.new(Appello::ConnectionError.new("refused"))).group("g1") }.to raise_error(Appello::ConnectionError)
    expect { build(FakeTransport.new(FakeTransport.json(503, {}))).group("g1") }.to raise_error(Appello::ServerError)
  end

  it "4xx はリトライしない" do
    transport = FakeTransport.new(FakeTransport.json(404, { "error" => { "code" => "not_found", "message" => "なし" } }))
    expect { build(transport).group("g1") }.to raise_error(Appello::NotFound)
    expect(transport.requests.size).to eq(1)
  end

  it "パスに入る ID をエスケープする" do
    transport = FakeTransport.new(FakeTransport.json(200, {}))
    build(transport).as_system.link_identity("m1", "google-oauth2|abc/1", app_role: "admin")

    expect(transport.requests.first.path).to eq("/v1/members/m1/identities/google-oauth2%7Cabc%2F1")
  end
end
