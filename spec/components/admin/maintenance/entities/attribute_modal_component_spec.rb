# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Maintenance::Entities::AttributeModalComponent, type: :component do
  before { render_inline(described_class.new) }

  it "renders the modal target wrapper with dialog role" do
    expect(page).to have_css(
      "[data-entity-form-target='modal'][role='dialog'][aria-modal='true']"
    )
  end

  it "gives the dialog panel a fixed height" do
    expect(page).to have_css("[data-attr-modal-panel].h-\\[100dvh\\]")
    expect(page).to have_css("[data-attr-modal-panel].sm\\:h-\\[90vh\\]")
  end

  it "renders the modal title target" do
    expect(page).to have_css(
      "[data-entity-form-target='modalTitle']",
      text: "Add Attribute"
    )
  end

  it "renders the close button wired to entity-form#closeModal" do
    expect(page).to have_css(
      "button[data-action='click->entity-form#closeModal'][aria-label='Close modal']"
    )
  end

  it "renders the identity input targets" do
    %w[modalName modalDisplayLabel].each do |target|
      expect(page).to have_css("[data-entity-form-target='#{target}']")
    end
    expect(page).to have_css("input[type='hidden'][data-entity-form-target='modalNameSlug']", visible: :hidden)
  end

  it "does not display a Name Slug field" do
    expect(page).not_to have_text("Name Slug")
  end

  it "renders the HTML type select wired to entity-form#htmlTypeChanged" do
    expect(page).to have_css(
      "select[data-entity-form-target='modalHtmlType'][data-action='change->entity-form#htmlTypeChanged']"
    )
  end

  it "renders HTML type optgroups from HtmlTypeOptions" do
    HtmlTypeOptions.grouped_html_types.each_key do |category|
      expect(page).to have_css("optgroup[label='#{category}']")
    end
  end

  it "renders the field configuration section target" do
    expect(page).to have_css("[data-entity-form-target='optionsSection']")
  end

  it "places type-specific options immediately after HTML type and before description" do
    html = rendered_content
    type_at = html.index("data-entity-form-target=\"htmlTypeField\"")
    options_at = html.index("data-entity-form-target=\"optionsSection\"")
    description_at = html.index("data-entity-form-target=\"modalDescription\"")
    expect(type_at).to be < options_at
    expect(options_at).to be < description_at
  end

  it "renders manual/constant option toggle buttons" do
    expect(page).to have_text("Choices people can pick. The label is shown; the value is stored.")
    expect(page).to have_css(
      "button[data-action='click->entity-form#selectManualOptions']",
      text: "Manual Entry"
    )
    expect(page).to have_css(
      "button[data-action='click->entity-form#selectConstantOptions']",
      text: "Use Constant"
    )
    expect(page).to have_css("span.text-center", text: "Default")
    expect(page).to have_css("span.text-center", text: "Label")
    expect(page).to have_css("span.text-center", text: "Value")
  end

  it "renders the validators container and validator select" do
    expect(page).to have_css("[data-entity-form-target='validatorsContainer']")
    expect(page).to have_css(
      "select[data-entity-form-target='modalValidatorSelect']"
    )
  end

  it "renders the add validator button" do
    expect(page).to have_css(
      "button[data-action='click->entity-form#addValidator']"
    )
  end

  it "renders the validator config sub-panel targets" do
    %w[validatorSingleValueConfig validatorRangeConfig validatorPatternConfig validatorListConfig].each do |target|
      expect(page).to have_css("[data-entity-form-target='#{target}']")
    end
  end

  it "renders field visibility checkboxes for admin, member, and public" do
    %w[modalVisibilityAdmin modalVisibilityMember modalVisibilityPublic].each do |target|
      expect(page).to have_css("input[type='checkbox'][data-entity-form-target='#{target}']")
    end
  end

  it "renders validator-apply checkboxes for admin, member, and public" do
    %w[modalValidatorApplyAdmin modalValidatorApplyMember modalValidatorApplyPublic].each do |target|
      expect(page).to have_css("input[type='checkbox'][data-entity-form-target='#{target}'][checked]")
    end
  end

  it "renders editable checkboxes for admin, member, and public" do
    %w[modalEditableAdmin modalEditableMember modalEditablePublic].each do |target|
      expect(page).to have_css("input[type='checkbox'][data-entity-form-target='#{target}'][checked]")
    end
  end

  it "wires visibility checkboxes to visibilityAudienceChanged" do
    %w[modalVisibilityAdmin modalVisibilityMember modalVisibilityPublic].each do |target|
      expect(page).to have_css(
        "input[type='checkbox'][data-entity-form-target='#{target}'][data-action*='visibilityAudienceChanged']"
      )
    end
  end

  it "wires editable checkboxes to visibilityAudienceChanged" do
    %w[modalEditableAdmin modalEditableMember modalEditablePublic].each do |target|
      expect(page).to have_css(
        "input[type='checkbox'][data-entity-form-target='#{target}'][data-action*='visibilityAudienceChanged']"
      )
    end
  end

  it "labels the Can edit column and checkboxes for each audience" do
    expect(page).to have_css("span.text-center", text: I18n.t("comp_admin.attribute_modal.editable"))
    %w[admin member public].each do |key|
      audience = I18n.t("comp_admin.attribute_modal.#{key}")
      expect(page).to have_css(
        "input#attr-modal-edit-#{key}[aria-label='#{I18n.t("comp_admin.attribute_modal.editable_for", audience: audience)}']"
      )
    end
  end

  it "renders the editable hint under the existing visibility hint" do
    expect(page).to have_text(I18n.t("comp_admin.attribute_modal.visibility_hint"))
    expect(page).to have_text(I18n.t("comp_admin.attribute_modal.editable_hint"))
  end

  it "places computed config under the value-source toggle and before HTML type" do
    html = rendered_content
    toggle_at = html.index("data-action=\"click->entity-form#selectComputedMode\"")
    computed_at = html.index("data-entity-form-target=\"computedSection\"")
    control_at = html.index("data-entity-form-target=\"htmlTypeField\"")
    expect(toggle_at).to be < computed_at
    expect(computed_at).to be < control_at
  end

  it "nests type-specific options inside htmlTypeField and keeps description outside" do
    wrapper = page.find("[data-entity-form-target='htmlTypeField']", visible: :all)
    expect(wrapper).to have_css("[data-entity-form-target='optionsSection']", visible: :all)
    expect(wrapper).not_to have_css("[data-entity-form-target='modalDescription']")
  end

  it "renders Input and Computed value-source options hidden until associations exist" do
    expect(page).to have_css("[data-entity-form-target='valueSourceSection'].hidden")
    expect(page).to have_css("[data-entity-form-target='valueSourceSection']", text: "Value source")
    expect(page).to have_css(
      "button[data-action='click->entity-form#selectInputMode']",
      text: "Input"
    )
    expect(page).to have_css(
      "button[data-action='click->entity-form#selectComputedMode']",
      text: "Computed"
    )
  end

  it "renders validators and access headings" do
    expect(page).to have_text("Validators")
    expect(page).to have_text("Field visibility")
    expect(page).to have_text("Can edit")
    expect(page).to have_text("Apply validators")
  end

  it "renders Field / Rules / Access section tabs" do
    expect(page).to have_css("[role='tab'][data-tabs-id='definition']", text: "Field")
    expect(page).to have_css("[role='tab'][data-tabs-id='validation']", text: "Rules")
    expect(page).to have_css("[role='tab'][data-tabs-id='access']", text: "Access")
  end

  it "exposes audience rows for admin, member, and public" do
    keys = described_class.new.audience_rows.map { |row| row[:key] }
    expect(keys).to eq(%w[admin member public])
  end

  it "exposes editable_target on each audience row" do
    expect(described_class.new.audience_rows.map { |row| row[:editable_target] })
      .to eq(%w[modalEditableAdmin modalEditableMember modalEditablePublic])
  end

  it "renders the description textarea target" do
    expect(page).to have_css("textarea[data-entity-form-target='modalDescription']")
  end

  it "renders the submit button wired to entity-form#addAttributeFromModal" do
    expect(page).to have_css(
      "button[data-action='click->entity-form#addAttributeFromModal'][data-entity-form-target='modalSubmitBtn']",
      text: "Add Attribute"
    )
  end

  it "renders the modal footer cancel button" do
    footer_cancel = page.find_all(
      "button[data-action='click->entity-form#closeModal']"
    ).find { |btn| btn.text.strip == "Cancel" }
    expect(footer_cancel).not_to be_nil
  end

  it "offers Use Entity Records with an entity and a display-field select" do
    render_inline(described_class.new)

    button = page.find("button[data-entity-form-target='entityRecordsOptionsBtn']")
    expect(button).to have_text(I18n.t("comp_admin.attribute_modal.use_entity_records"))
    expect(button["data-action"]).to eq("click->entity-form#selectEntityRecordsOptions")

    section = page.find("[data-entity-form-target='entityRecordsOptionsSection']", visible: :all)
    expect(section[:class]).to include("hidden")
    expect(section).to have_css("select[data-entity-form-target='referenceEntitySelect'][data-action='change->entity-form#referenceEntityChanged']", visible: :all)
    expect(section).to have_css("select[data-entity-form-target='referenceLabelFieldSelect']", visible: :all)
    expect(section).to have_text(I18n.t("maint_core.entities.assoc.target_entity"))
    expect(section).to have_text(I18n.t("comp_admin.attribute_modal.display_field"))
    expect(section).to have_text(I18n.t("comp_admin.attribute_modal.entity_records_hint"))
  end

  it "renders the owner switch with the translated label and help" do
    expect(page).to have_css("[data-entity-form-target='ownerSection']", visible: :all)
    expect(page).to have_css("[data-entity-form-target='modalOwner']", visible: :all)
    expect(page).to have_text(I18n.t("comp_admin.attribute_modal.owner_label"))
    expect(page).to have_text(I18n.t("comp_admin.attribute_modal.owner_help"))
  end

  it "renders person entity ids as a JSON Stimulus value on the modal" do
    render_inline(described_class.new(person_entity_ids: [ 12, 34 ]))

    modal = page.find("[data-entity-form-target='modal']", visible: :all)
    expect(modal["data-entity-form-person-entity-ids-value"]).to eq([ 12, 34 ].to_json)
  end

  it "renders the owner switch when editing a regular entity" do
    entity = create(:entity)
    render_inline(described_class.new(entity: entity))

    expect(page).to have_css("[data-entity-form-target='ownerSection']", visible: :all)
    expect(page).to have_css("[data-entity-form-target='modalOwner']", visible: :all)
  end

  it "hides the owner switch when editing a bridge entity" do
    entity = create(:entity, category: :bridge)
    render_inline(described_class.new(entity: entity))

    expect(page).not_to have_css("[data-entity-form-target='ownerSection']", visible: :all)
    expect(page).not_to have_css("[data-entity-form-target='modalOwner']", visible: :all)
  end

  it "hides the owner switch when editing a person entity" do
    entity = person_entity
    render_inline(described_class.new(entity: entity))

    expect(entity.person?).to be(true)
    expect(page).not_to have_css("[data-entity-form-target='ownerSection']", visible: :all)
    expect(page).not_to have_css("[data-entity-form-target='modalOwner']", visible: :all)
  end

  it "resolves person entity ids from the entity's customer when none are passed" do
    customer = create(:customer)
    person = person_entity(customer)
    host = create(:entity, customer: customer, name: "Assignment")

    expect(described_class.new(entity: host).person_entity_ids).to eq([ person.id ])
  end

  it "looks up person entity ids for a customer when they are not passed in" do
    customer = create(:customer)
    person = person_entity(customer)
    create(:entity, customer: customer, name: "Course")

    expect(described_class.person_entity_ids_for(customer.id)).to eq([ person.id ])
    expect(described_class.person_entity_ids_for(nil)).to eq([])
  end

  it "includes a trashed person entity in the id list" do
    customer = create(:customer)
    person = person_entity(customer)
    person.soft_delete

    expect(described_class.person_entity_ids_for(customer.id)).to eq([ person.id ])
  end

  def person_entity(customer = create(:customer))
    model = EntityDefinitions::Capabilities::PERSON_MODEL
    enable_module!("authentication", customer).set_extendable_model!(model, true)
    create(:entity, customer: customer, extended_model: model)
  end
end
