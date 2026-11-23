# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin entity entry journey routing", type: :routing do
  let(:cid) { "12345678" }
  let(:path) { "/#{cid}/admin/entities/42/entries/7/journeys/student_add_course_journey" }

  it "routes a journey start under the admin entries nest" do
    expect(post: path).to route_to(controller: "admin/entity_entry_journeys", action: "create", customer_id: cid,
                                   entity_id: "42", entry_id: "7", key: "student_add_course_journey")
  end

  it "only starts journeys" do
    expect(get: path).not_to be_routable
    expect(delete: path).not_to be_routable
    expect(get: "/#{cid}/admin/entities/42/entries/7/journeys").not_to be_routable
  end

  it "exposes the nested admin helper" do
    expect(Rails.application.routes.url_helpers.admin_entity_entry_journey_path(cid, 42, 7, "student_add_course_journey")).to eq(path)
  end
end
