# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/entity_entries/edit.html.erb", type: :view do
  let(:customer) { double("Customer", id: 12345678) }
  let(:entity) { double("Entity", to_param: "7", display_label: "课程") }
  let(:entry) { double("EntityEntry", id: 9, to_param: "9") }

  before do
    assign(:entity, entity)
    assign(:entry, entry)
    without_partial_double_verification { allow(view).to receive(:current_customer).and_return(customer) }
  end

  %i[en zh-CN].each do |locale|
    it "mounts the edit breadcrumbs around the entity's rendered page in #{locale}" do
      assign(:content, %(<form action="/12345678/page/abc?entry_id=9"></form>))

      I18n.with_locale(locale) { render }

      expect(rendered).to have_css("h1", text: I18n.t("admin_misc.entities.entry_form.edit_title", locale: locale, name: "课程", id: 9))
      expect(rendered).to have_text(I18n.t("admin_misc.entities.entry_form.edit_breadcrumb", locale: locale, id: 9))
      expect(rendered).to have_link("课程", href: "/12345678/admin/entities/7")
      expect(rendered).to have_css(".card > div > div.max-w-4xl form[action='/12345678/page/abc?entry_id=9']")
      expect(rendered).to have_css("dialog#entity-quick-add-dialog-0")
    end

    it "explains that the entity has no launched entry form in #{locale}" do
      assign(:content, nil)

      I18n.with_locale(locale) { render }

      expect(rendered).to have_css("h3", text: I18n.t("admin_misc.entities.entry_page.missing_title", locale: locale))
      expect(rendered).to have_text(I18n.t("admin_misc.entities.entry_page.missing_description", locale: locale, name: "课程"))
      expect(rendered).not_to have_css("form, dialog")
    end
  end
end
