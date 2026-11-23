# frozen_string_literal: true

require "rails_helper"

RSpec.describe Flowcharts::LifecycleCardComponent, type: :component do
  subject(:component) { described_class.new(flowchart: flowchart, customer_id: 81_721_200) }

  def render_component
    with_request_url("/81721200/admin/maintenance/flowcharts/#{flowchart.id}", host: "www.example.com") do
      render_inline(component)
    end
  end

  let(:draft_flowchart) do
    build_stubbed(:flowchart, id: 8, status: :draft, uuid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee")
  end

  let(:launched_flowchart) do
    build_stubbed(:flowchart, id: 9, status: :launched, uuid: "11111111-2222-4333-8444-555555555555")
  end

  describe "draft flowchart" do
    let(:flowchart) { draft_flowchart }

    before { render_component }

    it "renders the Publishing heading" do
      expect(page).to have_text("Publishing")
    end

    it "shows the Draft badge" do
      expect(page).to have_text("Draft")
    end

    it "shows the Launch button" do
      expect(page).to have_button("Launch")
    end

    it "shows the draft hint" do
      expect(page).to have_text("Launch this flowchart to make it available")
    end

    it "renders the UUID with a copy control" do
      expect(page).to have_text(flowchart.uuid)
      expect(page).to have_css("[data-controller='click-to-copy']")
    end
  end

  describe "launched flowchart" do
    let(:flowchart) { launched_flowchart }

    before { render_component }

    it "shows the Launched badge" do
      expect(page).to have_text("Launched")
    end

    it "shows the Take Offline button" do
      expect(page).to have_button("Take Offline")
    end

    it "shows the launched hint" do
      expect(page).to have_text("This flowchart is live")
    end

    it "does not offer to launch a latest version when nothing is pending" do
      expect(page).not_to have_button(I18n.t("maint_core.flowcharts.launch_latest"))
    end
  end

  describe "launched flowchart with a pending draft version" do
    let(:flowchart) do
      create(:flowchart, :simple, :launched_status).tap do |fc|
        config = JSON.parse(fc.configuration).merge("metadata" => { "note" => "staged" })
        fc.update!(configuration: config.to_json)
      end
    end

    before { render_component }

    it "offers to launch the latest version alongside Take Offline" do
      expect(page).to have_button(I18n.t("maint_core.flowcharts.launch_latest"))
      expect(page).to have_button("Take Offline")
    end

    it "names the live and the draft version" do
      expect(page).to have_text(I18n.t("comp_misc.flowchart_lifecycle.pending_hint", live: 1, draft: 2))
    end
  end

  describe "launch_editable: false" do
    let(:flowchart) { draft_flowchart }
    subject(:component) do
      described_class.new(flowchart: flowchart, customer_id: 81_721_200, launch_editable: false)
    end

    before { render_component }

    it "hides the Launch button" do
      expect(page).not_to have_button("Launch")
    end
  end
end
