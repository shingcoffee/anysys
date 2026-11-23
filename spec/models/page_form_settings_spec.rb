# frozen_string_literal: true

require "rails_helper"

RSpec.describe Page, "form settings" do
  let(:customer) { create(:customer) }
  let(:student) { create(:entity, customer: customer, name: "Student") }
  let(:bridge) do
    create(:entity, customer: customer, name: "Enrolment", property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "select", "entity_id" => student.id.to_s },
      { "name" => "Title", "name_slug" => "title", "type" => "String", "html_type" => "text" }
    ].to_json)
  end

  around { |example| Current.set(customer: customer) { example.run } }

  def page_with(form_settings)
    build(:page, customer: customer, entity: bridge).tap do |page|
      page.configuration_json = page.configuration_json.merge("form_settings" => form_settings)
    end
  end

  it("accepts a reference field as a locked input") { expect(page_with("inputs" => [{ "field" => "student", "entity_id" => student.id }])).to be_valid }

  it "rejects a locked input that is not a reference field of the page entity" do
    page = page_with("inputs" => [{ "field" => "title", "entity_id" => student.id }])
    expect(page).not_to be_valid
    expect(page.errors[:base].join).to include("title")
  end

  it "rejects a locked input whose entity is not the one the field references" do
    page = page_with("inputs" => [{ "field" => "student", "entity_id" => bridge.id }])
    expect(page).not_to be_valid
    expect(page.errors[:base]).to include(I18n.t("maint_core.errors.validations.page_input_invalid", field: "student"))
  end

  it("accepts any non-empty set of submission modes") { expect(page_with("modes" => %w[update])).to be_valid }
  it("accepts a page without a modes setting") { expect(page_with({})).to be_valid }

  it "rejects empty modes" do
    page = page_with("modes" => [])
    expect(page).not_to be_valid
    expect(page.errors[:base]).to include(I18n.t("maint_core.errors.validations.page_modes_blank"))
  end

  it "rejects an unknown submission mode with its own message" do
    page = page_with("modes" => %w[create delete])
    expect(page).not_to be_valid
    expect(page.errors[:base]).to include(I18n.t("maint_core.errors.validations.page_modes_invalid"))
    expect(page.errors[:base]).not_to include(I18n.t("maint_core.errors.validations.page_modes_blank"))
  end

  it("accepts a success_message") { expect(page_with("success_message" => "Welcome, student!")).to be_valid }

  it "ignores leftover after_submit settings" do
    expect(page_with("after_submit" => "redirect")).to be_valid
    expect(page_with("after_submit" => "page")).to be_valid
    expect(page_with("after_submit" => "page", "next_page" => { "page_id" => 12, "input" => nil })).to be_valid
  end
end
