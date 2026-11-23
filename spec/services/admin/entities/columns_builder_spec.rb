# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::ColumnsBuilder do
  let_it_be(:customer) { create(:customer) }

  let(:entity) do
    e = Entity.new(
      customer_id: customer.id,
      name: "Course",
      description: "Courses"
    )
    e.property_schema_json = property_schema
    e.save!
    e
  end

  let(:property_schema) do
    [
      { "name" => "Title", "name_slug" => "title", "type" => "String", "display_label" => "Course Title" },
      { "name" => "Status", "name_slug" => "status", "type" => "String" },
      { "name" => "Score", "name_slug" => "score", "type" => "Float" },
      { "name" => "Notes", "name_slug" => "notes", "type" => "Text" },
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
    ]
  end

  let(:setting) { EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id) }
  let(:t) { ->(key) { "T:#{key}" } }
  let(:display) do
    Entities::EntryDisplay.new(
      entity: entity,
      entries: [],
      customer_id: entity.customer_id,
      audience: EntityAttributeAudience::ADMIN
    )
  end

  subject(:columns) do
    described_class.call(
      entity: entity,
      setting: setting,
      customer_id: entity.customer_id,
      display: display,
      t: t
    )
  end

  def keys
    columns.map { |c| c[:key] }
  end

  describe "extended model columns" do
    it "is absent for an entity that does not extend a model" do
      expect(keys).to eq(%i[id title status score notes created_at updated_at])
    end

    context "with a person entity" do
      let(:user) { create(:user, customer: customer, first_name: "Ada", last_name: "Lovelace", email: "ada@example.com") }

      before do
        module_record = enable_module!("authentication", customer, name: "Authentication")
        module_record.set_extendable_model!(EntityDefinitions::Capabilities::PERSON_MODEL, true)
        %w[first_name last_name email].each do |name|
          module_record.set_extendable_attribute!(
            EntityDefinitions::Capabilities::PERSON_MODEL, name, true, candidates: Authentication::User.column_names
          )
        end
        entity.update!(extended_model: EntityDefinitions::Capabilities::PERSON_MODEL)
      end

      it "leads with the user's full name and email right after the id, without the link id" do
        expect(keys).to eq(%i[id user_full_name user_email title status score notes created_at updated_at])
        expect(keys).not_to include(:user_first_name, :user_last_name, :linked_account, :user_id)
        expect(columns.map { |col| col[:label] }).not_to include("user_id")
        expect(columns.find { |col| col[:key] == :user_full_name }[:label])
          .to eq("T:admin_misc.entities.columns.user_full_name")
      end

      it "reads the name and email from the linked user and links the name to the user's page" do
        linked = EntityEntry.create!(customer_id: customer.id, entity: entity, user: user)
        unlinked = EntityEntry.create!(customer_id: customer.id, entity: entity)
        full_name = columns.find { |col| col[:key] == :user_full_name }
        email = columns.find { |col| col[:key] == :user_email }

        expect(full_name[:cell].call(linked)).to eq("Ada Lovelace")
        expect(full_name[:cell].call(unlinked)).to eq("T:common.labels.em_dash")
        expect(full_name[:href].call(linked))
          .to eq(Rails.application.routes.url_helpers.admin_modules_authentication_user_path(customer.id, user))
        expect(full_name[:href].call(unlinked)).to be_nil
        expect(email[:cell].call(linked)).to eq("ada@example.com")
        expect(email[:cell].call(unlinked)).to eq("T:common.labels.em_dash")
      end

      it "keeps the name and email columns when no user attribute is selected" do
        %w[first_name last_name email].each do |name|
          FeatureModules::Module.find_by!(key: "authentication").set_extendable_attribute!(
            EntityDefinitions::Capabilities::PERSON_MODEL, name, false, candidates: Authentication::User.column_names
          )
        end

        expect(keys.first(3)).to eq(%i[id user_full_name user_email])
      end

      it "keeps other selected user attributes before the timestamps" do
        FeatureModules::Module.find_by!(key: "authentication").set_extendable_attribute!(
          EntityDefinitions::Capabilities::PERSON_MODEL, "locale", true, candidates: Authentication::User.column_names
        )

        expect(keys.last(3)).to eq(%i[user_locale created_at updated_at])
      end

      it "sorts and searches by the user's full name and email within the entry's tenant" do
        linked = EntityEntry.create!(customer_id: customer.id, entity: entity, user: user)
        full_name_column = columns.find { |col| col[:key] == :user_full_name }
        email_column = columns.find { |col| col[:key] == :user_email }

        expect(full_name_column).to include(sortable: true, searchable: true)
        expect(email_column).to include(sortable: true, searchable: true)
        expect(EntityEntry.where(id: linked.id).pick(Arel.sql(full_name_column[:sql]))).to eq("Ada Lovelace")
        expect(EntityEntry.where(id: linked.id).pick(Arel.sql(email_column[:sql]))).to eq("ada@example.com")
      end
    end
  end

  describe "system columns" do
    it "places id first and timestamps last" do
      expect(keys.first).to eq(:id)
      expect(keys.last(2)).to eq(%i[created_at updated_at])
    end

    it "labels system columns via t and marks them sortable" do
      id_col = columns.find { |c| c[:key] == :id }
      expect(id_col).to include(
        label: "T:admin_misc.entities.columns.id",
        sortable: true,
        type: :number,
        align: :right
      )
      expect(id_col).not_to have_key(:searchable)

      created_at_col = columns.find { |c| c[:key] == :created_at }
      expect(created_at_col).to include(type: :datetime, relative: true, sortable: true)
    end
  end

  describe "defaults when preference is nil" do
    it "shows every stored field when no column preference is saved" do
      expect(setting.visible_column_keys).to be_nil
      expect(keys).to eq(%i[id title status score notes created_at updated_at])
    end

    it "includes stored fields that are not searchable" do
      entity.property_schema_json = [
        { "key" => "title", "name_slug" => "title", "type" => "string", "name" => "Title" },
        { "key" => "status", "name_slug" => "status", "type" => "string", "name" => "Status" },
        { "key" => "score", "name_slug" => "score", "type" => "number", "name" => "Score" }
      ]
      entity.save!

      expect(entity.searchable_field_keys).to include("title", "status")
      expect(entity.searchable_field_keys).not_to include("score")
      expect(keys).to eq(%i[id title status score created_at updated_at])
    end
  end

  describe "explicit preference" do
    it "preserves preference order and ignores stale keys" do
      setting.write_overlay(visible_column_keys: %w[score missing title])
      setting.save!

      expect(keys).to eq(%i[id score title created_at updated_at])
    end

    it "hides all attribute columns when preference is []" do
      setting.write_overlay(visible_column_keys: [])
      setting.save!

      expect(keys).to eq(%i[id created_at updated_at])
    end
  end

  describe "candidates" do
    it "excludes Calculated fields" do
      expect(keys).not_to include(:total)
    end

    it "excludes fields with blank name_slug" do
      entity.property_schema_json = [
        { "name" => "Orphan", "name_slug" => "", "type" => "String" },
        { "name" => "Title", "name_slug" => "title", "type" => "String" }
      ]
      # Blank slugs are now rejected by validate_attribute_slug_format; persist
      # past that so this example still covers ColumnsBuilder's candidate filter.
      entity.save(validate: false)

      expect(keys).to eq(%i[id title created_at updated_at])
    end

    it "excludes system column slugs from candidates" do
      entity.property_schema_json = [
        { "name" => "Id", "name_slug" => "id", "type" => "String" },
        { "name" => "Title", "name_slug" => "title", "type" => "String" }
      ]
      entity.save!

      expect(keys).to eq(%i[id title created_at updated_at])
      expect(keys.count(:id)).to eq(1)
    end

    it "uses each entity's own input_fields as candidates" do
      other = Entity.new(customer_id: customer.id, name: "Other")
      other.property_schema_json = [
        { "name" => "Amount", "name_slug" => "amount", "type" => "Float" }
      ]
      other.save!
      other_setting = EntityIndexSetting.for(customer_id: customer.id, entity_id: other.id)

      other_display = Entities::EntryDisplay.new(
        entity: other,
        entries: [],
        customer_id: other.customer_id,
        audience: EntityAttributeAudience::ADMIN
      )
      other_keys = described_class.call(
        entity: other,
        setting: other_setting,
        customer_id: other.customer_id,
        display: other_display,
        t: t
      ).map { |c| c[:key] }
      expect(other_keys).to eq(%i[id amount created_at updated_at])
      expect(keys).to include(:title)
      expect(keys).not_to include(:amount)
    end
  end

  describe "attribute column metadata" do
    it "marks attribute columns sortable/searchable with sql: expressions" do
      title = columns.find { |c| c[:key] == :title }
      expect(title).to include(sortable: true, searchable: true, type: :text)
      expect(title[:sql]).to eq("json_extract(entity_entries.data, '$.title')")
    end

    it "maps html_type to column type" do
      entity.property_schema_json = [
        { "name_slug" => "age", "name" => "age", "html_type" => "number", "type" => "Integer" },
        { "name_slug" => "grade", "name" => "grade", "html_type" => "select", "type" => "String",
          "config" => { "options" => [{ "label" => "A", "value" => "A" }] } },
        { "name_slug" => "active", "name" => "active", "html_type" => "checkbox", "type" => "Boolean" },
        { "name_slug" => "bio", "name" => "bio", "html_type" => "textarea", "type" => "Text" }
      ]
      entity.save!
      setting.write_overlay(visible_column_keys: %w[age grade active bio])
      setting.save!
      cols = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      )
      expect(cols.find { |c| c[:key] == :age }).to include(type: :number, align: :right)
      expect(cols.find { |c| c[:key] == :grade }[:type]).to eq(:badge)
      expect(cols.find { |c| c[:key] == :active }[:type]).to eq(:text)
      expect(cols.find { |c| c[:key] == :bio }[:type]).to eq(:truncate)
    end

    it "keeps authored display_label as-is (does not humanize acronyms or casing)" do
      entity.property_schema_json = [
        { "name_slug" => "first_name", "name" => "first name", "display_label" => "first name",
          "html_type" => "text", "type" => "String" }
      ]
      entity.save!
      col = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      ).find { |c| c[:key] == :first_name }
      expect(col[:label]).to eq("first name")
    end

    context "with a choice and a text field" do
      before do
        entity.property_schema_json = [
          { "name_slug" => "grade", "name" => "Grade", "html_type" => "select", "type" => "String",
            "config" => { "options" => [{ "label" => "Grade A", "value" => "A" }] } },
          { "name_slug" => "first_name", "name" => "First name", "html_type" => "text", "type" => "String" }
        ]
        entity.save!
        setting.write_overlay(visible_column_keys: %w[grade first_name])
        setting.save!
      end

      it "reads attribute cells and badge labels from the display" do
        display = instance_double(Entities::EntryDisplay)
        row = instance_double(EntityEntry)
        allow(display).to receive(:text).with(row, "grade").and_return("Grade A")
        allow(display).to receive(:text).with(row, "first_name").and_return(I18n.t("common.labels.em_dash"))
        cols = described_class.call(entity: entity, setting: setting, customer_id: entity.customer_id, display: display, t: t)

        grade = cols.find { |c| c[:key] == :grade }
        expect(grade[:badge].call(row)).to eq(label: "Grade A", variant: :default)
        first_name = cols.find { |c| c[:key] == :first_name }
        expect(first_name[:cell].call(row)).to eq(I18n.t("common.labels.em_dash"))
      end

      it "has no badge for a blank choice" do
        display = instance_double(Entities::EntryDisplay, text: I18n.t("common.labels.em_dash"))
        grade = described_class.call(entity: entity, setting: setting, customer_id: entity.customer_id, display: display, t: t)
                               .find { |c| c[:key] == :grade }
        expect(grade[:badge].call(instance_double(EntityEntry))).to be_nil
      end
    end

    it "prefers display_label, then name, then the raw slug" do
      expect(columns.find { |c| c[:key] == :title }[:label]).to eq("Course Title")
      expect(columns.find { |c| c[:key] == :status }[:label]).to eq("Status")

      entity.property_schema_json = [
        { "name_slug" => "raw_slug", "type" => "String" }
      ]
      entity.save!
      col = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      ).find { |c| c[:key] == :raw_slug }
      expect(col[:label]).to eq("raw_slug")
    end
  end

  describe "computed columns" do
    let!(:peer) { create(:entity, name: "Peer", customer: customer) }
    let!(:bridge) do
      create(:entity, name: "assoc_course_peer", customer: customer, category: :bridge,
        property_schema: [
          { "name" => "Course", "name_slug" => "course", "type" => "EntityReference", "entity_id" => entity.id.to_s },
          { "name" => "Peer", "name_slug" => "peer", "type" => "EntityReference", "entity_id" => peer.id.to_s },
          { "name" => "Score", "name_slug" => "score", "type" => "Float", "html_type" => "number" }
        ].to_json)
    end

    before do
      entity.property_schema_json = property_schema + [
        { "name" => "Average Score", "display_label" => "Average Score", "name_slug" => "average_score",
          "type" => "Computed", "html_type" => "number", "readonly" => true, "storage" => "computed",
          "config" => {
            "bridge_entity_id" => bridge.id,
            "bridge_role" => "source",
            "source_slug" => "score",
            "function" => "avg",
            "precision" => 2
          } }
      ]
      entity.save(validate: false)
      entity.reload
      setting.write_overlay(visible_column_keys: %w[average_score])
      setting.save!
    end

    it "builds a number column that is sortable and not searchable" do
      col = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      ).find { |c| c[:key] == :average_score }
      expect(col).to include(
        type: :number,
        align: :right,
        sortable: true,
        searchable: false,
        derived: true
      )
      expect(col[:sql]).to include("SELECT")
    end

    it "reads the cell from the display" do
      display = instance_double(Entities::EntryDisplay)
      row = instance_double(EntityEntry)
      allow(display).to receive(:text).with(row, "average_score").and_return("87.5")
      col = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      ).find { |c| c[:key] == :average_score }
      expect(col[:cell].call(row)).to eq("87.5")
    end
  end

  describe "calculated columns" do
    before do
      entity.property_schema_json = [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number", "formula" => "price * 2" }
      ]
      entity.save!
    end

    it "builds a derived number column when preferred, with formula SQL" do
      setting.write_overlay(visible_column_keys: %w[total])
      setting.save!
      col = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      ).find { |c| c[:key] == :total }
      expect(col).to include(key: :total, type: :number, sortable: true, searchable: false, derived: true)
      expect(col[:sql]).to include("json_extract(entity_entries.data, '$.price')")
    end

    it "does not include a calculated field as a default column" do
      expect(setting.visible_column_keys).to be_nil
      expect(
        described_class.call(
          entity: entity,
          setting: setting,
          customer_id: entity.customer_id,
          display: display,
          t: t
        ).map { |c| c[:key] }
      ).not_to include(:total)
    end

    it "does not select a calculated field with a broken formula, even when preferred" do
      entity.property_schema_json = [
        { "name" => "Price", "name_slug" => "price", "type" => "Float", "html_type" => "number" },
        { "name" => "Total", "name_slug" => "total", "type" => "Calculated", "html_type" => "number", "formula" => "price +" }
      ]
      entity.save!
      setting.write_overlay(visible_column_keys: %w[total])
      setting.save!
      keys = described_class.call(
        entity: entity,
        setting: setting,
        customer_id: entity.customer_id,
        display: display,
        t: t
      ).map { |c| c[:key] }
      expect(keys).not_to include(:total)
    end
  end
end
