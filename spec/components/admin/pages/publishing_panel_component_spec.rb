# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::Pages::PublishingPanelComponent, type: :component do
  let(:page_record) { build_stubbed(:page, name: "Contact Form", launched: false) }
  let(:customer_id) { 81_721_200 }
  let(:return_to) { "/#{customer_id}/admin/pages/#{page_record.id}" }
  let(:close_path) { "/#{customer_id}/admin/pages" }

  def render_component
    with_request_url("/#{customer_id}/admin/pages/#{page_record.id}", host: "www.example.com") do
      render_inline(described_class.new(
        page: page_record,
        customer_id: customer_id,
        return_to: return_to,
        close_path: close_path
      ))
    end
  end

  before { render_component }

  it "renders a right-side slide-over with backdrop" do
    expect(page).to have_css("[data-controller='slide-over']")
    expect(page).to have_css("[data-slide-over-target='backdrop'][data-action='click->slide-over#close']")
    expect(page).to have_css("aside[data-slide-over-target='panel']")
  end

  it "renders the page title, preview link, and close control" do
    expect(page).to have_text("Contact Form")
    expect(page).to have_link(I18n.t("maint_core.pages.preview"), href: /preview/)
    expect(page).to have_css("a[data-action='slide-over#close']", text: I18n.t("admin_misc.pages.publishing_panel.close"))
  end

  it "embeds the distribution card for launch and visibility" do
    expect(page).to have_text(I18n.t("comp_misc.distribution.header_title_html"))
    expect(page).to have_text(I18n.t("comp_misc.distribution.audience_section"))
    expect(page).to have_css("form[data-controller='page-visibility tooltip'][data-turbo-frame='page-publishing']")
    expect(page).to have_field("return_to", type: :hidden, with: return_to)
  end
end
