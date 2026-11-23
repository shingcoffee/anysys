# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/modules/ai_assistant/conversations routing", type: :routing do
  let(:cid)  { "12345678" }
  let(:ctrl) { "admin/modules/ai_assistant/conversations" }

  it "routes GET index under admin modules" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/conversations").to route_to(
      controller: ctrl, action: "index", customer_id: cid
    )
  end

  it "routes POST create" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/conversations").to route_to(
      controller: ctrl, action: "create", customer_id: cid
    )
  end

  it "routes PATCH update" do
    expect(patch: "/#{cid}/admin/modules/ai_assistant/conversations/7").to route_to(
      controller: ctrl, action: "update", customer_id: cid, id: "7"
    )
  end

  it "routes PUT update" do
    expect(put: "/#{cid}/admin/modules/ai_assistant/conversations/7").to route_to(
      controller: ctrl, action: "update", customer_id: cid, id: "7"
    )
  end

  it "routes POST the archive member action" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/conversations/7/archive").to route_to(
      controller: ctrl, action: "archive", customer_id: cid, id: "7"
    )
  end

  it "routes DELETE destroy" do
    expect(delete: "/#{cid}/admin/modules/ai_assistant/conversations/7").to route_to(
      controller: ctrl, action: "destroy", customer_id: cid, id: "7"
    )
  end

  it "does not route GET show" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/conversations/7").not_to be_routable
  end

  it "does not route the new/edit form actions" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/conversations/new").not_to be_routable
    expect(get: "/#{cid}/admin/modules/ai_assistant/conversations/7/edit").not_to be_routable
  end

  it "does not route a member conversations URL" do
    expect(get: "/#{cid}/member/modules/ai_assistant/conversations").not_to be_routable
  end

  it "does not route a public conversations URL" do
    expect(get: "/modules/ai_assistant/conversations").not_to be_routable
  end

  # ResetConversation is gone: "New chat" is a conversations#create.
  it "no longer routes the messages reset collection action" do
    expect(delete: "/#{cid}/admin/modules/ai_assistant/messages/reset").not_to be_routable
  end
end
