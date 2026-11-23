# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page routing", type: :routing do
  let(:customer_id) { "12345678" }
  let(:uuid) { "550e8400-e29b-41d4-a716-446655440000" }

  describe "/:customer_id/page/:uuid" do
    it "routes GET to public_pages#show" do
      expect(get: "/#{customer_id}/page/#{uuid}").to route_to(
        controller: "public_pages",
        action: "show",
        customer_id: customer_id,
        uuid: uuid
      )
    end

    it "routes POST to public_pages#submit" do
      expect(post: "/#{customer_id}/page/#{uuid}").to route_to(
        controller: "public_pages",
        action: "submit",
        customer_id: customer_id,
        uuid: uuid
      )
    end

    it "does not route a non-UUID second segment under /page" do
      expect(get: "/#{customer_id}/page/not-a-uuid").not_to be_routable
    end
  end

  describe "former flowchart catch-all" do
    it "does not route /:customer_id/:uuid/:entity_id to a controller" do
      expect(get: "/#{customer_id}/#{uuid}/123").not_to be_routable
    end

    it "does not route POST /:customer_id/:uuid to a controller" do
      expect(post: "/#{customer_id}/#{uuid}").not_to be_routable
    end
  end

  describe "existing routes take precedence" do
    it "routes GET /:customer_id/admin/maintenance/flowcharts to flowcharts#index" do
      expect(get: "/#{customer_id}/admin/maintenance/flowcharts").to route_to(
        controller: "admin/maintenance/flowcharts",
        action: "index",
        customer_id: customer_id
      )
    end

    it "routes root to home#index" do
      expect(get: "/").to route_to(controller: "home", action: "index")
    end
  end
end
