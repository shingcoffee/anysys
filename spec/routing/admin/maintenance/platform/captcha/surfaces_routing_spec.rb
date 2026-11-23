# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/maintenance/platform/captcha/surfaces routing", type: :routing do
  let(:cid) { "81721200" }

  it "routes PATCH module_settings/captcha/surfaces" do
    expect(patch: "/#{cid}/admin/maintenance/platform/module_settings/captcha/surfaces").to route_to(
      controller: "admin/maintenance/platform/captcha/surfaces",
      action: "update",
      customer_id: cid
    )
  end

  it "routes PATCH module_settings/captcha/pages/:id" do
    expect(patch: "/#{cid}/admin/maintenance/platform/module_settings/captcha/pages/42").to route_to(
      controller: "admin/maintenance/platform/captcha/pages",
      action: "update",
      customer_id: cid,
      id: "42"
    )
  end
end
