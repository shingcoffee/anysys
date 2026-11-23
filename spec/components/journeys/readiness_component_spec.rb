# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::ReadinessComponent, type: :component do
  it "renders nothing when issues are omitted" do
    expect(render_inline(described_class.new(issues: nil)).to_html).to be_blank
  end

  it "shows a ready status when there are no issues" do
    render_inline(described_class.new(issues: []))

    expect(page).to have_css("h2", text: I18n.t("journeys.admin.readiness.title"))
    status = page.find("[role='status']")
    expect(status).to have_text(I18n.t("journeys.admin.readiness.ready"))
    expect(status).to have_css("svg[aria-hidden='true']")
    expect(page).not_to have_css("[role='list']")
  end

  it "lists each issue with a decorative warning icon" do
    render_inline(described_class.new(issues: ["First blocker.", "Second blocker."]))

    expect(page).to have_text(I18n.t("journeys.admin.readiness.issues"))
    items = page.all("[role='list'] li")
    expect(items.map(&:text).map(&:strip)).to eq(["First blocker.", "Second blocker."])
    expect(items).to all(have_css("svg.text-warning[aria-hidden='true']"))
    expect(page).not_to have_css("[role='status']")
  end
end
