# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/assistant routing", type: :routing do
  let(:cid) { "12345678" }

  it "routes GET messages index" do
    expect(get: "/#{cid}/admin/assistant/messages").to route_to(
      controller: "admin/assistant/messages",
      action: "index",
      customer_id: cid
    )
  end

  it "routes POST messages create" do
    expect(post: "/#{cid}/admin/assistant/messages").to route_to(
      controller: "admin/assistant/messages",
      action: "create",
      customer_id: cid
    )
  end

  it "routes POST transcriptions create" do
    expect(post: "/#{cid}/admin/assistant/transcriptions").to route_to(
      controller: "admin/assistant/transcriptions",
      action: "create",
      customer_id: cid
    )
  end

  it "routes GET transcriptions show" do
    expect(get: "/#{cid}/admin/assistant/transcriptions/9").to route_to(
      controller: "admin/assistant/transcriptions",
      action: "show",
      customer_id: cid,
      id: "9"
    )
  end

  it "routes GET /:cid/admin/assistant to the HTML workspace" do
    expect(get: "/#{cid}/admin/assistant").to route_to(
      controller: "admin/assistants",
      action: "show",
      customer_id: cid
    )
  end

  it "routes GET /:cid/admin to the AI Assistant as the admin root" do
    expect(get: "/#{cid}/admin").to route_to(
      controller: "admin/assistants",
      action: "show",
      customer_id: cid
    )
  end

  it "does not route a member assistant URL" do
    expect(post: "/#{cid}/member/assistant/messages").not_to be_routable
  end
end
