require_relative "lib/appello/version"

Gem::Specification.new do |spec|
  spec.name = "appello-client"
  spec.version = Appello::VERSION
  spec.authors = [ "Ensemble Lab" ]
  spec.summary = "団員名簿の正本サービス appello の Ruby クライアント"
  spec.description = "appello の API クライアント、Webhook の署名検証、ローカルキャッシュへのスナップショット適用、差分 pull を提供する。"
  spec.license = "MIT"
  spec.homepage = "https://github.com/aspick/appello-client"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir["lib/**/*.rb", "README.md", "CHANGELOG.md", "LICENSE"]
  spec.require_paths = [ "lib" ]

  # HTTP は標準ライブラリだけを使う。取り込み先アプリの依存と衝突させないため、実行時の依存 gem は持たない。
  # Appello::Cacheable を使う場合だけ、取り込み先の Active Record / Active Support を利用する。
end
