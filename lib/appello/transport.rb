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

    def initialize(base_url:, open_timeout:, read_timeout:)
      @base_uri = URI.parse(base_url)
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
  end
end
