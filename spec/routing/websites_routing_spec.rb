# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Website routes", type: :routing do
  let(:cid) { "12345678" }

  describe "public site" do
    it "routes GET /:customer_id/site to websites/pages#home" do
      expect(get: "/#{cid}/site").to route_to(
        controller: "websites/pages",
        action: "home",
        customer_id: cid
      )
    end

    it "routes GET /:customer_id/site/:page_slug to websites/pages#show" do
      expect(get: "/#{cid}/site/about").to route_to(
        controller: "websites/pages",
        action: "show",
        customer_id: cid,
        page_slug: "about"
      )
    end

    it "rejects a slug that is not kebab-case" do
      expect(get: "/#{cid}/site/About").not_to be_routable
      expect(get: "/#{cid}/site/hello_world").not_to be_routable
    end

    it "does not route POST /:customer_id/site" do
      expect(post: "/#{cid}/site").not_to be_routable
    end

    it "does not route POST /:customer_id/site/:page_slug" do
      expect(post: "/#{cid}/site/about").not_to be_routable
    end

    it "routes GET /:customer_id/site/media/:signed_id to websites/assets#show" do
      expect(get: "/#{cid}/site/media/abc--signed").to route_to(
        controller: "websites/assets",
        action: "show",
        customer_id: cid,
        signed_id: "abc--signed"
      )
    end
  end

  describe "admin modules" do
    it "no longer routes the former Pages / Website URL to the Website controller" do
      expect(get: "/#{cid}/admin/pages/website").to route_to(
        controller: "admin/pages", action: "show", customer_id: cid, id: "website"
      )
    end

    it "routes GET /:cid/admin/modules/website to pages#index" do
      expect(get: "/#{cid}/admin/modules/website").to route_to(
        controller: "admin/modules/website/pages",
        action: "index",
        customer_id: cid
      )
    end

    it "routes pages collection and member actions" do
      expect(get: "/#{cid}/admin/modules/website/pages").to route_to(
        controller: "admin/modules/website/pages", action: "index", customer_id: cid
      )
      expect(get: "/#{cid}/admin/modules/website/pages/new").to route_to(
        controller: "admin/modules/website/pages", action: "new", customer_id: cid
      )
      expect(post: "/#{cid}/admin/modules/website/pages").to route_to(
        controller: "admin/modules/website/pages", action: "create", customer_id: cid
      )
      expect(get: "/#{cid}/admin/modules/website/pages/5/edit").to route_to(
        controller: "admin/modules/website/pages", action: "edit", customer_id: cid, id: "5"
      )
      expect(patch: "/#{cid}/admin/modules/website/pages/5").to route_to(
        controller: "admin/modules/website/pages", action: "update", customer_id: cid, id: "5"
      )
      expect(delete: "/#{cid}/admin/modules/website/pages/5").to route_to(
        controller: "admin/modules/website/pages", action: "destroy", customer_id: cid, id: "5"
      )
      expect(get: "/#{cid}/admin/modules/website/pages/5/preview").to route_to(
        controller: "admin/modules/website/pages", action: "preview", customer_id: cid, id: "5"
      )
      expect(post: "/#{cid}/admin/modules/website/pages/5/preview").to route_to(
        controller: "admin/modules/website/pages", action: "preview", customer_id: cid, id: "5"
      )
      expect(patch: "/#{cid}/admin/modules/website/pages/reorder").to route_to(
        controller: "admin/modules/website/pages", action: "reorder", customer_id: cid
      )
      expect(post: "/#{cid}/admin/modules/website/media").to route_to(
        controller: "admin/modules/website/media", action: "create", customer_id: cid
      )
    end

    it "does not route GET show for a page" do
      expect(get: "/#{cid}/admin/modules/website/pages/5").not_to be_routable
    end

    it "does not offer site-wide publication from module records" do
      expect(patch: "/#{cid}/admin/modules/website/publication").not_to be_routable
    end
  end

  describe "admin settings" do
    it "routes GET /:cid/admin/settings/modules/website to sites#show" do
      expect(get: "/#{cid}/admin/settings/modules/website").to route_to(
        controller: "admin/settings/modules/website/sites",
        action: "show",
        customer_id: cid
      )
    end

    it "routes the site resource" do
      expect(get: "/#{cid}/admin/settings/modules/website/site").to route_to(
        controller: "admin/settings/modules/website/sites", action: "show", customer_id: cid
      )
      expect(patch: "/#{cid}/admin/settings/modules/website/site").to route_to(
        controller: "admin/settings/modules/website/sites", action: "update", customer_id: cid
      )
    end

    it "routes POST skeleton replace" do
      expect(post: "/#{cid}/admin/settings/modules/website/skeleton").to route_to(
        controller: "admin/settings/modules/website/skeletons",
        action: "create",
        customer_id: cid
      )
    end
  end

  describe "platform module settings" do
    it "routes GET skeletons gallery and layout catalog" do
      expect(get: "/#{cid}/admin/maintenance/platform/module_settings/website/skeletons").to route_to(
        controller: "admin/maintenance/platform/website/skeletons",
        action: "show",
        customer_id: cid
      )
      expect(get: "/#{cid}/admin/maintenance/platform/module_settings/website/skeletons/presence/edit").to route_to(
        controller: "admin/maintenance/platform/website/skeletons",
        action: "edit",
        customer_id: cid,
        key: "presence"
      )
      expect(get: "/#{cid}/admin/maintenance/platform/module_settings/website/layouts").to route_to(
        controller: "admin/maintenance/platform/website/layouts",
        action: "index",
        customer_id: cid
      )
    end
  end
end
