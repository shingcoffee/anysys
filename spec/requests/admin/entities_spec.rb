# frozen_string_literal: true

require "rails_helper"
require "csv"

RSpec.describe "Admin::Entities", type: :request do
  include_context "as admin"

  let(:property_schema) do
    [
      {
        "name" => "Name", "name_slug" => "name", "display_label" => "Name",
        "html_type" => "text", "type" => "String"
      },
      {
        "name" => "Grade", "name_slug" => "grade", "display_label" => "Grade",
        "html_type" => "select", "type" => "String",
        "config" => {
          "options" => [
            { "label" => "A", "value" => "A" },
            { "label" => "B", "value" => "B" }
          ]
        }
      }
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

  let(:show_path) { admin_entity_path(customer.id, entity) }
  let(:guard_path) { show_path }

  it_behaves_like "an admin-guarded GET"

  describe "GET csv — auth guards" do
    let(:guard_path) { "#{show_path}.csv" }

    it_behaves_like "an admin-guarded GET"
  end

  def create_entry(**attrs)
    data = attrs.fetch(:data, {})
    entry = create(
      :entity_entry,
      :with_data,
      customer: customer,
      entity: entity,
      entry_data: data
    )
    if attrs[:created_at]
      entry.update_column(:created_at, attrs[:created_at])
      entry.reload
    end
    entry
  end

  def entry_ids_in_table(body)
    body.scan(/name="ids\[\]"\s+value="(\d+)"/).flatten.map(&:to_i)
  end

  def id_positions(body, *ids)
    ordered = entry_ids_in_table(body)
    ids.map { |id| ordered.index(id) }
  end

  describe "GET /:customer_id/admin/entities/:id" do
    let!(:alpha) { create_entry(data: { "name" => "Alpha", "grade" => "A" }, created_at: 2.days.ago) }
    let!(:beta)  { create_entry(data: { "name" => "Beta", "grade" => "B" }, created_at: 1.day.ago) }

    it "returns 200 with export, column picker, and entries table markers but no detail drawer frame" do
      get show_path

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("admin_misc.entities.show.export_csv"))
        expect(response.body).to include(I18n.t("comp_admin.column_picker.button"))
        expect(response.body).not_to include('turbo-frame id="entity-entry-detail"')
        expect(response.body).to include('turbo-frame id="entity-entries-table"')
        expect(response.body).to include(entity.display_label)
      end
    end

    it "does not English-humanize an unlabeled attribute slug" do
      unlabeled = create(
        :entity,
        customer: customer,
        name: "Unlabeled",
        property_schema: [ { "name_slug" => "raw_slug", "type" => "String", "html_type" => "text" } ].to_json
      )

      get admin_entity_path(customer.id, unlabeled)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("raw_slug")
      expect(response.body).not_to include("Raw slug")
    end

    it "renders tenant entries on a shared entity and hides another tenant's" do
      shared = create(:entity, :shared, name: "SharedPeople",
                      display_label: "Shared People", property_schema: property_schema.to_json)
      create(:entity_entry, :with_data, customer: customer, entity: shared,
             entry_data: { "name" => "Pat Shared", "grade" => "A" })
      other = create(:customer)
      create(:entity_entry, :with_data, customer: other, entity: shared,
             entry_data: { "name" => "SecretForeignDataXYZ", "grade" => "B" })

      get admin_entity_path(customer.id, shared)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pat Shared")
      expect(response.body).not_to include("SecretForeignDataXYZ")
    end

    it "orders entries by created_at desc by default" do
      get show_path

      expect(entry_ids_in_table(response.body)).to eq([beta.id, alpha.id])
    end

    context "with search q against a JSON text attribute" do
      it "returns only matching entries" do
        get show_path, params: { q: "alpha" }

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(entry_ids_in_table(response.body)).to eq([alpha.id])
        end
      end

      it "does not 500 when q is an array" do
        get show_path, params: { q: ["alpha"] }

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(entry_ids_in_table(response.body)).to eq([alpha.id])
        end
      end
    end

    context "with sort and dir against a JSON attribute" do
      it "orders rows by the requested column" do
        get show_path, params: { sort: "name", dir: "asc" }

        expect(entry_ids_in_table(response.body)).to eq([alpha.id, beta.id])
      end
    end

    context "with a FiltersBuilder select filter" do
      it "scopes rows to the selected option" do
        get show_path, params: { grade: "A" }

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(entry_ids_in_table(response.body)).to eq([alpha.id])
        end
      end
    end

    context "when the entity belongs to another tenant" do
      let(:other_customer) { create(:customer) }
      let(:foreign_entity) { create(:entity, customer: other_customer, name: "Foreign") }

      it "returns 404" do
        get admin_entity_path(customer.id, foreign_entity)
        expect(response).to have_http_status(:not_found)
      end
    end

    it "does not honor or persist an unbounded per_page query param" do
      12.times { |i| create_entry(data: { "name" => "Extra #{i}" }) }

      get show_path, params: { per_page: 999_999 }

      expect(response).to have_http_status(:ok)
      expect(entry_ids_in_table(response.body).size).to eq(Listable::DEFAULT_PER_PAGE)
      setting = EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id)
      expect(setting.per_page).to be_nil
    end
  end

  describe "GET person entity entries — Linked account" do
    let(:person_model) { EntityDefinitions::Capabilities::PERSON_MODEL }
    let!(:person) do
      module_record = enable_module!("authentication", customer)
      module_record.set_extendable_model!(person_model, true)
      %w[first_name last_name email].each do |name|
        module_record.set_extendable_attribute!(person_model, name, true, candidates: Authentication::User.column_names)
      end
      create(:entity, customer: customer, name: "PersonRoster", extended_model: person_model,
             property_schema: property_schema.to_json)
    end
    let(:person_path) { admin_entity_path(customer.id, person) }
    let(:ada) { create(:user, :member, customer: customer, first_name: "Ada", last_name: "Lovelace", email: "ada.link@example.com") }
    let(:grace) { create(:user, :member, customer: customer, first_name: "Grace", last_name: "Hopper", email: "grace.link@example.com") }
    let!(:linked) { create(:entity_entry, :with_data, customer: customer, entity: person, user: ada, entry_data: { "name" => "Ada row" }) }
    let!(:other_linked) { create(:entity_entry, :with_data, customer: customer, entity: person, user: grace, entry_data: { "name" => "Grace row" }) }
    let!(:unlinked) { create(:entity_entry, :with_data, customer: customer, entity: person, entry_data: { "name" => "Solo row" }) }

    it "renders the linked user's full name and email right after the ID, without the link id column" do
      get person_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(I18n.t("admin_misc.entities.columns.user_id"))
      expect(response.body).not_to include(I18n.t("admin_misc.entities.columns.user_link_id", id: ada.id))
      headers = Capybara.string(response.body).all("table thead th").map { |th| th.text.strip }
      expect(headers[1, 3]).to eq([I18n.t("admin_misc.entities.columns.id"),
                                   I18n.t("admin_misc.entities.columns.user_full_name"),
                                   I18n.t("common.labels.email")])
      expect(headers).not_to include(I18n.t("common.labels.first_name"), I18n.t("common.labels.last_name"))
      expect(response.body).to include("Ada Lovelace", ada.email, "Grace Hopper", grace.email)
      expect(entry_ids_in_table(response.body)).to include(linked.id, other_linked.id, unlinked.id)
    end

    it "links the full name to the user's detail page" do
      get person_path

      table = Capybara.string(response.body).find("table")
      expect(table).to have_link("Ada Lovelace", href: admin_modules_authentication_user_path(customer.id, ada))
      expect(table).to have_link("Grace Hopper", href: admin_modules_authentication_user_path(customer.id, grace))
    end

    it "sorts by the linked user's full name" do
      get person_path, params: { sort: "user_full_name", dir: "asc" }
      expect(response).to have_http_status(:ok)
      expect(entry_ids_in_table(response.body) & [linked.id, other_linked.id]).to eq([linked.id, other_linked.id])

      get person_path, params: { sort: "user_full_name", dir: "desc" }
      expect(entry_ids_in_table(response.body) & [linked.id, other_linked.id]).to eq([other_linked.id, linked.id])
    end

    it "filters rows when searching by the linked user's email" do
      get person_path, params: { q: "ada.link@example.com" }

      expect(response).to have_http_status(:ok)
      expect(entry_ids_in_table(response.body)).to eq([linked.id])
    end

    it "preloads linked users so extra rows do not add user lookups" do
      get person_path
      expect(response).to have_http_status(:ok)
      small = count_queries { get person_path }

      5.times do |n|
        extra = create(:user, :member, customer: customer, first_name: "Extra", last_name: "User#{n}",
                       email: "extra.link.#{n}@example.com")
        create(:entity_entry, :with_data, customer: customer, entity: person, user: extra,
               entry_data: { "name" => "Extra #{n}" })
      end

      grown = count_queries { get person_path }
      expect(response).to have_http_status(:ok)
      expect(grown).to be <= small + 1
    end
  end

  describe "GET /:customer_id/admin/entities/:id.csv" do
    let!(:alpha) { create_entry(data: { "name" => "Alpha", "grade" => "A" }) }
    let!(:beta)  { create_entry(data: { "name" => "Beta", "grade" => "B" }) }

    before do
      EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id).tap do |setting|
        setting.write_overlay(visible_column_keys: %i[name])
        setting.save!
      end
    end

    it "returns CSV with the expected content type and filename pattern" do
      get show_path, params: { format: :csv }

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/csv")
        expect(response.headers["Content-Disposition"]).to match(
          /attachment; filename="student-entries-\d{8}\.csv"/
        )
      end
    end

    it "exports filtered rows and visible attribute columns" do
      get show_path, params: { format: :csv, grade: "A" }

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Name")
        expect(response.body).to include("Alpha")
        expect(response.body).not_to include("Beta")
        expect(response.body).not_to include("Grade")
      end
    end
  end

  describe "display" do
    let!(:instructor) do
      create(:entity, customer: customer, name: "Instructor", property_schema: [
        { "name" => "Name", "name_slug" => "name", "html_type" => "text" }
      ].to_json)
    end
    let!(:jenny) do
      create(:entity_entry, :with_data, customer: customer, entity: instructor, entry_data: { "name" => "Jenny" })
    end
    let!(:course) do
      create(:entity, customer: customer, name: "Course", property_schema: [
        { "name" => "Mode", "name_slug" => "mode", "html_type" => "select",
          "config" => { "options" => [{ "label" => "In person", "value" => "in_person" }] } },
        { "name" => "Instructor", "name_slug" => "instructor", "html_type" => "select",
          "config" => { "options_source" => "entity_entries", "entity_id" => instructor.id.to_s, "label_field" => "name" } },
        { "name" => "Seats", "name_slug" => "seats", "html_type" => "number" },
        { "name" => "Double seats", "name_slug" => "double_seats", "type" => "Calculated", "html_type" => "number",
          "formula" => "seats * 2" }
      ].to_json)
    end

    def prefer_display_columns!(entity = course, keys = %w[mode instructor seats double_seats])
      EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id).tap do |setting|
        setting.write_overlay(visible_column_keys: keys)
        setting.save!
      end
    end

    def table_cell_texts(body)
      Capybara.string(body).all("table tbody td").map { |td| td.text.strip }
    end

    it "shows option labels, referenced names and calculated values on the list" do
      prefer_display_columns!
      create(:entity_entry, :with_data, customer: customer, entity: course,
             entry_data: { "mode" => "in_person", "instructor" => jenny.id.to_s, "seats" => 12 })

      get admin_entity_path(customer.id, course)

      expect(response).to have_http_status(:ok)
      cells = table_cell_texts(response.body)
      expect(cells).to include("In person", "Jenny", "24")
      expect(cells).not_to include(jenny.id.to_s)
    end

    it "exports display text in the CSV under the column headings" do
      prefer_display_columns!
      create(:entity_entry, :with_data, customer: customer, entity: course,
             entry_data: { "mode" => "in_person", "instructor" => jenny.id.to_s, "seats" => 12 })

      get admin_entity_path(customer.id, course, format: :csv)

      expect(response).to have_http_status(:ok)
      parsed = CSV.parse(response.body)
      headers = parsed.first
      row = parsed.drop(1).first
      expect(row[headers.index("Mode")]).to eq("In person")
      expect(row[headers.index("Instructor")]).to eq("Jenny")
      expect(row[headers.index("Double seats")]).to eq("24")
      expect(row).not_to include(jenny.id.to_s)
    end

    it "sorts by a calculated column" do
      prefer_display_columns!
      fewer = create(:entity_entry, :with_data, customer: customer, entity: course,
                     entry_data: { "mode" => "in_person", "instructor" => jenny.id.to_s, "seats" => 5 })
      more = create(:entity_entry, :with_data, customer: customer, entity: course,
                    entry_data: { "mode" => "in_person", "instructor" => jenny.id.to_s, "seats" => 12 })

      get admin_entity_path(customer.id, course), params: { sort: "double_seats", dir: "desc" }

      expect(entry_ids_in_table(response.body)).to eq([more.id, fewer.id])
    end

    it "counts a bridge row whose parent id is a JSON number" do
      student = create(:entity, name: "CountStudent", customer: customer)
      klass = create(:entity, name: "CountClass", customer: customer)
      bridge = create(:entity, name: "assoc_count_student_count_class", customer: customer, category: :bridge,
        property_schema: [
          { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "entity_id" => student.id.to_s },
          { "name" => "Class", "name_slug" => "class", "type" => "EntityReference", "entity_id" => klass.id.to_s },
          { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
        ].to_json)
      student.property_schema_json = [
        { "name" => "Enrolments", "name_slug" => "enrolments", "type" => "Computed",
          "config" => { "bridge_entity_id" => bridge.id, "bridge_role" => "source", "source_slug" => "",
                        "function" => "count", "precision" => 2 } }
      ]
      student.save(validate: false)

      pupil = create(:entity_entry, entity: student, customer: customer, data: {}.to_json)
      math = create(:entity_entry, entity: klass, customer: customer, data: {}.to_json)
      create(:entity_entry, entity: bridge, customer: customer,
             data: { "student" => pupil.id, "class" => math.id.to_s, "score" => "70" }.to_json)

      prefer_display_columns!(student, %w[enrolments])

      get admin_entity_path(customer.id, student)

      expect(response).to have_http_status(:ok)
      table = Capybara.string(response.body).find("table")
      headers = table.all("thead th").map { |th| th.text.strip }
      idx = headers.index("Enrolments")
      expect(idx).to be_present
      expect(table.all("tbody tr:first-child td")[idx].text.strip).to eq("1")
    end
  end
end
