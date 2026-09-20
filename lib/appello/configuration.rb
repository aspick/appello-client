module Appello
  class Configuration
    attr_accessor :base_url, :api_key, :webhook_secret, :open_timeout, :read_timeout, :max_retries, :logger

    def initialize
      @open_timeout = 2
      @read_timeout = 10
      @max_retries = 2
    end
  end
end
