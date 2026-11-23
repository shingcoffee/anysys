# frozen_string_literal: true

require "rails_helper"

RSpec.describe PageBuilder::JourneyUsageComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:form) { build(:page, customer: customer, action_key: "student_add_course") }

  def edit_path(journey) = "/#{customer.id}/admin/maintenance/entities/journeys/#{journey.id}/edit"

  def finish_on(action_key)
    {
      "steps" => [
        { "key" => "start", "kind" => "create", "action_key" => "student_new" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "page", "action_key" => action_key } }
      ]
    }.to_json
  end

  it "lists this customer's journeys whose steps or finish open the page, each linking to its builder" do
    working = create(:journey, :launched, customer: customer, name: "Enrolment")
    finishing = create(:journey, customer: customer, name: "Admissions", definition: finish_on("student_add_course"))
    starting = create(:journey, customer: customer, name: "Courses first", definition: finish_on("other_page").sub("student_new", "student_add_course"))
    create(:journey, customer: customer, name: "Unrelated", definition: finish_on("other_page"))
    create(:journey, name: "Someone else's")

    render_inline(described_class.new(page: form, customer_id: customer.id))

    panel = page.find("[data-role='journey-usage']")
    expect(panel).to have_text(I18n.t("journeys.admin.usage.title"))
    expect(panel).to have_css("[data-role='journey-usage-count']", text: "3")
    links = panel.all("li a")
    expect(links.map { |link| link.find("span.truncate").text }).to eq(["Admissions", "Courses first", "Enrolment"])
    expect(links.map { |link| link.find("[data-role='journey-usage-role']").text })
      .to eq([I18n.t("journeys.admin.step_kind.finish"), I18n.t("journeys.admin.step_start"), I18n.t("journeys.admin.step_number", number: 2)])
    expect(panel).to have_link(href: edit_path(working), text: "Enrolment")
    expect(panel).to have_link(href: edit_path(finishing), text: "Admissions")
    expect(panel).to have_link(href: edit_path(starting))
    expect(panel.find_link(href: edit_path(working))).to have_css(".bg-emerald-500")
    expect(panel.find_link(href: edit_path(working))).to have_text(I18n.t("journeys.admin.status.launched"))
    expect(panel.find_link(href: edit_path(finishing))).to have_css(".bg-gray-300")
    expect(panel).not_to have_text("Unrelated")
    expect(panel).not_to have_text("Someone else's")
    expect(panel).not_to have_text(I18n.t("journeys.admin.usage.empty"))
  end

  it "shows the empty text when no journey uses the page" do
    create(:journey, customer: customer, definition: finish_on("other_page"))

    render_inline(described_class.new(page: form, customer_id: customer.id))

    expect(page).to have_css("[data-role='journey-usage']", text: I18n.t("journeys.admin.usage.empty"))
    expect(page).to have_css("[data-role='journey-usage-count']", text: "0")
    expect(page).not_to have_css("li a")
  end

  it "shows the empty text for a page without an action key, even beside steps that have none" do
    keyless = {
      "steps" => [
        { "key" => "start", "kind" => "create" },
        { "key" => "finish", "kind" => "finish", "target" => { "kind" => "page" } }
      ]
    }.to_json
    create(:journey, customer: customer, name: "Half built", definition: keyless)

    render_inline(described_class.new(page: build(:page, customer: customer, action_key: nil), customer_id: customer.id))

    expect(page).to have_css("[data-role='journey-usage']", text: I18n.t("journeys.admin.usage.empty"))
    expect(page).not_to have_text("Half built")
  end
end
