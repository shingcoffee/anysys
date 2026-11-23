# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/maintenance/platform/ai_assistant/settings routing", type: :routing do
  let(:cid)  { "81721200" }
  let(:ctrl) { "admin/maintenance/platform/ai_assistant/settings" }
  let(:base) { "/#{cid}/admin/maintenance/platform/module_settings/ai_assistant/settings" }

  it "routes GET show" do
    expect(get: base).to route_to(
      controller: ctrl,
      action: "show",
      customer_id: cid
    )
  end

  it "routes GET edit" do
    expect(get: "#{base}/edit").to route_to(
      controller: ctrl,
      action: "edit",
      customer_id: cid
    )
  end

  it "routes PATCH update" do
    expect(patch: base).to route_to(
      controller: ctrl,
      action: "update",
      customer_id: cid
    )
  end

  it "routes POST test_connection" do
    expect(post: "#{base}/test_connection").to route_to(
      controller: ctrl,
      action: "test_connection",
      customer_id: cid
    )
  end
end
