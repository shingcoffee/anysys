# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pages::VisibilityContract do
  let(:customer) { create(:customer) }
  let(:page)     { build(:page, customer: customer) }

  def contract_for(page_record = page)
    described_class.new(page_record)
  end

  def message(key, **vars)
    I18n.t("maint_core.errors.page_launch.#{key}", **vars)
  end

  it "maps an exact audience set onto the boolean columns" do
    c = contract_for
    expect(c.validate("visible_audiences" => %w[member public])).to be(true)
    expect(c.audience_admin).to be(false)
    expect(c.audience_member).to be(true)
    expect(c.audience_public).to be(true)
  end

  it "accepts a symbol-keyed visible_audiences param" do
    c = contract_for
    expect(c.validate(visible_audiences: %w[admin member])).to be(true)
    expect(c.audience_admin).to be(true)
    expect(c.audience_member).to be(true)
    expect(c.audience_public).to be(false)
  end

  it "ignores unknown audience names" do
    c = contract_for
    expect(c.validate("visible_audiences" => %w[admin bogus])).to be(true)
    expect(c.audience_admin).to be(true)
    expect(c.audience_member).to be(false)
  end

  it "rejects an empty or absent audience list" do
    blank = I18n.t("maint_core.errors.validations.page_audiences_blank")

    empty = contract_for
    expect(empty.validate("visible_audiences" => [])).to be(false)
    expect(empty.errors[:base]).to include(blank)

    absent = contract_for
    expect(absent.validate({})).to be(false)
    expect(absent.errors[:base]).to include(blank)
  end

  it "rejects an invalid action key and stores a blank key as nil" do
    invalid = I18n.t("maint_core.errors.validations.page_action_key_invalid")

    c = contract_for
    expect(c.validate("visible_audiences" => %w[admin], "action_key" => "Enroll")).to be(false)
    expect(c.errors[:action_key]).to include(invalid)

    c = contract_for
    expect(c.validate("visible_audiences" => %w[admin], "action_key" => "  ")).to be(true)
    expect(c.action_key).to be_nil
  end

  it "persists the exact audience set and action key" do
    persisted = create(:page, customer: customer)
    c = contract_for(persisted)
    expect(c.validate("visible_audiences" => %w[admin member], "action_key" => "enroll")).to be(true)
    expect(c.save).to be_truthy
    persisted.reload
    expect(persisted.visible_audiences).to eq(%w[admin member])
    expect(persisted.action_key).to eq("enroll")
  end

  describe "widening a launched form" do
    let(:student) do
      create(:entity, customer: customer, property_schema: [
        { "name" => "姓名", "name_slug" => "full_name", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "presence" }], "visibility" => { "public" => false } },
        { "name" => "Email", "name_slug" => "email", "type" => "String", "html_type" => "text",
          "validators" => [{ "type" => "presence" }], "validator_apply" => { "admin" => false } }
      ].to_json)
    end

    def form(launched:, audiences: %w[admin], entity: student, **attrs)
      page = build(:page, customer: customer, entity: entity, launched: launched,
                          configuration: { "pages" => [{ "id" => "p1", "fields" => [
                            { "id" => "f1", "property_slug" => "full_name", "property_type" => "string", "source" => "entity" }
                          ] }] }.to_json, **attrs)
      page.visible_audiences = audiences
      page.save!(validate: false)
      Page.find(page.id)
    end

    around { |example| Current.set(customer: customer) { example.run } }

    it "refuses an audience whose required field isn't on the form" do
      contract = contract_for(form(launched: true))

      expect(contract.validate("visible_audiences" => %w[admin member])).to be(false)
      expect(contract.errors.full_messages).to eq([
        I18n.t("maint_core.errors.page_launch.required_field_missing", field: "Email", audience: I18n.t("common.visibility.member"))
      ])
    end

    it "allows narrowing, and doesn't check an offline form" do
      expect(contract_for(form(launched: true, audiences: %w[admin member])).validate("visible_audiences" => %w[admin])).to be(true)
      expect(contract_for(form(launched: false)).validate("visible_audiences" => %w[admin member public])).to be(true)
    end

    it "refuses adding the public audience when the bound entity is owned" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      learner = create(:entity, customer: customer, name: "Learner", extended_model: person_model,
                       property_schema: [{ "name" => "Name", "name_slug" => "name", "html_type" => "text" }].to_json)
      owned = create(:entity, customer: customer, name: "Homework", display_label: "Homework",
                     property_schema: [
                       { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" },
                       { "name" => "Student", "name_slug" => "student", "html_type" => "select", "owner" => true,
                         "config" => { "options_source" => "entity_entries", "entity_id" => learner.id.to_s,
                                       "label_field" => "name" } }
                     ].to_json)
      page = build(:page, :for_member, customer: customer, entity: owned, launched: true,
                          configuration: { "pages" => [{ "id" => "p1", "fields" => [
                            { "id" => "f1", "property_slug" => "title", "property_type" => "string", "source" => "entity" }
                          ] }] }.to_json)
      page.save!(validate: false)
      contract = contract_for(Page.find(page.id))

      expect(contract.validate("visible_audiences" => %w[admin member public])).to be(false)
      expect(contract.errors.full_messages).to include(
        I18n.t("maint_core.errors.page_launch.owned_entity_public_audience", entity: "Homework")
      )
    end

    def action_form(launched:, audiences: %w[admin], **attrs)
      entity = create(:entity, customer: customer, property_schema: [
        { "name" => "Name", "name_slug" => "full_name", "type" => "String", "html_type" => "text" }
      ].to_json)
      form(launched: launched, audiences: audiences, entity: entity, **attrs)
    end

    it "refuses adding an audience that another live page already handles for the action" do
      page = action_form(launched: true, action_key: "enroll")
      create(:page, :launched, :member_only, customer: customer, entity: page.entity, action_key: "enroll")
      contract = contract_for(page)

      expect(contract.validate("visible_audiences" => %w[admin member], "action_key" => "enroll")).to be(false)
      expect(contract.errors.full_messages).to include(
        message(:action_audience_taken, audience: I18n.t("common.visibility.member"), action: "enroll")
      )
    end

    it "re-checks the collision under the owner lock on save" do
      page = action_form(launched: true, action_key: "enroll")
      rival = create(:page, :member_only, customer: customer, entity: page.entity, action_key: "enroll")
      contract = contract_for(page)
      expect(contract.validate("visible_audiences" => %w[admin member], "action_key" => "enroll")).to be(true)

      rival.update_column(:launched, true)

      expect(contract.save).to be(false)
      expect(contract.errors.full_messages).to include(
        message(:action_audience_taken, audience: I18n.t("common.visibility.member"), action: "enroll")
      )
      expect(Page.find(contract.model.id).visible_audiences).to eq(%w[admin])
    end
  end
end
