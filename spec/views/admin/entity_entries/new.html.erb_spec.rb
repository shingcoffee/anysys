# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/entity_entries/new.html.erb", type: :view do
  let(:customer) { double("Customer", id: 12345678) }
  let(:entity) { double("Entity", to_param: "7", display_label: "课程") }

  before do
    assign(:entity, entity)
    without_partial_double_verification { allow(view).to receive(:current_customer).and_return(customer) }
  end

  %i[en zh-CN].each do |locale|
    it "mounts the dashboard shell and breadcrumbs around the entity's rendered page in #{locale}" do
      assign(:content, %(<form action="/12345678/page/abc" data-turbo-frame="_top"></form>))

      I18n.with_locale(locale) { render }

      expect(rendered).to have_css("h1", text: I18n.t("admin_misc.entities.entry_form.title", locale: locale, name: "课程"))
      expect(rendered).to have_text(I18n.t("admin_misc.entities.entry_form.description", locale: locale, name: "课程"))
      expect(rendered).to have_link(I18n.t("admin_misc.domains.breadcrumb", locale: locale), href: "/12345678/admin/domains")
      expect(rendered).to have_link("课程", href: "/12345678/admin/entities/7")
      expect(rendered).to have_css("span.bg-accent-subtle.text-accent[aria-hidden='true'] svg")
      expect(rendered).to have_css(".card > div > div.max-w-4xl form[action='/12345678/page/abc']")
      expect(rendered).to have_css("dialog#entity-quick-add-dialog-0")
      expect(rendered).not_to have_css("turbo-frame[id^='entity-quick-add-frame'] form")
      expect(view.content_for(:container_width)).to be_blank
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
