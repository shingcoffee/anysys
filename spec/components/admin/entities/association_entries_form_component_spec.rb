# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Entities::AssociationEntriesFormComponent, type: :component do
  let(:customer) { create(:customer) }

  include_context "student course association"

  let(:links) { { "student" => student.id.to_s } }

  def row_form(params = nil, entity: bridge_entity)
    Entities::EntryForm.new(entity: entity, customer: customer, params: params, links: links)
  end

  def render_form(forms: [row_form], template_form: row_form, errors: {})
    render_inline(described_class.new(forms: forms, template_form: template_form, url: "/rows", cancel_path: "/back", errors: errors))
  end

  it "renders numbered rows, a blank template under the row token and the row controller wiring" do
    render_form(forms: [row_form, row_form])

    aggregate_failures do
      expect(page).to have_css("form[action='/rows'][data-turbo-frame='_top']")
      expect(page).to have_css("[data-controller='association-rows'][data-association-rows-next-index-value='2']")
      expect(page).to have_css("[data-association-rows-heading-value='#{I18n.t('admin_misc.entities.association_entries.row_heading', number: '{number}')}']")
      expect(page).to have_css("ol > li h3", text: I18n.t("admin_misc.entities.association_entries.row_heading", number: 2))
      expect(page).to have_css("select[name='rows[1][course]'][id='association_row_1_course']")
      expect(page).to have_css("ol button[data-association-rows-target='remove']:not(.hidden)", count: 2)
      expect(page).to have_css("button[data-action='association-rows#add']", text: I18n.t("admin_misc.entities.association_entries.add_row"))
      expect(page).to have_css("a[href='/back']", text: I18n.t("common.actions.cancel"))
      expect(page).to have_css("dialog#entity-quick-add-dialog-0", visible: :all)
      expect(page).not_to have_css("[role='alert']")
    end
    template = rendered_content[%r{<template data-association-rows-target="template">.*</template>}m]
    expect(template).to include('name="rows[__ROW__][course]"', 'id="association_row___ROW___course"')
    expect(template).to match(%r{<h3[^>]*>\s*</h3>})
  end

  it "submits into the dialog frame and closes the dialog on Cancel in frame mode" do
    render_inline(described_class.new(forms: [row_form], template_form: row_form, url: "/rows", cancel_path: nil,
                                      frame: true, quick_add_depth: 2))

    expect(page).to have_css("form[action='/rows']:not([data-turbo-frame])")
    expect(page).to have_css("button[data-action='entity-quick-add-dialog#close']", text: I18n.t("common.actions.cancel"))
    expect(page).not_to have_css("a", text: I18n.t("common.actions.cancel"))
    expect(page).to have_css("[data-entity-quick-add-entity-quick-add-dialog-outlet='#entity-quick-add-dialog-2']")
    expect(page).to have_css("dialog#entity-quick-add-dialog-2", visible: :all)
  end

  it "hides remove on a single row" do
    render_form

    expect(page).to have_css("ol button[data-association-rows-target='remove'].hidden")
  end

  it "summarizes base errors and flags invalid rows with their unplaced errors" do
    invalid = row_form({ "course" => "", "status" => "enrolled" }).add_errors!("base" => ["Linked record missing"], "course" => ["can't be blank"])

    render_form(forms: [invalid], errors: { "base" => ["Too many"] })

    aggregate_failures do
      expect(page).to have_css("[role='alert'] li", text: "Too many")
      expect(page).to have_css("ol > li.border-danger li", text: "Linked record missing")
      expect(page).to have_css("#association_row_0_course_errors", text: "can't be blank")
    end
  end

  it "shows the error summary heading for row errors alone" do
    render_form(forms: [row_form.add_errors!("grade" => ["bad"])])

    expect(page).to have_css("[role='alert'] h2")
    expect(page).not_to have_css("[role='alert'] ul")
  end

  it "explains an unavailable bridge form and disables submit" do
    blocked = create(:entity, customer: customer, category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "number" },
      { "name" => "Weird", "name_slug" => "weird", "html_type" => "color" }
    ].to_json)
    empty = create(:entity, customer: customer, category: :bridge, property_schema: [
      { "name" => "Student", "name_slug" => "student", "type" => "EntityReference", "html_type" => "number" }
    ].to_json)

    render_form(forms: [row_form(entity: blocked)], template_form: row_form(entity: blocked))
    expect(page).to have_css("[role='status']", text: I18n.t("admin_misc.entities.entry_form.unsupported_fields", fields: "Weird"))
    expect(page).to have_css("button[type='submit'][disabled]")
    expect(page).not_to have_css("ol")

    render_form(forms: [row_form(entity: empty)], template_form: row_form(entity: empty))
    expect(page).to have_css("[role='status']", text: I18n.t("admin_misc.entities.entry_form.no_fields"))
    expect(page).not_to have_css("dialog", visible: :all)
  end
end
