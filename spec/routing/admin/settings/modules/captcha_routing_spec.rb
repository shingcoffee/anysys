# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/modules/captcha routing", type: :routing do
  let(:cid) { "12345678" }

  it "routes GET /settings/modules/captcha to StatusController#show" do
    expect(get: "/#{cid}/admin/settings/modules/captcha").to route_to(
      controller: "admin/settings/modules/captcha/status",
      action: "show",
      customer_id: cid
    )
  end

  it "keeps GET /settings/modules/captcha/status on StatusController#show" do
    expect(get: "/#{cid}/admin/settings/modules/captcha/status").to route_to(
      controller: "admin/settings/modules/captcha/status",
      action: "show",
      customer_id: cid
    )
  end

  it "routes PATCH /settings/modules/captcha/pages/:id" do
    expect(patch: "/#{cid}/admin/settings/modules/captcha/pages/42").to route_to(
      controller: "admin/settings/modules/captcha/pages",
      action: "update",
      customer_id: cid,
      id: "42"
    )
  end
end
