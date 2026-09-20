module Appello
  # Webhook と差分 pull で届くイベント。snapshot は対象の最新の全項目 (Member / Section / Group)。
  # identity.* は親の Member のスナップショット、*.reordered は { id, position, version } の一覧を持つ。
  class Event
    attr_reader :id, :seq, :type, :group_id, :subject_type, :subject_id, :data, :snapshot, :created_at

    def initialize(payload)
      @id = payload.fetch("id")
      @seq = payload["seq"]
      @type = payload.fetch("type")
      @group_id = payload["group_id"]
      @subject_type = payload.dig("subject", "type")
      @subject_id = payload.dig("subject", "id")
      @data = payload["data"] || {}
      @snapshot = payload["snapshot"]
      @created_at = payload["created_at"]
    end

    # "member.updated" → "member"
    def resource
      type.split(".").first
    end

    # "member.updated" → "updated"
    def action
      type.split(".").last
    end

    # 対象が既に存在しない (section.deleted など)
    def subject_gone?
      snapshot.nil?
    end
  end
end
