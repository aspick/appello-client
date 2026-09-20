RSpec.describe Appello::EventPuller do
  let(:cursor) do
    Class.new do
      attr_reader :value

      def read = @value
      def write(seq) = @value = seq
    end.new
  end

  def event(seq)
    { "id" => "e#{seq}", "seq" => seq, "type" => "member.updated", "snapshot" => { "id" => "m1", "version" => seq } }
  end

  it "has_more が尽きるまで読み、カーソルを進める" do
    client = instance_double(Appello::Client)
    allow(client).to receive(:events).with(after: 0, limit: nil).and_return("events" => [ event(1), event(2) ], "next_after" => 2, "has_more" => true)
    allow(client).to receive(:events).with(after: 2, limit: nil).and_return("events" => [ event(3) ], "next_after" => 3, "has_more" => false)

    seen = []
    expect(described_class.new(cursor: cursor, client: client).run { |e| seen << e.seq }).to eq(3)
    expect(seen).to eq([ 1, 2, 3 ])
    expect(cursor.value).to eq(3)
  end

  it "処理が失敗したら、済んだところまでしかカーソルを進めない" do
    client = instance_double(Appello::Client, events: { "events" => [ event(1), event(2) ], "has_more" => false })

    expect { described_class.new(cursor: cursor, client: client).run { |e| raise "boom" if e.seq == 2 } }.to raise_error("boom")
    expect(cursor.value).to eq(1)
  end
end
