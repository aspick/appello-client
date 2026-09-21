require "net/http"

module Appello
  Request = Struct.new(:method, :path, :query, :headers, :body, keyword_init: true)

  Response = Struct.new(:status, :body, keyword_init: true) do
    def success? = status.between?(200, 299)

    def json
      return @json if defined?(@json)

      @json = body.to_s.empty? ? nil : JSON.parse(body)
    rescue JSON::ParserError
      @json = nil
    end
  end

  # HTTP の実体。テストでは #call(request) を持つ別のオブジェクトに差し替えられる。
  class NetHttpTransport
    NETWORK_ERRORS = [ SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, EOFError, IOError ].freeze

    LOCAL_HOSTS = %w[localhost 127.0.0.1 ::1 [::1]].freeze

    def initialize(base_url:, open_timeout:, read_timeout:, allow_insecure_http: false)
      @base_uri = URI.parse(base_url)
      reject_plain_http! unless allow_insecure_http
      @open_timeout = open_timeout
      @read_timeout = read_timeout
    end

    def call(request)
      uri = @base_uri.dup
      uri.path = File.join(@base_uri.path.to_s, request.path)
      uri.query = URI.encode_www_form(request.query) unless request.query.nil? || request.query.empty?

      http_request = Net::HTTP.const_get(request.method.to_s.capitalize).new(uri)
      request.headers.each { |name, value| http_request[name] = value }
      http_request.body = request.body if request.body

      response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                 open_timeout: @open_timeout, read_timeout: @read_timeout) { |http| http.request(http_request) }
      Response.new(status: response.code.to_i, body: response.body)
    rescue *NETWORK_ERRORS => e
      raise ConnectionError, "#{e.class}: #{e.message}"
    end

    private

    # http:// だと API キーが平文で流れる。サーバーが https へリダイレクトしても、その時点でキーは漏れている。
    # 送る前に止める。手元での開発 (localhost) だけは許す。
    def reject_plain_http!
      return if @base_uri.scheme == "https"

      # URI はスキームを小文字に正規化するが、ホスト名は書かれたままの大文字・小文字で返す。
      host = @base_uri.host.to_s.downcase
      return if LOCAL_HOSTS.include?(host) || host.end_with?(".localhost")

      raise ConfigurationError, "base_url は https:// で指定してください (#{@base_uri.scheme}://#{@base_uri.host})。" \
                                "検証環境などで平文を許す場合は config.allow_insecure_http = true"
    end
  end
end
