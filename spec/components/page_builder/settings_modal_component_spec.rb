# frozen_string_literal: true

require "rails_helper"

# The settings modal is a presentation shell over the live page-builder state:
# controls carry data-property / data-action, and a `page-settings` Stimulus
# controller switches between the sidebar sections.
RSpec.describe PageBuilder::SettingsModalComponent, type: :component do
  let_it_be(:customer) { create(:customer) }

  before { Current.customer = customer }
  after  { Current.customer = nil }

  def render_modal(page: build(:page, customer: customer))
    render_inline(described_class.new(page: page, customer_id: customer.id))
  end

  it "wires the section-switching Stimulus controller" do
    render_modal
    expect(page).to have_css("[data-controller='page-settings']")
    expect(page).to have_css("button[data-page-settings-target='tab'][data-section='general']")
    expect(page).to have_css("[data-page-settings-target='panel'][data-section='after_submit']")
  end

  it "renders the core sections and opens on the After submit pane by default" do
    render_modal
    %w[general steps after_submit].each do |key|
      expect(page).to have_css("button[data-page-settings-target='tab'][data-section='#{key}']")
    end
    expect(page).to have_css("[data-page-settings-target='panel'][data-section='after_submit']:not(.hidden)")
    expect(page).to have_css("[data-page-settings-target='panel'][data-section='general'].hidden")
    expect(page).to have_css("[data-page-settings-target='panel'][data-section='steps'].hidden")
  end

  it "preserves the submit-button, wizard and success-message controls" do
    render_modal
    expect(page).to have_css("input[data-property='submit_button_text']")
    expect(page).to have_css("input[data-property='wizard_mode']")
    expect(page).to have_css("input[data-property='show_progress']")
    expect(page).to have_css("input[data-property='success_message'][data-action*='updateFormSettings']")
    expect(page).not_to have_css("select[data-property='after_submit']")
  end

  it "reflects persisted values into the controls" do
    page_record = build(:page, customer: customer,
      configuration: { form_settings: { submit_button_text: "Donate now", success_message: "Thanks for giving" } }.to_json)
    render_modal(page: page_record)

    expect(page).to have_css("input[data-property='submit_button_text'][value='Donate now']")
    expect(page).to have_css("input[data-property='success_message'][value='Thanks for giving']")
  end

  describe "submission modes" do
    it "checks both modes for a page without a setting" do
      render_modal
      %w[create update].each do |mode|
        expect(page).to have_css("[data-section='general'] input[type='checkbox'][data-submission-mode][value='#{mode}'][checked]" \
                                 "[data-action='change->page-builder#updateSubmissionModes']")
      end
    end

    it "checks only the stored modes" do
      render_modal(page: build(:page, customer: customer, configuration: { form_settings: { modes: ["update"] } }.to_json))
      expect(page).to have_css("input[data-submission-mode][value='update'][checked]")
      expect(page).to have_css("input[data-submission-mode][value='create']:not([checked])")
    end
  end

  describe "locked inputs" do
    let_it_be(:student) { create(:entity, customer: customer, name: "Student") }
    let_it_be(:course) { create(:entity, customer: customer, name: "Course") }
    let_it_be(:bridge) do
      create(:entity, customer: customer, name: "Enrolment", property_schema: [
        { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "select", "entity_id" => student.id.to_s },
        { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "html_type" => "select", "entity_id" => course.id.to_s },
        { "name" => "Note", "name_slug" => "note", "type" => "String", "html_type" => "text" }
      ].to_json)
    end

    it "adds an Inputs section right after General" do
      render_modal
      expect(page.all("button[data-page-settings-target='tab']").map { |tab| tab["data-section"] }.first(2)).to eq(%w[general inputs])
      expect(page).to have_css("[data-page-settings-target='panel'][data-section='inputs'].hidden")
    end

    it "lists one checkbox per reference field, checked when it is a locked input" do
      page_record = build(:page, customer: customer, entity: bridge,
                                 configuration: { form_settings: { inputs: [{ field: "student", entity_id: student.id }] } }.to_json)
      render_modal(page: page_record)

      boxes = page.all("[data-section='inputs'] input[type='checkbox'][data-page-input]")
      expect(boxes.map(&:value)).to eq(%w[student course])
      expect(page).to have_css("input[data-page-input][value='student'][data-entity-id='#{student.id}'][checked]" \
                               "[data-action='change->page-builder#updatePageInputs']")
      expect(page).to have_css("input[data-page-input][value='course'][data-entity-id='#{course.id}']:not([checked])")
      expect(page).not_to have_text(I18n.t("comp_page_builder.settings_modal.inputs_empty"))
    end

    it "offers letting members change and remove the rows from their record, checked when stored" do
      render_modal(page: build(:page, customer: customer, entity: bridge))
      expect(page).to have_css("[data-section='inputs'] input[type='checkbox'][data-property='manage_rows']" \
                               "[data-action='change->page-builder#updateFormSettings']:not([checked])")
      expect(page).to have_text(I18n.t("comp_page_builder.settings_modal.manage_rows"))

      render_modal(page: build(:page, customer: customer, entity: bridge, configuration: { form_settings: { manage_rows: true } }.to_json))
      expect(page).to have_css("input[data-property='manage_rows'][checked]")
    end

    it "offers a dropdown of another entity's records as a lockable input" do
      pupil = create(:entity, customer: customer, name: "Pupil",
                              property_schema: [{ "name" => "Name", "name_slug" => "name", "type" => "String", "html_type" => "text" }].to_json)
      roster = create(:entity, customer: customer, name: "Roster", property_schema: [
        { "name" => "Pupil", "name_slug" => "pupil", "type" => "String", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => pupil.id.to_s, "label_field" => "name" } },
        { "name" => "Level", "name_slug" => "level", "type" => "String", "html_type" => "select", "config" => { "options" => %w[A B] } }
      ].to_json)
      render_modal(page: build(:page, customer: customer, entity: roster))

      expect(page.all("[data-section='inputs'] input[data-page-input]").map(&:value)).to eq(%w[pupil])
      expect(page).to have_css("input[data-page-input][value='pupil'][data-entity-id='#{pupil.id}']:not([checked])")
    end

    it "explains when the record type has no reference fields" do
      render_modal(page: build(:page, customer: customer, entity: student))
      expect(page).not_to have_css("input[data-page-input]")
      expect(page).not_to have_css("input[data-property='manage_rows']")
      expect(page).to have_css("[data-section='inputs']", text: I18n.t("comp_page_builder.settings_modal.inputs_empty"))
    end
  end

  it "does not offer go-to-page or handoff after-submit controls" do
    render_modal
    expect(page).not_to have_css("[data-after-submit='page']")
    expect(page).not_to have_css("[data-handoff-panel]")
    expect(page).to have_css("[data-section='after_submit'] input[data-property='success_message']")
  end

  context "when the Captcha module is not available" do
    it "omits the Security section" do
      render_modal
      expect(page).not_to have_css("[data-section='security']")
    end
  end

  context "when the Captcha module is available" do
    let!(:captcha_module) do
      FeatureModules::Module.find_or_initialize_by(key: "captcha").tap do |m|
        m.name = "Captcha"
        m.status = :active
        m.configuration_schema = {}.to_json
        m.save!
      end
    end
    let!(:assignment) do
      create(:customer_feature_module, customer: customer, feature_module: captcha_module,
             status: :active, configuration: {}.to_json)
    end

    it "does not show a per-page captcha toggle (throttle lives in Captcha settings)" do
      render_modal
      expect(page).not_to have_css("[data-section='security']")
    end
  end
end
