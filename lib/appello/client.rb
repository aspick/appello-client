module Appello
  # appello の v1 API。戻り値は JSON をそのままパースした Hash (キーは文字列) で、
  # Webhook のスナップショットと同じ形をしている。
  #
  # 書き込みには操作者が必要。#as で操作者を束ねたクライアントを作ってから呼ぶ:
  #
  #   appello = Appello.client.as(current_user.id, label: current_user.name)
  #   appello.update_member(member.appello_id, name: "山田", version: member.appello_version)
  #
  # ユーザーに紐づかない処理 (取り込みジョブ、バックフィル) は #as_system を使う。
  class Client
    SYSTEM_ACTOR = "system".freeze
    RETRYABLE_STATUSES = [ 429, 502, 503, 504 ].freeze

    def initialize(base_url: nil, api_key: nil, transport: nil, actor: nil, config: Appello.configuration, sleeper: Kernel.method(:sleep))
      @config = config
      @base_url = base_url || config.base_url
      @api_key = api_key || config.api_key
      @transport = transport
      @actor = actor
      @sleeper = sleeper
    end

    def as(subject, label: nil)
      self.class.new(base_url: @base_url, api_key: @api_key, transport: @transport, config: @config, sleeper: @sleeper,
                     actor: { subject: subject.to_s, label: label })
    end

    def as_system
      as(SYSTEM_ACTOR)
    end

    # --- ミラー用 (/v1/refs): クライアントのローカル ID をキーにした冪等な upsert ---

    def upsert_group_ref(group_ref, attributes)
      put("/v1/refs/groups/#{escape(group_ref)}", attributes)
    end

    def delete_group_ref(group_ref)
      delete("/v1/refs/groups/#{escape(group_ref)}")
    end

    def upsert_section_ref(group_ref, section_ref, attributes)
      put("/v1/refs/groups/#{escape(group_ref)}/sections/#{escape(section_ref)}", attributes)
    end

    def delete_section_ref(group_ref, section_ref)
      delete("/v1/refs/groups/#{escape(group_ref)}/sections/#{escape(section_ref)}")
    end

    # attributes には section_ref (パートのローカル ID) と identities (このクライアントの Identity の全量) を含められる。
    def upsert_member_ref(group_ref, member_ref, attributes)
      put("/v1/refs/groups/#{escape(group_ref)}/members/#{escape(member_ref)}", attributes)
    end

    def delete_member_ref(group_ref, member_ref)
      delete("/v1/refs/groups/#{escape(group_ref)}/members/#{escape(member_ref)}")
    end

    # --- グループ ---

    def group(id)
      get("/v1/groups/#{escape(id)}")
    end

    def create_group(attributes, external_id:, idempotency_key: nil)
      post("/v1/groups", attributes.merge(external_id: external_id.to_s), idempotency_key: idempotency_key)
    end

    def update_group(id, attributes)
      patch("/v1/groups/#{escape(id)}", attributes)
    end

    # mirror → authoritative。以後このグループは /v1/refs から書き込めなくなる。
    def switch_group_to_authoritative(id)
      post("/v1/groups/#{escape(id)}/switch_mode")
    end

    def bind_group(id, external_id)
      put("/v1/groups/#{escape(id)}/binding", external_id: external_id.to_s)
    end

    def unbind_group(id)
      delete("/v1/groups/#{escape(id)}/binding")
    end

    # --- パート ---

    def sections(group_id)
      get("/v1/groups/#{escape(group_id)}/sections").fetch("sections")
    end

    def section(id)
      get("/v1/sections/#{escape(id)}")
    end

    def create_section(group_id, attributes, external_id: nil, idempotency_key: nil)
      post("/v1/groups/#{escape(group_id)}/sections", with_external_id(attributes, external_id), idempotency_key: idempotency_key)
    end

    def update_section(id, attributes)
      patch("/v1/sections/#{escape(id)}", attributes)
    end

    def delete_section(id)
      delete("/v1/sections/#{escape(id)}")
    end

    def reorder_sections(group_id, section_ids)
      post("/v1/groups/#{escape(group_id)}/sections/reorder", { section_ids: section_ids }).fetch("sections")
    end

    def bind_section(id, external_id)
      put("/v1/sections/#{escape(id)}/binding", external_id: external_id.to_s)
    end

    def unbind_section(id)
      delete("/v1/sections/#{escape(id)}/binding")
    end

    # --- メンバー ---

    # status: "active" や %w[active on_leave] / bound: true なら自クライアントが使っているものだけ、false なら使っていないものだけ
    def members(group_id, status: nil, updated_since: nil, bound: nil, include_discarded: false)
      query = {
        status: status && Array(status).join(","),
        updated_since: updated_since.respond_to?(:iso8601) ? updated_since.iso8601(3) : updated_since,
        bound: bound.nil? ? nil : bound.to_s,
        include_discarded: include_discarded ? "true" : nil
      }.compact
      get("/v1/groups/#{escape(group_id)}/members", query).fetch("members")
    end

    def member(id)
      get("/v1/members/#{escape(id)}")
    end

    def create_member(group_id, attributes, external_id: nil, idempotency_key: nil)
      post("/v1/groups/#{escape(group_id)}/members", with_external_id(attributes, external_id), idempotency_key: idempotency_key)
    end

    # 全件成功か全件失敗のどちらか。各要素に external_id を含められる。
    def create_members(group_id, members, idempotency_key: nil)
      post("/v1/groups/#{escape(group_id)}/members/batch", { members: members }, idempotency_key: idempotency_key).fetch("members")
    end

    def update_member(id, attributes)
      patch("/v1/members/#{escape(id)}", attributes)
    end

    def reorder_members(group_id, member_ids)
      post("/v1/groups/#{escape(group_id)}/members/reorder", { member_ids: member_ids }).fetch("members")
    end

    # 休団
    def suspend_member(id, version: nil)
      post("/v1/members/#{escape(id)}/suspend", { version: version }.compact)
    end

    # 休団からの復帰、または退団後の再入団
    def reinstate_member(id, version: nil)
      post("/v1/members/#{escape(id)}/reinstate", { version: version }.compact)
    end

    # 退団
    def leave_member(id, left_on: nil, version: nil)
      post("/v1/members/#{escape(id)}/leave", { left_on: left_on&.to_s, version: version }.compact)
    end

    def bind_member(id, external_id)
      put("/v1/members/#{escape(id)}/binding", external_id: external_id.to_s)
    end

    # このクライアントで使うのをやめる。どのクライアントも使わなくなったら appello 側で discard される。
    def unbind_member(id)
      delete("/v1/members/#{escape(id)}/binding")
    end

    # --- Identity ---

    # 役割 (app_role) の変更も同じ呼び出しで申告する。
    def link_identity(member_id, subject, relationship: "self", app_role: nil)
      put("/v1/members/#{escape(member_id)}/identities/#{escape(subject)}", { relationship: relationship, app_role: app_role })
    end

    def unlink_identity(member_id, subject)
      delete("/v1/members/#{escape(member_id)}/identities/#{escape(subject)}")
    end

    # アカウント削除。このクライアントの、そのユーザーの Identity をすべて外す。
    def unlink_all_identities(subject)
      delete("/v1/identities/#{escape(subject)}")
    end

    # そのユーザーが属するグループとメンバー: [{ "relationship", "app_role", "group", "member" }]
    def memberships(subject)
      get("/v1/identities/#{escape(subject)}/members").fetch("memberships")
    end

    # --- 履歴とイベント ---

    def change_logs(group_id, target_type: nil, target_id: nil, before: nil, limit: nil)
      query = { target_type: target_type, target_id: target_id, before: before, limit: limit }.compact
      get("/v1/groups/#{escape(group_id)}/change_logs", query).fetch("change_logs")
    end

    # { "events" => [...], "next_after" => Integer, "has_more" => true/false }。通常は EventPuller 経由で使う。
    def events(after: 0, limit: nil)
      get("/v1/events", { after: after, limit: limit }.compact)
    end

    private

    def get(path, query = nil)
      request(:get, path, query: query)
    end

    def put(path, body)
      request(:put, path, body: body)
    end

    def patch(path, body)
      request(:patch, path, body: body)
    end

    def delete(path)
      request(:delete, path)
    end

    # POST は Idempotency-Key を必ず付ける。これでタイムアウト後のリトライが二重作成にならない。
    def post(path, body = {}, idempotency_key: nil)
      request(:post, path, body: body, idempotency_key: idempotency_key || SecureRandom.uuid)
    end

    def request(method, path, query: nil, body: nil, idempotency_key: nil)
      raise ActorRequired, "書き込みには操作者が必要です。Client#as か #as_system を使ってください" if method != :get && @actor.nil?

      request = Request.new(method: method, path: path, query: query, headers: headers(idempotency_key), body: body && JSON.generate(body))
      response = perform(request)
      raise ApiError.from_response(response) unless response.success?

      response.json
    end

    def perform(request)
      attempt = 0
      begin
        response = transport.call(request)
        raise RetryableResponse.new(response) if RETRYABLE_STATUSES.include?(response.status)

        response
      rescue ConnectionError, RetryableResponse => e
        attempt += 1
        if attempt > @config.max_retries
          raise e unless e.is_a?(RetryableResponse)

          return e.response
        end

        @config.logger&.warn("[appello] #{request.method.upcase} #{request.path} failed (#{e.message}); retry #{attempt}/#{@config.max_retries}")
        @sleeper.call(0.2 * (2**(attempt - 1)))
        retry
      end
    end

    class RetryableResponse < StandardError
      attr_reader :response

      def initialize(response)
        super("HTTP #{response.status}")
        @response = response
      end
    end
    private_constant :RetryableResponse

    def headers(idempotency_key)
      headers = {
        "Authorization" => "Bearer #{@api_key || raise(ConfigurationError, 'api_key が設定されていません')}",
        "Accept" => "application/json",
        "Content-Type" => "application/json",
        "User-Agent" => "appello-client-ruby/#{VERSION}"
      }
      if @actor
        headers["Appello-Actor-Subject"] = @actor[:subject]
        # HTTP ヘッダは ASCII しか安全に通らないので、日本語の表示名はパーセントエンコードして送る。
        headers["Appello-Actor-Label"] = URI.encode_www_form_component(@actor[:label]) if @actor[:label]
      end
      headers["Idempotency-Key"] = idempotency_key if idempotency_key
      headers
    end

    def transport
      @transport ||= NetHttpTransport.new(
        base_url: @base_url || raise(ConfigurationError, "base_url が設定されていません"),
        open_timeout: @config.open_timeout, read_timeout: @config.read_timeout,
        allow_insecure_http: @config.allow_insecure_http
      )
    end

    def with_external_id(attributes, external_id)
      external_id ? attributes.merge(external_id: external_id.to_s) : attributes
    end

    def escape(segment)
      URI.encode_www_form_component(segment.to_s).gsub("+", "%20")
    end
  end
end
