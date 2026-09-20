module Appello
  class Error < StandardError; end

  # 設定漏れや、書き込みなのに操作者が指定されていないなど、呼び出し側の誤り。
  class ConfigurationError < Error; end
  class ActorRequired < Error; end

  # appello に到達できなかった (タイムアウト、接続拒否など)。リトライを使い切った後に上がる。
  class ConnectionError < Error; end

  # appello がエラー応答を返した。
  class ApiError < Error
    attr_reader :status, :code, :details

    def initialize(status:, code:, message:, details: nil)
      super(message)
      @status = status
      @code = code
      @details = details
    end

    def self.from_response(response)
      error = response.json.is_a?(Hash) ? response.json.fetch("error", {}) : {}
      klass = BY_STATUS.fetch(response.status) { response.status >= 500 ? ServerError : ApiError }
      klass.new(status: response.status, code: error["code"], message: error["message"] || "HTTP #{response.status}", details: error["details"])
    end
  end

  class BadRequest < ApiError; end
  class Unauthorized < ApiError; end
  class NotFound < ApiError; end

  # 409。code で原因を見分ける: stale_version / group_authoritative / group_not_authoritative / request_in_progress / conflict
  class Conflict < ApiError
    def stale_version? = code == "stale_version"
    def group_authoritative? = code == "group_authoritative"
    def group_not_authoritative? = code == "group_not_authoritative"
  end

  # 422。details に項目ごとのエラーが入る。
  class ValidationFailed < ApiError; end
  class ServerError < ApiError; end

  class ApiError
    BY_STATUS = { 400 => BadRequest, 401 => Unauthorized, 404 => NotFound, 409 => Conflict, 422 => ValidationFailed }.freeze
  end
end
