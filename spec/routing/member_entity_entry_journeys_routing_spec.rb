# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Member entity entry journey routing", type: :routing do
  let(:cid) { "12345678" }
  let(:path) { "/#{cid}/member/entities/42/entries/7/journeys/follow_up" }

  it "routes a journey start under the member entries nest" do
    expect(post: path).to route_to(controller: "member/entity_entry_journeys", action: "create", customer_id: cid,
                                   entity_id: "42", entry_id: "7", key: "follow_up")
  end

  it "only starts journeys" do
    expect(get: path).not_to be_routable
    expect(delete: path).not_to be_routable
    expect(get: "/#{cid}/member/entities/42/entries/7").not_to be_routable
    expect(get: "/#{cid}/member/entities/42/entries/7/journeys").not_to be_routable
  end

  it "exposes the nested member helper" do
    expect(Rails.application.routes.url_helpers.member_entity_entry_journey_path(cid, 42, 7, "follow_up")).to eq(path)
  end
end
