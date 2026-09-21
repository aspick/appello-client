RSpec.describe Appello::NetHttpTransport do
  def build(base_url, **options)
    described_class.new(base_url: base_url, open_timeout: 1, read_timeout: 1, **options)
  end

  it "https の URL を受け付ける" do
    expect { build("https://appello.example.com") }.not_to raise_error
  end

  it "http の URL は、API キーを平文で流さないよう送信前に拒否する" do
    expect { build("http://appello.example.com") }.to raise_error(Appello::ConfigurationError, /https/)
  end

  it "手元での開発 (localhost) は http でも許す" do
    %w[http://localhost:3000 http://127.0.0.1:3000 http://[::1]:3000 http://appello.localhost:3000].each do |url|
      expect { build(url) }.not_to raise_error
    end
  end

  it "ホスト名の大文字・小文字を区別しない" do
    %w[http://LOCALHOST:3000 http://appello.LocalHost:3000 HTTPS://Appello.Example.com].each do |url|
      expect { build(url) }.not_to raise_error
    end
    expect { build("HTTP://Appello.Example.com") }.to raise_error(Appello::ConfigurationError, /https/)
  end

  it "明示的に許可すれば http でも使える" do
    expect { build("http://appello.internal:3000", allow_insecure_http: true) }.not_to raise_error
  end

  it "Client の設定から引き継がれる" do
    Appello.configure do |config|
      config.base_url = "http://appello.example.com"
      config.api_key = "apl_test"
    end

    expect { Appello.client.group("g1") }.to raise_error(Appello::ConfigurationError, /https/)
  end
end
