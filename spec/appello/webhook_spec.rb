RSpec.describe Appello::Webhook do
  let(:secret) { "whsec_test" }
  let(:payload) { JSON.generate("id" => "e1", "seq" => 5, "type" => "member.updated", "subject" => { "type" => "member", "id" => "m1" }, "snapshot" => { "id" => "m1", "version" => 3 }) }

  it "正しい署名ならイベントを返す" do
    event = described_class.verify!(payload: payload, signature: described_class.sign(payload: payload, secret: secret), secret: secret)

    expect(event).to have_attributes(type: "member.updated", resource: "member", action: "updated", seq: 5, subject_id: "m1")
    expect(event.snapshot).to include("version" => 3)
  end

  it "改ざんされた本文を拒否する" do
    signature = described_class.sign(payload: payload, secret: secret)
    expect { described_class.verify!(payload: payload.sub("m1", "m2"), signature: signature, secret: secret) }
      .to raise_error(Appello::Webhook::SignatureError, /一致しません/)
  end

  it "別の secret の署名を拒否する" do
    signature = described_class.sign(payload: payload, secret: "other")
    expect { described_class.verify!(payload: payload, signature: signature, secret: secret) }.to raise_error(Appello::Webhook::SignatureError)
  end

  it "古い署名を拒否する (リプレイ対策)" do
    signature = described_class.sign(payload: payload, secret: secret, timestamp: Time.now.to_i - 3600)
    expect { described_class.verify!(payload: payload, signature: signature, secret: secret) }.to raise_error(Appello::Webhook::SignatureError, /古すぎ/)
  end

  it "形式が不正なヘッダを拒否する" do
    [ nil, "", "v1=abc", "t=abc,v1=abc" ].each do |signature|
      expect { described_class.verify!(payload: payload, signature: signature, secret: secret) }.to raise_error(Appello::Webhook::SignatureError)
    end
  end

  it "secret が未設定なら設定エラー" do
    expect { described_class.verify!(payload: payload, signature: "t=1,v1=a") }.to raise_error(Appello::ConfigurationError)
  end
end
