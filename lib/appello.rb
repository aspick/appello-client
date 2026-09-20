require "json"
require "securerandom"
require "openssl"
require "uri"

require_relative "appello/version"
require_relative "appello/errors"
require_relative "appello/configuration"
require_relative "appello/transport"
require_relative "appello/client"
require_relative "appello/event"
require_relative "appello/webhook"
require_relative "appello/event_puller"

# appello (団員名簿の正本サービス) のクライアント。
#
#   Appello.configure do |config|
#     config.base_url = ENV.fetch("APPELLO_URL")
#     config.api_key = ENV.fetch("APPELLO_API_KEY")
#     config.webhook_secret = ENV.fetch("APPELLO_WEBHOOK_SECRET")
#   end
#
#   Appello.client.as(current_user.id, label: current_user.name).update_member(id, name: "山田")
module Appello
  # Active Record を使うアプリでだけ読み込まれるようにする。
  autoload :Cacheable, File.expand_path("appello/cacheable", __dir__)

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
      @client = nil
    end

    def client
      @client ||= Client.new
    end

    # テストで差し替えるための口。
    attr_writer :client

    def reset!
      @configuration = nil
      @client = nil
    end
  end
end
