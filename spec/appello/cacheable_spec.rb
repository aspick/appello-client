require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
ActiveRecord::Schema.verbose = false
ActiveRecord::Schema.define do
  create_table :cached_members, force: true do |t|
    t.string :name
    t.boolean :hidden, default: false, null: false
    t.string :appello_id
    t.integer :appello_version
  end
end

class CachedMember < ActiveRecord::Base
  include Appello::Cacheable

  appello_attributes { |snapshot| { name: snapshot["name"], hidden: snapshot["status"] == "left" } }
end

RSpec.describe Appello::Cacheable do
  before { CachedMember.delete_all }

  def snapshot(version:, name: "山田", status: "active")
    { "id" => "m1", "version" => version, "name" => name, "status" => status }
  end

  it "新しいスナップショットだけを反映する (重複・順序の入れ替わりに強い)" do
    member = CachedMember.create!(name: "旧", appello_id: "m1", appello_version: 2)

    expect(CachedMember.apply_appello_snapshot(snapshot(version: 3, name: "新", status: "left"))).to eq(member)
    expect(member.reload).to have_attributes(name: "新", hidden: true, appello_version: 3)

    expect(CachedMember.apply_appello_snapshot(snapshot(version: 3, name: "重複"))).to be_nil
    expect(CachedMember.apply_appello_snapshot(snapshot(version: 2, name: "遅れて届いた古い版"))).to be_nil
    expect(member.reload.name).to eq("新")
  end

  it "対応する行がなければ何もしない。ブロックがあれば新しい行を作れる" do
    expect(CachedMember.apply_appello_snapshot(snapshot(version: 1))).to be_nil
    expect(CachedMember.count).to eq(0)

    created = CachedMember.apply_appello_snapshot(snapshot(version: 1)) { CachedMember.new }
    expect(created).to have_attributes(name: "山田", appello_id: "m1", appello_version: 1)
  end

  it "appello_id をまだ持たない既存行にも反映できる (バックフィル直後)" do
    member = CachedMember.create!(name: "山田")
    member.apply_appello_snapshot(snapshot(version: 4))

    expect(member.reload).to have_attributes(appello_id: "m1", appello_version: 4)
  end
end
