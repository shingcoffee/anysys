# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/authentication routes", type: :routing do
  let(:cid) { "12345678" }

  it "routes roles index" do
    expect(get: "/#{cid}/admin/settings/modules/authentication/roles")
      .to route_to(controller: "admin/settings/modules/authentication/roles",
                   action: "index", customer_id: cid)
  end

  it "routes role grants show" do
    expect(get: "/#{cid}/admin/settings/modules/authentication/roles/5/grants")
      .to route_to(controller: "admin/settings/modules/authentication/role_grants",
                   action: "show", customer_id: cid, role_id: "5")
  end

  it "routes user_role_assignments index" do
    expect(get: "/#{cid}/admin/settings/modules/authentication/user_role_assignments")
      .to route_to(controller: "admin/settings/modules/authentication/user_role_assignments",
                   action: "index", customer_id: cid)
  end
end
