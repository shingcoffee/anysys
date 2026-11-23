# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::ListComponent, type: :component do
  let(:customer) { create(:customer) }

  it "lists each journey as a table row on wider screens and a linked item on mobile" do
    draft = create(:journey, customer: customer, name: "Enrolment", key: "enrolment", visible_audiences: %w[admin member])
    live = create(:journey, :launched, customer: customer, name: "Intake")

    render_inline(described_class.new(journeys: [draft, live], customer_id: customer.id))

    edit = "/#{customer.id}/admin/maintenance/entities/journeys/#{draft.id}/edit"
    table = page.find("table.hidden.md\\:table")
    expect(table).to have_css("th[scope='col']", text: I18n.t("journeys.admin.columns.status"))
    expect(table).not_to have_css("th", text: I18n.t("journeys.admin.fields.domain"))
    expect(table).to have_css("tr", count: 3)
    row = table.find("tr", text: "Enrolment")
    expect(row).to have_link("Enrolment", href: edit)
    expect(row.find_link("Enrolment")["data-turbo-frame"]).to eq("_top")
    expect(row).to have_css(".font-mono", text: "enrolment")
    expect(row).to have_css(".badge", text: I18n.t("journeys.admin.status.draft"))
    expect(row).to have_css("td", text: I18n.t("journeys.admin.step_count", count: 2))
    expect(row).to have_text("#{I18n.t('journeys.audiences.admin')}, #{I18n.t('journeys.audiences.member')}")
    expect(row).to have_css("time[datetime='#{draft.updated_at.iso8601}']")
    intake = table.find("tr", text: "Intake")
    expect(intake).to have_css(".badge", text: I18n.t("journeys.admin.status.launched"))

    items = page.find("ul.md\\:hidden")
    expect(items).to have_css("li", count: 2)
    expect(items).to have_link(href: edit, text: "Enrolment")
  end

  it "counts a user step among the steps" do
    user_first = create(:journey, customer: customer, name: "Register", definition: { "steps" => [
      { "key" => "user", "kind" => "user" },
      { "key" => "start", "kind" => "create", "action_key" => "student_new" },
      { "key" => "finish", "kind" => "finish", "target" => { "kind" => "record", "step" => "start" } }
    ] }.to_json)

    render_inline(described_class.new(journeys: [user_first], customer_id: customer.id))

    expect(page.find("table tr", text: "Register")).to have_css("td", text: I18n.t("journeys.admin.step_count", count: 2))
  end

  it "says when the domain has no journeys yet" do
    render_inline(described_class.new(journeys: [], customer_id: customer.id))

    expect(page).to have_text(I18n.t("journeys.admin.empty_title"))
    expect(page).to have_text(I18n.t("journeys.admin.empty_description"))
    expect(page).not_to have_css("table")
  end
end
