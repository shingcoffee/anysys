# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::FinishStepComponent, type: :component do
  include JourneyPageHelpers
  include_context "student course association"

  let(:customer) { create(:customer) }
  let(:start_page) { student_journey_page(name: "Student form") }
  let(:course_page) { course_journey_page }
  let(:catalog) { Journeys::BuilderCatalog.new(pages: [start_page, course_page], domain: nil, customer_id: customer.id) }
  let(:earlier_rows) do
    [
      { key: "start", name: "Student form", entity_id: student_entity.id.to_s, optional: false },
      { key: "extra", name: "Optional extra", entity_id: student_entity.id.to_s, optional: true },
      { key: "courses", name: course_page.name, entity_id: bridge_entity.id.to_s, optional: false }
    ]
  end
  let(:step) do
    Journeys::Definition::Step.new(key: "finish", kind: "finish", action_key: nil, label: nil, inputs: {},
                                   repeat: false, optional: false,
                                   target: { "kind" => "record", "step" => "start", "message" => "Thanks for enrolling." })
  end

  before { Current.customer = customer }
  after { Current.reset }

  def render_finish(**options)
    render_inline(described_class.new(step: step, catalog: catalog, earlier_rows: earlier_rows, **options))
  end

  it "lists earlier non-optional records, groups pages, and shows the completion message" do
    render_finish

    row = page.find("[data-finish]")
    expect(row).to have_select("journey[steps][][finish_step]", selected: "Student form",
                                                                 options: ["Student form", course_page.name], visible: :all)
    expect(row).not_to have_css("option", text: "Optional extra", visible: :all)
    expect(row).to have_css("optgroup[label='#{student_entity.display_label}'] option", text: "Student form", visible: :all)
    expect(row).to have_css("optgroup[label='#{bridge_entity.display_label}'] option", text: course_page.name, visible: :all)
    message = row.find_field("journey[steps][][finish_message]")
    expect(message.value).to eq("Thanks for enrolling.")
    expect(message[:maxlength]).to eq("300")
    expect(message[:placeholder]).to eq(I18n.t("journeys.admin.finish_message_placeholder"))
    expect(message["aria-describedby"]).to eq("journey-finish-message-hint")
    expect(row).to have_css("#journey-finish-message-hint", text: I18n.t("journeys.admin.finish_message_hint"))
  end

  it "keeps a refused finish page and posted completion message" do
    render_finish(submitted: { "finish_page_id" => start_page.id.to_s, "finish_message" => "See you next term." })

    expect(page).to have_select("journey[steps][][finish_page_id]", selected: "Student form", visible: :all)
    expect(page).to have_field("journey[steps][][finish_message]", with: "See you next term.")
  end
end
