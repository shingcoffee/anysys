# frozen_string_literal: true

require "rails_helper"

RSpec.describe Journeys::StepRowComponent, type: :component do
  include JourneyPageHelpers
  include_context "student course association"

  let(:customer) { create(:customer) }
  let(:start_page) { student_journey_page(name: "Student form") }
  let(:course_page) { course_journey_page }
  let(:catalog) { Journeys::BuilderCatalog.new(pages: [start_page, course_page], domain: nil, customer_id: customer.id) }
  let(:earlier) { [{ key: "start", name: "Student form", entity_id: student_entity.id.to_s, optional: false }] }

  before { Current.customer = customer }
  after { Current.reset }

  def step(**attrs)
    defaults = { key: "relate_1", kind: "relate", action_key: "student_add_course", label: nil,
                 inputs: {}, repeat: false, optional: false, target: nil }
    Journeys::Definition::Step.new(**defaults.merge(attrs))
  end

  def render_row(**options)
    options = { step: step, index: 1, catalog: catalog, earlier_rows: earlier }.merge(options)
    render_inline(described_class.new(**options))
  end

  it "renders a relate row with grouped pages, a hint, and fill pickers filtered by entity" do
    render_row(step: step(inputs: { "student" => "start" }, repeat: true))

    row = page.find("[data-journey-builder-target='row']")
    expect(row["data-step-mode"]).to eq("relate")
    expect(row).to have_css("optgroup[label='#{student_entity.display_label}']", visible: :all)
    expect(row).to have_css("optgroup[label='#{bridge_entity.display_label}']", visible: :all)
    expect(row).to have_select("journey[steps][][page_id]", selected: course_page.name, visible: :all)
    expect(row.find("[data-step-page]")["aria-describedby"]).to eq(row.find("[data-step-hint]")["id"])
    expect(row.find("[data-step-hint]").text).to include(I18n.t("journeys.admin.page_hint.locks", fields: "Student"))
    expect(row).to have_css("fieldset[data-step-inputs-section] legend", text: I18n.t("journeys.admin.step_fill"), visible: :all)
    fill = row.find("[data-step-input][data-step-input-entity='#{student_entity.id}']", visible: :all)
    expect(fill[:name]).to eq("journey[steps][][inputs][student]")
    expect(fill.value).to eq("start")
    expect(fill).to have_css("option[value='']", text: I18n.t("journeys.admin.step_fill_none"), visible: :all)
    expect(row).to have_checked_field("journey[steps][][repeat]", visible: :all)
    expect(row).to have_unchecked_field("journey[steps][][optional]", visible: :all)
    expect(row).not_to have_css("input[type='hidden'][name='journey[steps][][repeat]']", visible: :all)
    expect(row).not_to have_css("input[type='hidden'][name='journey[steps][][optional]']", visible: :all)
  end

  it "blanks a fill picker when the saved step is not an earlier match for that entity" do
    render_row(earlier_rows: [
      { key: "start", name: "Student form", entity_id: student_entity.id.to_s, optional: false },
      { key: "other", name: "Other", entity_id: "999", optional: false }
    ], step: step(inputs: { "student" => "other" }))

    fill = page.find("select[name='journey[steps][][inputs][student]']", visible: :all)
    expect(fill.value).to eq("")
    expect(fill).not_to have_css("option[value='other']", visible: :all)
  end

  it "renders create mode for a page that locks nothing" do
    render_row(step: step(key: "start", kind: "create", action_key: "student_new"), index: 0, earlier_rows: [])

    row = page.find("[data-journey-builder-target='row']")
    expect(row["data-step-mode"]).to eq("create")
    expect(row.find("[data-step-inputs]", visible: :all).text).to be_blank
    expect(row).to have_css("[class*='group-data-[step-mode=create]/step:block']", text: I18n.t("journeys.admin.step_independent"), visible: :all)
    expect(row).to have_css("input[data-step-optional]", visible: :all)
  end

  it "renders none mode and an empty inputs container for the blank template row" do
    render_row(step: nil, index: nil, earlier_rows: [])

    row = page.find("[data-journey-builder-target='row']")
    expect(row["data-step-mode"]).to eq("none")
    expect(row.find("[data-step-key]", visible: :all).value).to eq("")
    expect(row.find("[data-step-inputs]", visible: :all).text).to be_blank
    expect(row.find("select[name='journey[steps][][page_id]']", visible: :all).value).to eq("")
    expect(row).to have_css("option[value='']", text: I18n.t("journeys.admin.step_page_none"), visible: :all)
  end

  it "keeps a refused page choice and checks optional without a hidden companion" do
    render_row(step: step(action_key: "student_new", optional: true), submitted: { "page_id" => course_page.id.to_s })

    row = page.find("[data-journey-builder-target='row']")
    expect(row["data-step-mode"]).to eq("relate")
    expect(row).to have_select("journey[steps][][page_id]", selected: course_page.name, visible: :all)
    expect(row).to have_checked_field("journey[steps][][optional]", visible: :all)
    expect(row).to have_css("input[data-step-optional][data-action='change->journey-builder#refresh']", visible: :all)
    expect(row).to have_css("[class*='group-has-[[data-step-optional]:checked]/step:inline-flex']", text: I18n.t("journeys.optional"), visible: :all)
  end

  describe "a row an earlier step's processing may leave out" do
    def row = page.find("[data-journey-builder-target='row']")
    def skipped_by = row.find("[data-step-skipped-by]", visible: :all).text

    it "checks the setting, badges the row and names the earlier steps whose processing can leave it out" do
      rows = earlier + [{ key: "intake", name: "Intake form", entity_id: student_entity.id.to_s, optional: false, skips: %w[relate_1] }]
      render_row(step: step(conditional: true), earlier_rows: rows)

      box = row.find("input[type='checkbox'][name='journey[steps][][conditional]'][data-step-conditional]", visible: :all)
      expect(box).to be_checked
      expect(box["data-action"]).to eq("change->journey-builder#refresh")
      expect(row).not_to have_css("input[type='hidden'][name='journey[steps][][conditional]']", visible: :all)
      expect(row).to have_css("[class*='group-has-[[data-step-conditional]:checked]/step:inline-flex']",
                              text: I18n.t("journeys.admin.step_conditional_badge"), visible: :all)
      expect(row).to have_text(I18n.t("journeys.admin.step_conditional_hint"))
      expect(skipped_by).to eq(I18n.t("journeys.admin.step_conditional_by", steps: "Intake form"))
    end

    it "says no earlier processing leaves it out yet, and leaves an ordinary row unchecked" do
      render_row(step: step(conditional: true))
      expect(skipped_by).to eq(I18n.t("journeys.admin.step_conditional_none"))

      render_row
      expect(row).to have_unchecked_field("journey[steps][][conditional]", visible: :all)
    end

    it "shows the page's On submit block, without what only a new record does on a row that edits one" do
      render_row(step: step(key: "review", kind: "update", action_key: "student_new", record: "start"))

      expect(row).to have_css("[data-step-effects]:not([hidden])", visible: :all)
      expect(row.all("[data-step-effects-lines] li", visible: :all).map(&:text)).to eq([I18n.t("journeys.admin.effects.saves_only")])

      render_row(step: nil, index: nil, earlier_rows: [])
      expect(row).to have_css("[data-step-effects][hidden]", visible: :all)
    end
  end

  describe "a row that edits a record" do
    let(:review) { step(key: "review", kind: "update", action_key: "student_new", record: "start", optional: true) }

    def row = page.find("[data-journey-builder-target='row']")
    def record_picker = row.find("select[name='journey[steps][][record]'][data-step-record]", visible: :all)

    it "is set to edit, offers only pages that edit records, and picks the earlier record of its page's type" do
      render_row(step: review)

      expect(row["data-step-mode"]).to eq("update")
      expect(row).to have_select("journey[steps][][kind]", selected: I18n.t("journeys.admin.step_kind.update"),
                                                           options: [I18n.t("journeys.admin.step_kind.add"), I18n.t("journeys.admin.step_kind.update")],
                                                           visible: :all)
      expect(row).to have_css("option[value='#{start_page.id}'][selected]:not([disabled])", visible: :all)
      expect(row).to have_css("option[value='#{course_page.id}'][disabled][hidden]", visible: :all)
      expect([record_picker["data-step-input-entity"], record_picker.value]).to eq([student_entity.id.to_s, "start"])
      expect(record_picker).to have_css("option[value='']", text: I18n.t("journeys.admin.step_fill_none"), visible: :all)
      expect(record_picker["aria-describedby"]).to eq("journey-step-hint-review-record")
      expect(row).to have_css("[class*='group-data-[step-mode=update]/step:block'] label",
                              text: I18n.t("journeys.admin.step_record"), visible: :all)
      expect(row).to have_css("[class*='group-data-[step-mode=update]/step:flex'] input[data-step-optional][checked]", visible: :all)
    end

    it "blanks a record that is no earlier step of the page's type" do
      render_row(step: review.with(record: "gone"))
      expect(record_picker.value).to eq("")

      render_row(step: review, earlier_rows: [{ key: "start", name: "Course", entity_id: course_entity.id.to_s, optional: false }])
      expect(record_picker).not_to have_css("option[value='start']", visible: :all)
    end

    it "keeps the posted kind and record on a refused save" do
      render_row(step: step, submitted: { "kind" => "update", "page_id" => start_page.id.to_s, "record" => "start" })
      expect(row["data-step-mode"]).to eq("update")
      expect(record_picker.value).to eq("start")

      render_row(step: review, submitted: { "kind" => "add", "page_id" => start_page.id.to_s })
      expect(row["data-step-mode"]).to eq("create")
      expect(row).to have_select("journey[steps][][kind]", selected: I18n.t("journeys.admin.step_kind.add"), visible: :all)
      expect(row).not_to have_css("option[disabled]", visible: :all)
    end

    it "never edits on the lead row, and offers no record without a page" do
      render_row(step: review, index: 0, lead: true, earlier_rows: [])
      expect(row["data-step-mode"]).to eq("create")
      expect(row).to have_select("journey[steps][][kind]", selected: I18n.t("journeys.admin.step_kind.add"), visible: :all)

      render_row(step: review.with(action_key: nil))
      expect(record_picker["data-step-input-entity"]).to eq("")
      expect(record_picker.all("option", visible: :all).map(&:value)).to eq([""])
    end
  end
end
