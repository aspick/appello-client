module Appello
  # Webhook の署名検証。
  #
  #   event = Appello::Webhook.verify!(payload: request.raw_post, signature: request.headers["Appello-Signature"])
  #
  # 配送は at-least-once で、順序も保証されない。受け側は snapshot の version を見て、
  # 手元より新しいときだけ上書きする (Appello::Cacheable がこれを行う)。
  module Webhook
    class SignatureError < Error; end

    DEFAULT_TOLERANCE = 300

    module_function

    def verify!(payload:, signature:, secret: Appello.configuration.webhook_secret, tolerance: DEFAULT_TOLERANCE, now: Time.now)
      raise ConfigurationError, "webhook_secret が設定されていません" if secret.to_s.empty?

      timestamp, digests = parse(signature)
      raise SignatureError, "署名ヘッダの形式が不正です" if timestamp.nil? || digests.empty?
      raise SignatureError, "署名が古すぎます" if (now.to_i - timestamp).abs > tolerance

      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
      raise SignatureError, "署名が一致しません" unless digests.any? { |digest| OpenSSL.secure_compare(digest, expected) }

      Event.new(JSON.parse(payload))
    end

    # テストや手元での送信用。
    def sign(payload:, secret:, timestamp: Time.now.to_i)
      "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest('SHA256', secret, "#{timestamp}.#{payload}")}"
    end

    def parse(signature)
      pairs = signature.to_s.split(",").map { |pair| pair.split("=", 2) }
      timestamp = pairs.find { |key, _| key == "t" }&.last
      [ timestamp && Integer(timestamp, exception: false), pairs.select { |key, _| key == "v1" }.map(&:last).compact ]
    end
  end
end
