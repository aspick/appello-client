require "appello"

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.order = :random
  config.after { Appello.reset! }
end

# Client に差し込む偽の transport。応答を順に返し、受け取ったリクエストを記録する。
class FakeTransport
  attr_reader :requests

  def initialize(*responses)
    @responses = responses
    @requests = []
  end

  def call(request)
    @requests << request
    response = @responses.size > 1 ? @responses.shift : @responses.first
    raise response if response.is_a?(Exception)

    response
  end

  def self.json(status, body)
    Appello::Response.new(status: status, body: JSON.generate(body))
  end
end
