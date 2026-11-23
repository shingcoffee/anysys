# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Dashboard settings", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/settings" }

  it_behaves_like "an admin-guarded GET"

  it "renders a grouped catalog with guidance without duplicating sidebar search" do
    get "/#{customer.id}/admin/settings"
    expect(response).to have_http_status(:ok)
    main = Nokogiri::HTML(response.body).at_css("main")
    expect(main.text).to include(I18n.t("admin_settings.index.subtitle"))
    expect(main.text).to include(I18n.t("settings_navigation.descriptions.member_portal"))
    expect(main.text).to include(I18n.t("admin_settings.catalog.groups.members"))
    expect(main.text).not_to include("Manage members, access, your website, messages, payments, and billing.")
    expect(main.css("input[type='search'], [data-controller='list-filter']")).to be_empty
    expect(main.css("section[aria-labelledby^='catalog-']")).not_to be_empty
    expect(response.body).to include("Search settings...")
    expect(response.body).to include("Members")
    expect(response.body).to include("Billing")
    expect(response.body).to include("Member portal")
    expect(response.body).to include("Overview")
  end

  it "expands the selected Settings section and marks its child active" do
    enable_module!("email", customer)
    get "/#{customer.id}/admin/settings/modules/emails/template_tokens"

    expect(response).to have_http_status(:ok)
    nav = Nokogiri::HTML(response.body).at_css("aside nav[aria-label='Settings']")
    selected = nav.at_css('a[href$="/emails/template_tokens"]')
    expect(selected["aria-current"]).to eq("page")
    expect(selected.ancestors("details").first["open"]).not_to be_nil
    expect(nav.css("details[open]").size).to eq(1)
  end

  it "keeps localized group guidance and per-setting explanations visible" do
    enable_module!("email", customer)

    %w[en zh-CN].each do |locale|
      get guard_path, params: { locale: locale }
      content = Nokogiri::HTML(response.body).at_css("main")
      expect(content.text).to include(I18n.t("admin_settings.index.subtitle", locale: locale))
      expect(content.text).to include(I18n.t("admin_settings.catalog.modules.email", locale: locale))
      expect(content.text).to include(I18n.t("settings_navigation.descriptions.email_sending_limit", locale: locale))
      expect(content.css(".translation_missing")).to be_empty
    end
  end

  it_behaves_like "a removed admin URL", "/admin/settings/customer"
  it_behaves_like "a removed admin URL", "/admin/settings/users"
end
