# frozen_string_literal: true

require "rails_helper"

RSpec.describe Entities::InfoCardComponent, type: :component do
  let(:customer) { create(:customer) }
  let(:entity) do
    create(:entity,
           customer:    customer,
           name:        "Test Entity",
           icon:        "folder",
           color:       "indigo",
           description: "A test entity")
  end

  def render_component(ent = entity)
    with_request_url("/#{customer.id}/admin/maintenance/entities/#{ent.id}", host: "www.example.com") do
      render_inline(described_class.new(entity: ent, customer_id: customer.id))
    end
  end

  describe "standard entity" do
    before { render_component }

    it "renders the Entity Information heading" do
      expect(page).to have_text("Entity Information")
    end

    it "renders the entity name" do
      expect(page).to have_text("Test Entity")
    end

    it "renders the Standard kind badge" do
      expect(page).to have_css(".badge", text: "Standard")
    end

    it "does not render the Bridge badge" do
      expect(page).not_to have_css(".badge", text: "Bridge")
    end

    it "does not render the name slug" do
      expect(page).not_to have_css("dt", text: "Name Slug")
    end

    it "renders the Standard kind badge" do
      expect(page).to have_css(".badge", text: "Standard")
    end

    it "renders the description" do
      expect(page).to have_text("A test entity")
    end

    it "omits the base model when the entity extends nothing" do
      expect(page).not_to have_css("dt", text: "Extends")
      expect(page).not_to have_css("[data-role='base-model']")
    end

    it "renders the Referenced Template label" do
      expect(page).to have_css("dt", text: "Referenced Template")
    end

    it "renders 'None' when referenced_template is blank" do
      expect(page).to have_css("dd", text: "None")
    end

    it "renders the Created timestamp label" do
      expect(page).to have_css("dt", text: "Created")
    end

    it "renders the Last Updated timestamp label" do
      expect(page).to have_css("dt", text: "Last Updated")
    end

    it "renders actual timestamp values" do
      expect(page).to have_text(I18n.l(entity.created_at, format: :long))
    end
  end

  describe "entity that extends a base model" do
    let(:student) do
      enable_module!("authentication", customer)
        .set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
      create(:entity, customer: customer, name: "Student",
                      extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
    end

    before { render_component(student) }

    it "names the base model and the module that provides it" do
      expect(page).to have_css("dt", text: "Extends")
      expect(page).to have_css("[data-role='base-model']", text: "User")
      expect(page).to have_css("[data-role='base-model']", text: "(authentication)")
    end
  end

  describe "bridge entity" do
    let(:bridge_entity) do
      create(:entity, customer: customer, name: "Bridge Ent", category: :bridge)
    end

    before { render_component(bridge_entity) }

    it "renders the Bridge kind badge" do
      expect(page).to have_css(".badge", text: "Bridge")
    end

    it "does not render the Standard badge" do
      expect(page).not_to have_css(".badge", text: "Standard")
    end
  end

  describe "with a referenced_template containing valid JSON" do
    let(:entity_with_template) do
      create(:entity,
             customer:            customer,
             name:                "Templated Entity",
             referenced_template: { name: "My Template", description: "A cool template" }.to_json)
    end

    before { render_component(entity_with_template) }

    it "renders a link with the template name" do
      expect(page).to have_link("My Template")
    end

    it "renders the template description caption" do
      expect(page).to have_text("A cool template")
    end

    it "opens the link in a new tab (target=_blank)" do
      link = page.find("a", text: "My Template")
      expect(link["target"]).to eq("_blank")
    end
  end

  describe "with referenced_template that is not parseable JSON" do
    let(:entity_bad_template) do
      create(:entity,
             customer:            customer,
             name:                "Bad Template Entity",
             referenced_template: "not valid json content")
    end

    before { render_component(entity_bad_template) }

    it "renders the raw value truncated" do
      expect(page).to have_text("not valid json")
    end

    it "does not render a template name link" do
      expect(page).not_to have_link("My Template")
    end
  end

  describe "entity with blank description" do
    let(:entity_no_desc) do
      create(:entity, customer: customer, name: "No Desc", description: nil)
    end

    before { render_component(entity_no_desc) }

    it "omits the description row when description is absent" do
      expect(page).not_to have_css("dt", text: "Description")
    end
  end

  describe "accessibility attributes" do
    before { render_component }

    it "uses a dl/dt/dd definition list for metadata" do
      expect(page).to have_css("dl")
      expect(page).to have_css("dt")
      expect(page).to have_css("dd")
    end
  end
end
