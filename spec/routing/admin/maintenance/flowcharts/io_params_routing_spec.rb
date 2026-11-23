# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Tenant flowchart I/O routes", type: :routing do
  it "routes step actions to tenant introspection" do
    expect(post: "/12345678/admin/maintenance/flowcharts/step_actions/api_call/io_params").to route_to(
      controller: "admin/maintenance/flowcharts/step_io_params", action: "show",
      customer_id: "12345678", generator_action: "api_call"
    )
  end

  it "routes element introspection without a persisted flowchart ID" do
    expect(post: "/12345678/admin/maintenance/flowcharts/element_types/loop/io_params").to route_to(
      controller: "admin/maintenance/flowcharts/element_io_params", action: "show",
      customer_id: "12345678", element_type: "loop"
    )
  end
end
