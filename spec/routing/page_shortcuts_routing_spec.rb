# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Page shortcut management routes", type: :routing do
  let(:base) { "/12345678/admin/maintenance/page_shortcuts" }
  let(:controller) { "admin/maintenance/page_shortcuts" }

  it "routes tenant-scoped index/create/update/destroy to the guarded controller" do
    expect(get: base).to route_to(controller: controller, action: "index", customer_id: "12345678")
    expect(post: base).to route_to(controller: controller, action: "create", customer_id: "12345678")
    expect(patch: "#{base}/42").to route_to(controller: controller, action: "update", customer_id: "12345678", id: "42")
    expect(put: "#{base}/42").to route_to(controller: controller, action: "update", customer_id: "12345678", id: "42")
    expect(delete: "#{base}/42").to route_to(controller: controller, action: "destroy", customer_id: "12345678", id: "42")
  end

  it "preserves canonical website, media and public form endpoints before the aliases" do
    uuid = SecureRandom.uuid
    expect(get: "/12345678/site").to route_to(controller: "websites/pages", action: "home", customer_id: "12345678")
    expect(get: "/12345678/site/pricing").to route_to(controller: "websites/pages", action: "show", customer_id: "12345678", page_slug: "pricing")
    expect(get: "/12345678/site/media/signed-id").to route_to(controller: "websites/assets", action: "show", customer_id: "12345678", signed_id: "signed-id")
    expect(get: "/12345678/page/#{uuid}").to route_to(controller: "public_pages", action: "show", customer_id: "12345678", uuid: uuid)
    expect(post: "/12345678/page/#{uuid}").to route_to(controller: "public_pages", action: "submit", customer_id: "12345678", uuid: uuid)
  end

  [
    ["WebsitePage", "websites/pages", "home"],
    ["WebsitePage", "websites/pages", "show"],
    ["Page", "public_pages", "show"]
  ].each do |type, destination, action|
    it "dispatches GET/HEAD root and prefixed nested aliases to the fixed #{destination}##{action} destination" do
      target = PageShortcuts::Target.new(
        customer_id: 12345678, target_type: type, target_id: 42,
        controller: destination, action: action, page_slug: nil, uuid: nil, canonical_path: "/12345678/site"
      )
      allow(PageShortcuts::Resolver).to receive(:cached_resolve).and_return(target)

      %i[get head].each do |verb|
        expect(verb => "/").to route_to(controller: destination, action: action)
        expect(verb => "/12345678/campaign/welcome").to route_to(
          controller: destination, action: action, shortcut_path: "12345678/campaign/welcome"
        )
      end
    end
  end

  it "routes public Page POST aliases through submit without admitting website POST aliases" do
    target = PageShortcuts::Target.new(
      customer_id: 12345678, target_type: "Page", target_id: 42,
      controller: "public_pages", action: "show", page_slug: nil, uuid: nil, canonical_path: "/12345678/page/form"
    )
    allow(PageShortcuts::Resolver).to receive(:cached_resolve).and_return(target)
    expect(post: "/").to route_to(controller: "public_pages", action: "submit")
    expect(post: "/12345678/campaign/join").to route_to(
      controller: "public_pages", action: "submit", shortcut_path: "12345678/campaign/join"
    )

    website_target = target.with(target_type: "WebsitePage", controller: "websites/pages", action: "home")
    allow(PageShortcuts::Resolver).to receive(:cached_resolve).and_return(website_target)
    expect(post: "/").not_to be_routable
    expect(post: "/12345678/campaign/welcome").not_to be_routable
  end
end
