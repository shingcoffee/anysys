# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/maintenance/platform/announcements routing", type: :routing do
  let(:cid)  { "81721200" }
  let(:ctrl) { "admin/maintenance/platform/announcements" }
  let(:base) { "/#{cid}/admin/maintenance/platform/announcements" }

  it "routes GET index" do
    expect(get: base).to route_to(controller: ctrl, action: "index", customer_id: cid)
  end

  it "routes GET new" do
    expect(get: "#{base}/new").to route_to(controller: ctrl, action: "new", customer_id: cid)
  end

  it "routes POST create" do
    expect(post: base).to route_to(controller: ctrl, action: "create", customer_id: cid)
  end

  it "routes GET show" do
    expect(get: "#{base}/1").to route_to(controller: ctrl, action: "show", customer_id: cid, id: "1")
  end

  it "routes GET edit" do
    expect(get: "#{base}/1/edit").to route_to(controller: ctrl, action: "edit", customer_id: cid, id: "1")
  end

  it "routes PATCH update" do
    expect(patch: "#{base}/1").to route_to(controller: ctrl, action: "update", customer_id: cid, id: "1")
  end

  it "routes DELETE destroy" do
    expect(delete: "#{base}/1").to route_to(controller: ctrl, action: "destroy", customer_id: cid, id: "1")
  end

  it "routes POST audience_preview" do
    expect(post: "#{base}/audience_preview")
      .to route_to(controller: ctrl, action: "audience_preview", customer_id: cid)
  end
end
