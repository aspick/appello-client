module Appello
  # Webhook の取りこぼしを回収する差分 pull。定期ジョブから呼ぶ。
  #
  #   Appello::EventPuller.new(cursor: AppelloCursor).run { |event| AppelloEventHandler.call(event) }
  #
  # cursor は #read (Integer か nil) と #write(Integer) を持つオブジェクト。保存先はアプリが決める。
  # ブロックが例外を上げたらそこで止まり、カーソルは処理済みのところまでしか進まない。
  class EventPuller
    def initialize(cursor:, client: Appello.client, limit: nil)
      @cursor = cursor
      @client = client
      @limit = limit
    end

    # 処理したイベント数を返す。
    def run
      processed = 0
      loop do
        page = @client.events(after: @cursor.read.to_i, limit: @limit)
        page.fetch("events").each do |payload|
          event = Event.new(payload)
          yield event
          @cursor.write(event.seq)
          processed += 1
        end
        break unless page["has_more"]
      end
      processed
    end
  end
end
