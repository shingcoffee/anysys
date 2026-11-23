# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Settings::Modules::Emails::TemplateTokenEditorComponent, type: :component do
  let(:customer) { build_stubbed(:customer, id: 81721200) }
  let(:entity) { build_stubbed(:entity, :with_name_status_schema, customer: customer, display_label: "Supporters") }
  let(:token) { build(:email_template_token, entity: entity, customer: entity.customer, label: "Supporter name") }
  let(:attributes) { { entity.id.to_s => [["Name", "name"], ["Status", "status"]] } }

  def render_editor
    render_inline(described_class.new(customer_id: entity.customer_id, token: token, entities: [entity], entity_attributes: attributes))
  end

  it "renders the new batch form with record-specific preselected fields and editable display names" do
    render_editor
    expect(page).to have_css("h1", text: "Add personalization fields", count: 1)
    expect(page).to have_select("Entity", selected: "Supporters")
    expect(page).to have_css("input[type=checkbox][checked]", count: 2, visible: :all)
    expect(page).to have_css("input[name='emails_template_token[fields][0][label]'][value='Name']", visible: :all)
    expect(page).to have_css("input[name='emails_template_token[fields][1][label]'][value='Status']", visible: :all)
    expect(page).to have_text("Custom fields are currently left blank in sent emails")
    expect(page).to have_button("Add selected fields")
    expect(page).to have_link("Cancel", href: "/#{entity.customer_id}/admin/settings/modules/emails/template_tokens")
  end

  it "renders edits as PATCH with a linked personalization breadcrumb" do
    allow(token).to receive(:persisted?).and_return(true)
    token.id = 123
    render_editor
    expect(page).to have_css("h1", text: "Edit personalization field")
    expect(page).to have_css("form[action='/#{entity.customer_id}/admin/settings/modules/emails/template_tokens/123']")
    expect(page).to have_css("input[name='_method'][value='patch']", visible: :all)
    expect(page).to have_select("Entity", selected: "Supporters")
    expect(page).to have_select("Field", selected: "Name")
    expect(page).to have_field("Display name", with: "Supporter name")
    expect(page).to have_text("Custom fields are currently left blank in sent emails")
    expect(page).to have_css("[data-email-template-token-form-target='label']")
    expect(page).to have_button("Save changes")
    expect(page).to have_link("Email personalization", href: "/#{entity.customer_id}/admin/settings/modules/emails/template_tokens")
  end

  it "excludes fields already used by other tokens but preserves the current field" do
    allow(token).to receive(:persisted?).and_return(true)
    token.id = 123
    render_inline(described_class.new(customer_id: entity.customer_id, token: token, entities: [entity],
                                      entity_attributes: attributes, existing_slugs: { entity.id => %w[name status] }))
    expect(page).to have_select("Field", options: ["Choose a field", "Name"], selected: "Name")
  end

  it "keeps validation errors and entered selections on the form" do
    token.errors.add(:label, "has already been taken")
    render_editor
    expect(page).to have_text("has already been taken")
    expect(page).to have_select("Entity", selected: "Supporters")
  end

  it "retains rejected label, entity and field values without syncing them onto the token" do
    allow(token).to receive(:persisted?).and_return(true)
    token.id = 123
    original = token.attributes.slice("label", "entity_id", "attribute_slug")
    token.errors.add(:label, :blank)
    submitted = { "label" => "", "entity_id" => "not-an-id", "attribute_slug" => "unavailable-field" }
    render_inline described_class.new(customer_id: entity.customer_id, token: token, entities: [entity],
      entity_attributes: attributes, submitted_values: submitted)

    expect(page).to have_field("Display name", with: "")
    expect(page).to have_select("Entity", selected: "not-an-id")
    expect(page).to have_select("Field", selected: "unavailable-field")
    expect(page).to have_text(token.errors.full_messages.first)
    expect(token.attributes.slice("label", "entity_id", "attribute_slug")).to eq(original)
  end

  it "keeps overlong display text and a rejected already-used field selected for correction" do
    allow(token).to receive(:persisted?).and_return(true)
    token.id = 123
    original = token.attributes.slice("label", "entity_id", "attribute_slug")
    invalid_label = "X" * 101
    token.errors.add(:label, :too_long, count: 100)
    render_inline described_class.new(customer_id: entity.customer_id, token: token, entities: [entity],
      entity_attributes: attributes, existing_slugs: { entity.id => %w[name status] },
      submitted_values: { "label" => invalid_label, "entity_id" => entity.id.to_s, "attribute_slug" => "status" })

    expect(page).to have_field("Display name", with: invalid_label)
    expect(page).to have_select("Field", selected: "Status")
    expect(token.attributes.slice("label", "entity_id", "attribute_slug")).to eq(original)
  end
end
