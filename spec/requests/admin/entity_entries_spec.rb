# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::EntityEntries", type: :request do
  include_context "as admin"

  let(:property_schema) do
    [
      { "name" => "Name", "name_slug" => "name", "display_label" => "Name", "html_type" => "text", "type" => "String" }
    ]
  end

  let!(:entity) do
    create(
      :entity,
      customer: customer,
      name: "Student",
      property_schema: property_schema.to_json
    )
  end

  let!(:entry) do
    create(
      :entity_entry,
      :with_data,
      customer: customer,
      entity: entity,
      entry_data: { "name" => "Alice" }
    )
  end

  let(:show_path) { admin_entity_path(customer.id, entity) }
  let(:entry_path) { admin_entity_entry_path(customer.id, entity, entry) }
  let(:batch_path) { batch_admin_entity_entries_path(customer.id, entity) }
  let(:guard_path) { entry_path }

  it_behaves_like "an admin-guarded GET"
  it_behaves_like "an admin-guarded request", :delete

  describe "DELETE batch — auth guards" do
    let(:guard_path) { batch_path }

    it_behaves_like "an admin-guarded request", :delete
  end

  describe "GET /:customer_id/admin/entities/:entity_id/entries/:id" do
    it "renders the entry as a full dashboard page, not a drawer frame" do
      get entry_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("<!DOCTYPE html>")
        expect(response.body).not_to include('turbo-frame id="entity-entry-detail"')
        expect(response.body).not_to include('data-controller="slide-over"')
        expect(response.body).to include(
          I18n.t("admin_misc.entities.entry_detail.title", id: entry.id)
        )
        expect(response.body).to include("Alice")
      end
    end

    it "tints the header tile with the entity's palette colour, even when it stores a hex colour" do
      entity.update!(color: "#4F46E5")
      soft = EntityAttributeGroupingHelper::COLOR_CLASS_MAP.fetch(EntityGlyph.color(entity))[:soft]

      get entry_path

      tile = Nokogiri::HTML(response.body).at_css("h1").ancestors("div").map { |node| node.at_css("span[aria-hidden='true']") }.compact.first
      expect(tile["class"].split).to include(*soft.split)
    end

    it "links the breadcrumb back to the entity's entries" do
      get entry_path

      expect(Nokogiri::HTML(response.body).css("a[href='#{show_path}']")).not_to be_empty
    end

    it "reaches a linked person entry's user through the Account card name, without record tabs" do
      person_model = EntityDefinitions::Capabilities::PERSON_MODEL
      enable_module!("authentication", customer).set_extendable_model!(person_model, true)
      member = create(:user, :member, customer: customer, first_name: "Ada", last_name: "Lovelace")
      person = create(:entity, customer: customer, name: "Pupil", extended_model: person_model)
      linked = create(:entity_entry, customer: customer, entity: person, user: member)

      get admin_entity_entry_path(customer.id, person, linked)

      document = Nokogiri::HTML(response.body)
      account = document.at_css("section[aria-labelledby='entry-account-heading']")
      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(document.css("a[data-section-nav-tab]")).to be_empty
        expect(account.css("a").map { |link| [link.text.strip, link["href"]] })
          .to eq([["Ada Lovelace", admin_modules_authentication_user_path(customer.id, member)]])
      end
    end

    it "shows the referenced instructor's name and the calculated value" do
      instructor = create(:entity, customer: customer, name: "Instructor", property_schema: [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
      ].to_json)
      jenny = create(:entity_entry, :with_data, customer: customer, entity: instructor,
                     entry_data: { "name" => "Jenny" })
      course = create(:entity, customer: customer, name: "DisplayCourse", property_schema: [
        { "name" => "Mode", "name_slug" => "mode", "html_type" => "select",
          "config" => { "options" => [{ "label" => "In person", "value" => "in_person" }] } },
        { "name" => "Instructor", "name_slug" => "instructor", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => instructor.id.to_s, "label_field" => "name" } },
        { "name" => "Seats", "name_slug" => "seats", "html_type" => "number" },
        { "name" => "Double seats", "name_slug" => "double_seats", "type" => "Calculated", "html_type" => "number",
          "formula" => "seats * 2" }
      ].to_json)
      course_entry = create(:entity_entry, :with_data, customer: customer, entity: course,
                            entry_data: { "mode" => "in_person", "instructor" => jenny.id.to_s, "seats" => 12 })

      get admin_entity_entry_path(customer.id, course, course_entry)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Jenny")
        expect(response.body).to include("24")
      end
    end

    it "returns 200 for a tenant entry on a shared entity" do
      shared = create(:entity, :shared, name: "SharedPeople",
                      property_schema: property_schema.to_json)
      shared_entry = create(:entity_entry, :with_data, customer: customer, entity: shared,
                            entry_data: { "name" => "Pat" })

      get admin_entity_entry_path(customer.id, shared, shared_entry)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pat")
    end

    it "returns 404 for an entry belonging to another tenant" do
      other_customer = create(:customer)
      other_entity = create(
        :entity,
        customer: other_customer,
        name: "Foreign",
        property_schema: property_schema.to_json
      )
      foreign_entry = create(
        :entity_entry,
        :with_data,
        customer: other_customer,
        entity: other_entity,
        entry_data: { "name" => "Outsider" }
      )

      get admin_entity_entry_path(customer.id, entity, foreign_entry)
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the entry belongs to a different entity in the same tenant" do
      other_entity = create(
        :entity,
        customer: customer,
        name: "Course",
        property_schema: property_schema.to_json
      )
      foreign_entry = create(
        :entity_entry,
        :with_data,
        customer: customer,
        entity: other_entity,
        entry_data: { "name" => "Wrong bucket" }
      )

      get admin_entity_entry_path(customer.id, entity, foreign_entry)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /:customer_id/admin/entities/:entity_id/entries/:id" do
    it "destroys the entry and redirects to the admin entity show page" do
      entry_to_delete = entry

      expect {
        delete admin_entity_entry_path(customer.id, entity, entry_to_delete)
      }.to change(EntityEntry, :count).by(-1)

      aggregate_failures do
        expect(response).to redirect_to(show_path)
        follow_redirect!
        expect(response.body).to include(I18n.t("common.flash.entry_deleted"))
      end
    end

    it "returns 204 for JSON destroy" do
      delete admin_entity_entry_path(customer.id, entity, entry), as: :json
      expect(response).to have_http_status(:no_content)
      expect(EntityEntry.exists?(entry.id)).to eq(false)
    end

    it "does not delete an entry from another tenant" do
      other_customer = create(:customer)
      other_entity = create(:entity, customer: other_customer)
      foreign_entry = create(:entity_entry, customer: other_customer, entity: other_entity)

      expect {
        delete admin_entity_entry_path(customer.id, entity, foreign_entry)
      }.not_to change(EntityEntry, :count)

      expect(response).to have_http_status(:not_found)
      expect(EntityEntry.exists?(foreign_entry.id)).to be(true)
    end
  end

  describe "DELETE /:customer_id/admin/entities/:entity_id/entries/batch" do
    let!(:entry_two) { create(:entity_entry, customer: customer, entity: entity, data: {}.to_json) }
    let!(:other_entity) { create(:entity, customer: customer, name: "Other") }
    let!(:foreign_entry) { create(:entity_entry, customer: customer, entity: other_entity, data: {}.to_json) }

    it "destroys only tenant-scoped entries for the entity and reports the count" do
      expect {
        delete batch_path, params: { ids: [entry.id, entry_two.id, foreign_entry.id, 9_999_999] }
      }.to change(EntityEntry, :count).by(-2)

      aggregate_failures do
        expect(response).to redirect_to(show_path)
        follow_redirect!
        expect(response.body).to include(I18n.t("common.flash.entries_deleted", count: 2))
        expect(EntityEntry.exists?(foreign_entry.id)).to be(true)
      end
    end

    it "does not delete entries when ids belong to another tenant" do
      other_customer = create(:customer)
      other_entity = create(:entity, customer: other_customer)
      foreign_entry = create(:entity_entry, customer: other_customer, entity: other_entity)

      expect {
        delete batch_path, params: { ids: [foreign_entry.id] }
      }.not_to change(EntityEntry, :count)

      expect(EntityEntry.exists?(foreign_entry.id)).to be(true)
    end
  end
end
