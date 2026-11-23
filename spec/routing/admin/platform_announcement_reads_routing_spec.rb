# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/platform_announcement_reads routing", type: :routing do
  let(:cid) { "10000001" }

  it "routes POST create under the tenant admin prefix" do
    expect(post: "/#{cid}/admin/platform_announcement_reads").to route_to(
      controller: "admin/platform_announcement_reads",
      action: "create",
      customer_id: cid
    )
  end

  it "does not nest reads under the platform maintenance prefix" do
    expect(post: "/#{cid}/admin/maintenance/platform/platform_announcement_reads").not_to be_routable
  end
end
