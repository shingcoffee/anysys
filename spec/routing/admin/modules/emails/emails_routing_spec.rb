# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/modules/emails routing", type: :routing do
  let(:cid) { "12345678" }

  it "does not route email tags" do
    expect(get: "/81721200/admin/modules/emails/tags").not_to be_routable
  end

  %w[
    reports
    deliverability
    engagement
    suppressions
  ].each do |resource|
    it "routes GET /:cid/admin/modules/emails/#{resource} to #{resource}#index" do
      expect(get: "/#{cid}/admin/modules/emails/#{resource}").to route_to(
        controller: "admin/modules/emails/#{resource}",
        action:     "index",
        customer_id: cid
      )
    end
  end
end
