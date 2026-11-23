# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Dashboards#show", type: :request do
  include_context "as admin"
  let(:guard_path) { "/#{customer.id}/admin/dashboard" }

  before do
    enable_module!("authentication", customer)
  end

  it_behaves_like "an admin-guarded GET"

  it "renders 200 and shows the landing stats and quick actions" do
    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)

    html = Nokogiri::HTML(response.body)
    expect(html.at("html")["class"].to_s.split).to include("h-full", "overflow-hidden")
    expect(html.at("body")["class"].to_s.split).to include("h-full", "overflow-hidden")

    %w[Entities Pages Modules Users].each do |label|
      expect(response.body).to include(label)
    end

    expect(response.body).to include(I18n.t("admin_misc.dashboard.snapshot"))
    expect(response.body).to include(I18n.t("admin_misc.dashboard.quick_actions"))
    expect(response.body).to include(I18n.t("admin_misc.dashboard.modules.title"))

    expect(response.body).to include(I18n.t("admin_misc.dashboard.actions.create_entity.label"))
    expect(response.body).to include(I18n.t("admin_misc.dashboard.actions.new_page.label"))
    expect(response.body).to include(I18n.t("admin_misc.dashboard.actions.invite_user.label"))

    expect(response.body).to include(admin_assistant_path(customer.id))
    expect(response.body).not_to include(new_admin_maintenance_entity_path(customer_id: customer.id))
    expect(response.body).to include(new_admin_maintenance_page_path(customer_id: customer.id))
    expect(response.body).to include(new_admin_modules_authentication_user_path(customer_id: customer.id))
  end

  it "offers Enable module when an optional module is still off" do
    create(:feature_module, required: false, status: :active)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin_misc.dashboard.actions.enable_module.label"))
    expect(response.body).to include(admin_maintenance_modules_path(customer_id: customer.id))
  end

  it "reflects real counts in the stats" do
    create(:entity, customer: customer)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    stats = LandingStats.for(customer).to_h
    expect(stats[:entities]).to be >= 1
    expect(response.body).to include(stats[:entities].to_s)
  end

  it "does not render the assistant composer or offline empty state" do
    get "/#{customer.id}/admin/dashboard"

    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.placeholder"))
    expect(response.body).not_to include(I18n.t("ai_assistant.assistant.offline.body"))
    expect(response.body).not_to include(%(id="ai_assistant_composer"))
    expect(response.body).not_to include("data-controller=\"ai-assistant\"")
  end

  it "highlights Home and links to the AI Assistant menu item" do
    get "/#{customer.id}/admin/dashboard"

    expect(response.body).to include(I18n.t("chrome.menu_bar.items.assistant"))
    expect(response.body).to include(admin_assistant_path(customer.id))
    html = Nokogiri::HTML(response.body)
    home = html.at("a[aria-current='page']")
    expect(home.text).to include(I18n.t("chrome.menu_bar.items.home"))
  end

  it "hides Maintenance from tenant admins in both desktop and mobile navigation" do
    get guard_path

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("nav[aria-label='Dashboard menu'] [data-menu-item-key='maintenance']")).to be_nil
    expect(html.at_css("[data-drawer-target='panel'] [data-menu-item='maintenance']")).to be_nil
  end

  it "renders tenant-aware top navigation and only enabled communication choices" do
    %w[payment email sms].each { |key| enable_module!(key, customer) }

    get guard_path

    nav = Nokogiri::HTML(response.body).at_css("nav[aria-label='Dashboard menu']")
    expect(nav.css("[data-menu-item-key]").first(5).map { |item| item["data-menu-item-key"] })
      .to eq(%w[home assistant users payments communication])
    expect(nav.at_css("a[data-menu-item-key='users']")['href']).to eq(admin_modules_authentication_users_path(customer.id))
    expect(nav.at_css("a[data-menu-item-key='payments']")['href']).to eq(admin_modules_payments_transactions_path(customer.id))
    expect(nav.css("details[data-menu-item-key='communication'] a").map { |link| link['href'] }).to eq([
      admin_modules_emails_send_activities_path(customer.id), admin_modules_sms_campaigns_path(customer.id)
    ])
  end

  it "omits the optional top navigation when those modules are off" do
    get guard_path

    nav = Nokogiri::HTML(response.body).at_css("nav[aria-label='Dashboard menu']")
    expect(nav.at_css("a[data-menu-item-key='users']")).to be_present
    expect(nav.css("[data-menu-item-key='payments'], [data-menu-item-key='communication']")).to be_empty
  end

  it "rejects a same-role admin using another tenant's URL" do
    other_customer = create(:customer)

    get "/#{other_customer.id}/admin/dashboard"

    expect(response).not_to have_http_status(:ok)
  end

  it "still serves the admin's own dashboard when the app is mounted under a sub-path" do
    get "/#{customer.id}/admin/dashboard", env: { "SCRIPT_NAME" => "/anysys" }

    expect(request.script_name).to eq("/anysys")
    expect(request.path).to eq("/anysys/#{customer.id}/admin/dashboard")
    expect(request.path_info).to eq("/#{customer.id}/admin/dashboard")
    expect(response).to have_http_status(:ok)
  end

  it "still rejects a same-role admin using another tenant's URL when mounted under a sub-path" do
    other_customer = create(:customer)

    get "/#{other_customer.id}/admin/dashboard", env: { "SCRIPT_NAME" => "/anysys" }

    expect(request.path).to eq("/anysys/#{other_customer.id}/admin/dashboard")
    expect(request.path_info).to eq("/#{other_customer.id}/admin/dashboard")
    expect(response).not_to have_http_status(:ok)
    expect(response).not_to have_http_status(:internal_server_error)
  end

  it "renders authentication module shortcuts" do
    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_modules_authentication_users_path(customer_id: customer.id))
    expect(response.body).to include(admin_modules_authentication_events_path(customer_id: customer.id))
  end

  it "surfaces email module shortcuts when email is enabled" do
    enable_module!("email", customer)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_modules_emails_templates_path(customer_id: customer.id))
    expect(response.body).to include(admin_modules_emails_send_activities_path(customer_id: customer.id))
    expect(response.body).to include(admin_modules_emails_lists_path(customer_id: customer.id))
    expect(response.body).to include(I18n.t("feature_modules.email.entries.audience"))
    expect(response.body).not_to include("/payments/checkout")
  end

  it "lists recent own pages and excludes another tenant's pages" do
    entity = create(:entity, customer: customer, name: "Dash Entity")
    own_page = create(:page, customer: customer, entity: entity, name: "Dash Own Page", launched: true)
    other = create(:customer)
    other_entity = create(:entity, customer: other, name: "Other Dash Entity")
    create(:page, customer: other, entity: other_entity, name: "Dash Other Page", launched: true)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dash Own Page")
    expect(response.body).to include(admin_page_path(customer.id, own_page))
    expect(response.body).not_to include("Dash Other Page")
  end

  it "omits getting started when every setup item is complete" do
    entity = create(:entity, customer: customer)
    create(:page, customer: customer, entity: entity, launched: true)
    optional = create(:feature_module, required: false, status: :active)
    ensure_customer_feature_module(customer, optional)
    create(:user, :member, customer: customer)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(I18n.t("admin_misc.dashboard.setup.title"))
  end

  it "still shows getting started when only required authentication is enabled" do
    entity = create(:entity, customer: customer)
    create(:page, customer: customer, entity: entity, launched: true)
    create(:feature_module, required: false, status: :active)
    create(:user, :member, customer: customer)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("admin_misc.dashboard.setup.title"))
  end

  it "surfaces payment module shortcuts when payment is enabled" do
    enable_module!("payment", customer)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(admin_modules_payments_transactions_path(customer_id: customer.id))
    expect(response.body).to include(admin_modules_payments_reconciliations_path(customer_id: customer.id))
    expect(response.body).not_to include("/#{customer.id}/admin/modules/payments/subscriptions")
    expect(response.body).not_to include(admin_settings_modules_payments_merchant_accounts_path(customer_id: customer.id))
    expect(response.body).not_to include("/payments/checkout")
    expect(response.body).not_to include("/admin/maintenance/platform/module_settings")
  end

  it "lists recent own entities and excludes another tenant's entities" do
    own_entity = create(:entity, customer: customer, name: "Dash Own Entity")
    other = create(:customer)
    create(:entity, customer: other, name: "Dash Other Entity")

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dash Own Entity")
    expect(response.body).to include(admin_entity_path(customer.id, own_entity))
    expect(response.body).not_to include("Dash Other Entity")
  end
