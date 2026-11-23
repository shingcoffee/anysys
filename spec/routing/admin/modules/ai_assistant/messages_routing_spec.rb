# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/modules/ai_assistant/messages routing", type: :routing do
  let(:cid)  { "12345678" }
  let(:ctrl) { "admin/modules/ai_assistant/messages" }

  it "routes POST create under admin modules" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/messages").to route_to(
      controller: ctrl, action: "create", customer_id: cid
    )
  end

  it "routes POST undo" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/messages/7/undo").to route_to(
      controller: ctrl, action: "undo", customer_id: cid, id: "7"
    )
  end

  it "routes POST discard_proposal" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/messages/7/discard_proposal").to route_to(
      controller: ctrl, action: "discard_proposal", customer_id: cid, id: "7"
    )
  end

  it "routes GET mentions" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/messages/mentions").to route_to(
      controller: ctrl, action: "mentions", customer_id: cid
    )
  end

  it "routes POST stop" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/messages/stop").to route_to(
      controller: ctrl, action: "stop", customer_id: cid
    )
  end

  it "routes POST regenerate" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/messages/regenerate").to route_to(
      controller: ctrl, action: "regenerate", customer_id: cid
    )
  end

  it "does not route GET index" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/messages").not_to be_routable
  end

  it "does not route GET show" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/messages/7").not_to be_routable
  end

  it "does not route a member messages URL" do
    expect(post: "/#{cid}/member/modules/ai_assistant/messages").not_to be_routable
  end

  it "does not route a public messages URL" do
    expect(post: "/modules/ai_assistant/messages").not_to be_routable
  end

  it "does not route a seven-digit customer id" do
    expect(post: "/1234567/admin/modules/ai_assistant/messages").not_to be_routable
    expect(post: "/1234567/admin/modules/ai_assistant/messages/7/discard_proposal").not_to be_routable
  end

  it "does not route a nine-digit customer id" do
    expect(post: "/123456789/admin/modules/ai_assistant/messages").not_to be_routable
  end
end
