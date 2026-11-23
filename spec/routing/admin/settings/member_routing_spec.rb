# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Customer member settings routing", type: :routing do
  %i[get patch].each do |verb|
    it "routes #{verb} for the hub, source list, and display form to their dedicated controllers" do
      action = verb == :get ? "show" : "update"
      root = "/12345678/admin/settings/member"
      expect(verb => root).to route_to(controller: "admin/settings/members", action: action, customer_id: "12345678")
      expect(verb => "#{root}/sources/modules").to route_to(
        controller: "admin/settings/member_sources", action: action, customer_id: "12345678", key: "modules"
      )
      expect(verb => "#{root}/sources/modules/surfaces/payments").to route_to(
        controller: "admin/settings/member_surfaces", action: action, customer_id: "12345678",
        source_key: "modules", key: "payments"
      )
    end
  end
end