end

RSpec.describe "Admin::Dashboards#show as platform owner", type: :request do
  include_context "as platform owner"

  it "shows Maintenance in both desktop and mobile navigation" do
    get "/#{customer.id}/admin/dashboard"

    html = Nokogiri::HTML(response.body)
    expect(html.at_css("nav[aria-label='Dashboard menu'] a[data-menu-item-key='maintenance']")['href'])
      .to eq(admin_maintenance_path(customer.id))
    expect(html.at_css("[data-drawer-target='panel'] [data-menu-item='maintenance']")).to be_present
  end

  it "hides Maintenance from an admin of the platform customer" do
    sign_out owner
    sign_in create(:user, :admin, customer: customer)

    get "/#{customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("nav[aria-label='Dashboard menu'] [data-menu-item-key='maintenance']")).to be_nil
    expect(html.at_css("[data-drawer-target='panel'] [data-menu-item='maintenance']")).to be_nil
  end

  it "renders the URL customer's dashboard and excludes other tenants" do
    url_customer = create(:customer)
    other = create(:customer)
    enable_module!("authentication", url_customer)

    url_entity = create(:entity, customer: url_customer, name: "Owner Url Entity")
    create(:entity, customer: other, name: "Owner Other Entity")
    create(:entity, customer: customer, name: "Owner Home Entity")

    get "/#{url_customer.id}/admin/dashboard"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Owner Url Entity")
    expect(response.body).to include(admin_entity_path(url_customer.id, url_entity))
    expect(response.body).not_to include("Owner Other Entity")
    expect(response.body).not_to include("Owner Home Entity")
    html = Nokogiri::HTML(response.body)
    expect(html.at_css("nav[aria-label='Dashboard menu'] a[data-menu-item-key='maintenance']")).to be_present
  end
end
