# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules#index", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/modules" }

  before { enable_module!("authentication", customer) }

  it_behaves_like "an admin-guarded GET"

  it "renders enabled module cards instead of a sidebar-only hint" do
    get guard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin_modules.nav.modules"))
    main = Nokogiri::HTML(response.body).at_css("main")
    expect(main.text).to include(I18n.t("admin_modules.index.description"))
    expect(main.text).to include(I18n.t("admin_misc.dashboard.modules.blurbs.authentication"))
    expect(main.text).not_to include("modules enabled", "pages")
    expect(main.css("section[aria-labelledby^='modules-section-'] a").size).to eq(2)
    expect(main.css("input[type='search'], [data-controller='list-filter']")).to be_empty
    expect(Nokogiri::HTML(response.body).css("aside input[type='search']")).not_to be_empty
    expect(response.body).to include(admin_modules_authentication_users_path(customer_id: customer.id))
    # Module enablement is accessed from Maintenance, never from the hub.
    expect(response.body).not_to include(admin_maintenance_modules_path(customer_id: customer.id))
    expect(response.body).not_to include(I18n.t("admin_modules.index.pick_hint"))
    expect(response.body).not_to include("/payments/checkout")
  end

  it "surfaces email destinations when email is enabled" do
    enable_module!("email", customer)

    get guard_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_modules_emails_templates_path(customer_id: customer.id))
  end

  it "keeps localized module introductions, descriptions, and record labels visible" do
    enable_module!("email", customer)

    %w[en zh-CN].each do |locale|
      get guard_path, params: { locale: locale }
      content = Nokogiri::HTML(response.body).at_css("main")
      expect(content.text).to include(I18n.t("admin_modules.index.description", locale: locale))
      expect(content.text).to include(I18n.t("admin_misc.dashboard.modules.blurbs.email", locale: locale))
      expect(content.text).to include(I18n.t("feature_modules.email.titles.templates", locale: locale))
      expect(content.css(".translation_missing")).to be_empty
    end
  end

  it "keeps all customer settings links in the Settings area, including settings-only modules" do
    %w[email sms payment captcha ai_assistant website].each { |key| enable_module!(key, customer) }

    get guard_path
    hub = Nokogiri::HTML(response.body).at_css("main")
    expect(hub.css('a[href*="/admin/settings/"]')).to be_empty
    expect(hub.css("h3").map(&:text)).to include(I18n.t("feature_modules.captcha.name"))
    expect(hub.css("section[aria-labelledby^='modules-section-'] details")).to be_empty
    sidebar = Nokogiri::HTML(response.body).at_css("aside nav[aria-label='Modules']")
    expect(sidebar.css('a[href$="/howto"]').size).to eq(7)

    get admin_setting_path(customer.id)
    expect(response).to have_http_status(:ok)
    settings = Nokogiri::HTML(response.body).at_css("[data-settings-page]")
    expect(settings.css('a[href*="/admin/settings/modules/captcha"]')).not_to be_empty
    expect(settings.css('a[href*="/admin/settings/modules/payments/merchant_accounts"]')).not_to be_empty
  end

  it "keeps nested module pages free of settings and maintenance shortcuts" do
    %w[email sms payment website].each { |key| enable_module!(key, customer) }
    paths = [
      admin_modules_authentication_users_path(customer.id),
      admin_modules_emails_templates_path(customer.id),
      admin_modules_sms_messages_path(customer.id),
      admin_modules_payments_transactions_path(customer.id),
      new_admin_modules_website_page_path(customer.id)
    ]

    paths.each do |path|
      get path
      expect(response).to have_http_status(:ok), path
      content = Nokogiri::HTML(response.body).at_css("main")
      expect(content.css('a[href*="/admin/settings/modules/"], a[href*="/admin/maintenance/modules"]')).to be_empty, path
      content.css("[data-catalog-thumbnail]").each(&:remove)
      expect(content.text).not_to include(I18n.t("admin_modules.index.configure")), path
    end
  end

  it "rejects a same-role admin using another tenant's URL" do
    other = create(:customer)

    get "/#{other.id}/admin/modules"

    expect(response).not_to have_http_status(:ok)
  end

  it "hides Manage Modules from the sidebar and hub for a customer admin" do
    get guard_path

    expect(response.body).not_to include("Manage Modules")
    expect(response.body).not_to include("maintenance/modules")
    expect(response.body).to include(I18n.t("admin_modules.nav.overview"))
  end

  it "keeps maintenance actions out of the platform owner's module hub" do
    owner = find_or_create_platform_owner
    sign_in owner

    get "/#{owner.customer.id}/admin/modules"

    expect(response.body).not_to include("Manage Modules")
    expect(response.body).not_to include("maintenance/modules")
  end
end
