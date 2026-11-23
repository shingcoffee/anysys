# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/platform_announcement_dismissals routing", type: :routing do
  let(:cid) { "10000001" }

  it "routes POST create under the tenant admin prefix" do
    expect(post: "/#{cid}/admin/platform_announcement_dismissals").to route_to(
      controller: "admin/platform_announcement_dismissals",
      action: "create",
      customer_id: cid
    )
  end

  it "does not nest dismissals under the platform maintenance prefix" do
    expect(post: "/#{cid}/admin/maintenance/platform/platform_announcement_dismissals").not_to be_routable
  end
end
