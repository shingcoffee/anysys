# frozen_string_literal: true

require "rails_helper"

RSpec.describe ActivityTraceComponent, type: :component do
  after { Current.reset }

  let(:customer)   { create(:customer) }
  let(:flowchart_with_activity) do
    build_stubbed(:flowchart, customer_id: customer.id, activity: "# some generated ruby activity code")
  end
  let(:flowchart_no_activity) do
    build_stubbed(:flowchart, customer_id: customer.id, activity: nil)
  end
  let(:shared_flowchart) do
    build_stubbed(:flowchart, customer_id: nil, activity: "# shared activity")
  end

  def component_for(flowchart) = described_class.new(flowchart: flowchart)

  # ActivityTraceComponent#trace_url calls helpers.admin_maintenance_flowchart_traces_path
  # which requires a request context to resolve URL helpers.
  def render_component(flowchart)
    with_request_url("/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}", host: "www.example.com") do
      render_inline(component_for(flowchart))
    end
  end

  # -------------------------------------------------------------------
  # render? guard
  # -------------------------------------------------------------------
  describe "#render?" do
    it "returns true when flowchart has an activity" do
      expect(component_for(flowchart_with_activity).render?).to be true
    end

    it "returns false when flowchart has no activity" do
      expect(component_for(flowchart_no_activity).render?).to be false
    end

    it "does not render HTML when flowchart has no activity" do
      with_request_url("/#{customer.id}/admin/maintenance/flowcharts/1", host: "www.example.com") do
        render_inline(described_class.new(flowchart: flowchart_no_activity))
      end
      expect(page.text).to be_blank
    end
  end

  # -------------------------------------------------------------------
  # Happy path rendering
  # -------------------------------------------------------------------
  describe "with activity present" do
    before { render_component(flowchart_with_activity) }

    it "renders the activity-trace Stimulus controller" do
      expect(page).to have_css("[data-controller='activity-trace']")
    end

    it "sets the trace URL in data-activity-trace-url-value" do
      node = page.find("[data-controller='activity-trace']")
      expect(node["data-activity-trace-url-value"]).to include("traces")
    end

    it "renders the Run Activity button" do
      expect(page).to have_button("Run Activity")
    end

    it "renders the placeholder section" do
      expect(page).to have_text("Click \"Run Activity\" to execute and trace")
    end

    it "renders the results container (hidden initially)" do
      expect(page).to have_css("[data-activity-trace-target='results'].hidden")
    end

    it "renders the error container (hidden initially)" do
      expect(page).to have_css("[data-activity-trace-target='error'].hidden")
    end
  end

  # -------------------------------------------------------------------
  # effective_customer_id
  # -------------------------------------------------------------------
  describe "#effective_customer_id" do
    it "returns flowchart.customer_id for customer-specific flowcharts" do
      expect(component_for(flowchart_with_activity).effective_customer_id).to eq(customer.id)
    end

    it "falls back to Current.customer_id for shared flowcharts" do
      Current.customer_id = customer.id
      expect(component_for(shared_flowchart).effective_customer_id).to eq(customer.id)
    end
  end
end
