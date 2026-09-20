require "active_support/concern"

module Appello
  # appello のスナップショットを、ローカルのキャッシュ行 (既存の groups / members テーブル) に反映する。
  # 対象テーブルには appello_id (uuid, unique) と appello_version (integer) の列が要る。
  #
  #   class Member < ApplicationRecord
  #     include Appello::Cacheable
  #
  #     appello_attributes do |snapshot|
  #       { name: snapshot["name"], hidden: snapshot["status"] == "left" }
  #     end
  #   end
  #
  #   Member.apply_appello_snapshot(event.snapshot)
  #
  # 手元の appello_version 以下のスナップショットは捨てるので、Webhook の重複や順序の入れ替わりを気にしなくてよい。
  module Cacheable
    extend ActiveSupport::Concern

    class_methods do
      def appello_attributes(&block)
        @appello_attributes = block if block
        @appello_attributes || raise(ConfigurationError, "#{name} に appello_attributes が定義されていません")
      end

      # 反映したレコードを返す。古いスナップショットだった場合と、対応する行がなくブロックも渡されなかった場合は nil。
      # ブロックを渡すと、対応する行がないときに新しい行を組み立てられる (未保存のレコードを返すこと)。
      def apply_appello_snapshot(snapshot)
        record = find_by(appello_id: snapshot.fetch("id"))
        record ||= (yield snapshot if block_given?)
        record&.apply_appello_snapshot(snapshot)
      end
    end

    def apply_appello_snapshot(snapshot)
      apply = lambda do
        return nil if appello_version && snapshot.fetch("version") <= appello_version

        assign_attributes(self.class.appello_attributes.call(snapshot))
        self.appello_id = snapshot.fetch("id")
        self.appello_version = snapshot.fetch("version")
        save!
        self
      end

      # 同じ行への Webhook が並行して届いても、古い方が後から上書きしないように行ロックを取る。
      new_record? ? apply.call : with_lock { apply.call }
    end

    # write-through の応答 (= スナップショット) をその場で反映するときにも同じ入口を使う。
    def appello_stale?(snapshot)
      appello_version.nil? || snapshot.fetch("version") > appello_version
    end
  end
end
