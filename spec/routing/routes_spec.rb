# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard routing", type: :routing do
  it "routes GET /:cid/admin/dashboard to admin/dashboard#show" do
    expect(get: "/12345678/admin/dashboard").to route_to(
      controller: "admin/dashboards", action: "show", customer_id: "12345678"
    )
  end

  it "routes the domains page and each domain, and no longer routes an entities index" do
    expect(get: "/12345678/admin/domains").to route_to(
      controller: "admin/domains", action: "index", customer_id: "12345678"
    )
    expect(get: "/12345678/admin/domains/ungrouped").to route_to(
      controller: "admin/domains", action: "show", customer_id: "12345678", id: "ungrouped"
    )
    expect(get: "/12345678/admin/entities").not_to be_routable
  end

  it "lists forms on a domain or entity and keeps a shallow page show, with no pages index" do
    expect(get: "/12345678/admin/domains/ungrouped/pages").to route_to(
      controller: "admin/domains/pages", action: "index", customer_id: "12345678", domain_id: "ungrouped"
    )
    expect(get: "/12345678/admin/entities/42/pages").to route_to(
      controller: "admin/entities/pages", action: "index", customer_id: "12345678", entity_id: "42"
    )
    expect(get: "/12345678/admin/pages/9").to route_to(
      controller: "admin/pages", action: "show", customer_id: "12345678", id: "9"
    )
    expect(get: "/12345678/admin/pages/9/form").not_to be_routable
    expect(get: "/12345678/admin/pages").not_to be_routable
  end

  it "routes module entry show" do
    expect(get: "/12345678/admin/modules/payments/entries/transactions").to route_to(
      controller: "admin/module_entries", action: "show",
      customer_id: "12345678", module_key: "payments", key: "transactions"
    )
  end

  it "routes settings and module sub-pages" do
    expect(get: "/12345678/admin/settings").to route_to(
      controller: "admin/settings", action: "show", customer_id: "12345678"
    )
    expect(get: "/12345678/admin/settings/modules/payments").to route_to(
      controller: "admin/module_configs", action: "show",
      customer_id: "12345678", key: "payments"
    )
    expect(get: "/12345678/admin/settings/modules/payments/gateway").to route_to(
      controller: "admin/module_configs", action: "show",
      customer_id: "12345678", key: "payments", entry_key: "gateway"
    )
  end

  %w[authentication authentications email emails sms ai_assistant ai_assistants payment payments].each do |key|
    it "preserves generic #{key} settings root, save, and entry routes" do
      root = "/12345678/admin/settings/modules/#{key}"
      target = { controller: "admin/module_configs", customer_id: "12345678", key: key }
      expect(get: root).to route_to(target.merge(action: "show"))
      expect(patch: root).to route_to(target.merge(action: "update"))
      expect(get: "#{root}/some_entry").to route_to(target.merge(action: "show", entry_key: "some_entry"))
    end
  end

  it "no longer routes removed settings customer/users paths to settings" do
    expect(get: "/12345678/admin/settings/customer").not_to route_to(
      controller: "admin/settings"
    )
    expect(get: "/12345678/admin/settings/users").not_to route_to(
      controller: "admin/settings"
    )
  end
end
