# frozen_string_literal: true

require "rails_helper"

RSpec.describe FlowchartInfoCardComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:flowchart) do
    create(:flowchart, :customer_specific_type, :launched_status, customer: customer,
                                                name: "Test Flowchart",
                                                description: "Test description")
  end

  def render_card(pages: [])
    with_request_url("/#{customer.id}/admin/maintenance/flowcharts/#{flowchart.id}", host: "www.example.com") do
      render_inline(described_class.new(flowchart: flowchart, pages: pages))
    end
  end

  describe "#format_datetime" do
    let(:component) { described_class.new(flowchart: flowchart, pages: []) }

    it "formats datetime with the locale long time format" do
      datetime = Time.zone.local(2026, 2, 11, 14, 30, 45)
      expect(component.format_datetime(datetime)).to eq(I18n.l(datetime, format: :long))
    end

    it "localizes datetime in zh-CN" do
      datetime = Time.zone.local(2026, 2, 11, 14, 30, 45)
      I18n.with_locale(:"zh-CN") do
        expect(component.format_datetime(datetime)).to eq(I18n.l(datetime, format: :long))
      end
    end

    it "returns dash for blank datetime" do
      expect(component.format_datetime(nil)).to eq("-")
    end
  end

  describe "rendering" do
    it "renders the heading, name, description and element count" do
      render_card

      expect(page).to have_text(I18n.t("chrome.flowchart_info_card.header"))
      expect(page).to have_text("Test Flowchart")
      expect(page).to have_text("Test description")
      expect(page).to have_text(I18n.t("chrome.flowchart_info_card.elements_count", count: flowchart.elements.length))
    end

    it "keeps the ID and UUID off the compact info card" do
      render_card

      expect(page).not_to have_css("dt", text: "ID")
      expect(page).not_to have_text(flowchart.uuid)
    end

    it "omits the description row when blank" do
      flowchart.update_column(:description, nil)
      render_card

      expect(page).not_to have_css("dt", text: I18n.t("common.labels.description"))
    end

    it "says no page uses the flowchart when none is bound" do
      render_card

      expect(page).to have_text(I18n.t("chrome.flowchart_info_card.used_by_pages"))
      expect(page).to have_text(I18n.t("chrome.flowchart_info_card.no_pages"))
      expect(page).not_to have_css("[data-role='bound-pages']")
    end

    it "links each bound page with its entity and flags pages that are not launched" do
      entity = create(:entity, customer: customer, name: "Student")
      live = create(:page, customer: customer, entity: entity, flowchart: flowchart, name: "Enrol", launched: true)
      draft = create(:page, customer: customer, entity: entity, flowchart: flowchart, name: "Draft enrol")

      render_card(pages: [live, draft])

      list = page.find("[data-role='bound-pages']")
      expect(list).to have_link("Enrol", href: "/#{customer.id}/admin/maintenance/pages/#{live.id}")
      expect(list).to have_link("Draft enrol", href: "/#{customer.id}/admin/maintenance/pages/#{draft.id}")
      expect(list).to have_text(entity.display_label)
      expect(list.all("li").last).to have_text(I18n.t("maint_core.pages.show.not_launched"))
      expect(list.all("li").first).not_to have_text(I18n.t("maint_core.pages.show.not_launched"))
    end
  end
end
