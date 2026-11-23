# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::ColumnPickerComponent, type: :component do
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
      { "name" => "Total", "name_slug" => "total", "type" => "Calculated" }
    ]
  end

  let(:setting) { EntityIndexSetting.for(customer_id: customer.id, entity_id: entity.id) }
  let(:update_path) { "/#{customer.id}/admin/entities/#{entity.id}/index_setting" }

  subject(:component) do
    described_class.new(entity: entity, setting: setting, update_path: update_path)
  end

  before { render_inline(component) }

  it "wires the dropdown Stimulus controller and toggle action" do
    aggregate_failures do
      expect(page).to have_css("[data-controller='dropdown']")
      expect(page).to have_css("[data-action='click->dropdown#toggle']")
      expect(page).to have_css("[data-dropdown-target='menu']", visible: :all)
    end
  end

  it "renders the PATCH form to the update path with a hidden empty array field" do
    form = page.find("form[action='#{update_path}']", visible: :all)
    expect(form[:method]).to eq("post")
    expect(page).to have_css(
      "input[type='hidden'][name='entity_index_setting[visible_column_keys][]'][value='']",
      visible: :hidden
    )
    expect(page).to have_css("input[type='hidden'][name='_method'][value='patch']", visible: :hidden)
  end

  it "renders locked system columns as checked and disabled without a submit name" do
    aggregate_failures do
      %w[id created_at updated_at].each do |key|
        checkbox = page.find("input[type='checkbox'][value='#{key}']", visible: :all)
        expect(checkbox[:checked]).to be_truthy
        expect(checkbox[:disabled]).to eq("disabled")
        expect(checkbox[:name]).to be_blank
      end
      # Locked system columns are grouped under a "System" header instead of a
      # per-row "(always shown)" caption.
      expect(page).to have_text(I18n.t("comp_admin.column_picker.system_group"))
    end
  end

  it "groups attribute columns under an Attributes header and shows the selected count" do
    aggregate_failures do
      expect(page).to have_text(I18n.t("comp_admin.column_picker.attributes_group"))
      # 3 system + 3 checked attributes (title/status/score) = 6
      expect(page).to have_text(I18n.t("comp_admin.column_picker.selected_summary", count: 6))
    end
  end

  it "lists entity attribute checkboxes" do
    aggregate_failures do
      expect(page).to have_css("input[type='checkbox'][name='entity_index_setting[visible_column_keys][]'][value='title']", visible: :all)
      expect(page).to have_css("input[type='checkbox'][name='entity_index_setting[visible_column_keys][]'][value='status']", visible: :all)
      expect(page).to have_css("input[type='checkbox'][name='entity_index_setting[visible_column_keys][]'][value='score']", visible: :all)
      expect(page).to have_text("Course Title")
    end
  end

  it "lists a calculated attribute as a choice" do
    expect(page).to have_css(
      "input[type='checkbox'][name='entity_index_setting[visible_column_keys][]'][value='total']",
      visible: :all
    )
  end

  it "checks the ColumnsBuilder default slugs when preference is nil" do
    expect(setting.visible_column_keys).to be_nil
    aggregate_failures do
      expect(page.find("input[value='title']", visible: :all)[:checked]).to be_truthy
      expect(page.find("input[value='status']", visible: :all)[:checked]).to be_truthy
      expect(page.find("input[value='score']", visible: :all)[:checked]).to be_truthy
    end
  end

  context "with an explicit preference" do
    before do
      setting.write_overlay(visible_column_keys: %w[status])
      setting.save!
      render_inline(component)
    end

    it "checks only preferred attribute slugs" do
      aggregate_failures do
        expect(page.find("input[value='status']", visible: :all)[:checked]).to be_truthy
        expect(page.find("input[value='title']", visible: :all)[:checked]).to be_falsey
        expect(page.find("input[value='score']", visible: :all)[:checked]).to be_falsey
      end
    end
  end

  it "renders I18n button, title, and apply labels" do
    aggregate_failures do
      expect(page).to have_button(I18n.t("comp_admin.column_picker.button"))
      expect(page).to have_text(I18n.t("comp_admin.column_picker.title"))
      expect(page).to have_button(I18n.t("comp_admin.column_picker.apply"))
    end
  end
end
