# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/modules/ai_assistant/transcriptions routing", type: :routing do
  let(:cid)  { "12345678" }
  let(:ctrl) { "admin/modules/ai_assistant/transcriptions" }

  it "routes POST create under admin modules" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/transcriptions").to route_to(
      controller: ctrl,
      action: "create",
      customer_id: cid
    )
  end

  it "does not route GET index" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/transcriptions").not_to be_routable
  end

  it "does not route the old modules/speech_to_text path" do
    expect(post: "/#{cid}/admin/modules/speech_to_text/transcriptions").not_to be_routable
  end

  it "does not route the old admin/speech_to_text path" do
    expect(post: "/#{cid}/admin/speech_to_text/transcriptions").not_to be_routable
  end

  it "does not route a member transcribe URL" do
    expect(post: "/#{cid}/member/speech_to_text/transcriptions").not_to be_routable
  end

  it "does not route a public transcribe URL" do
    expect(post: "/speech_to_text/transcriptions").not_to be_routable
  end
end

RSpec.describe "admin/modules/ai_assistant/messages routing", type: :routing do
  let(:cid)  { "12345678" }
  let(:ctrl) { "admin/modules/ai_assistant/messages" }

  it "routes POST create under admin modules" do
    expect(post: "/#{cid}/admin/modules/ai_assistant/messages").to route_to(
      controller: ctrl,
      action: "create",
      customer_id: cid
    )
  end

  it "does not route GET index" do
    expect(get: "/#{cid}/admin/modules/ai_assistant/messages").not_to be_routable
  end
end
