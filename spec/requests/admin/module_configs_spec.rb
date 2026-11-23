# frozen_string_literal: true

require "rails_helper"

# Covers Admin::ModuleConfigsController
# Routes: GET/PATCH /:customer_id/admin/settings/modules/:key
#         GET       /:customer_id/admin/settings/modules/:key/:entry_key
#
# The controller gates on: module enabled for customer, CustomerAssignment present.
RSpec.describe "Admin::ModuleConfigsController", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }

  # Use the real "authentication" module which has a Registration class that
  # exposes `default_exit_config` and `configuration_keys`.
  let!(:feature_module) do
    enable_module!("authentication", customer, name: "User Authentication")
      .tap { |fm| fm.update!(handoff_enabled: true) }
  end

  let!(:customer_assignment) do
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: feature_module)
  end

  def show_path(key = "authentication")
    "/#{customer.id}/admin/settings/modules/#{key}"
  end

  def update_path
    show_path
  end

  # The controller redirects to the PLURAL key after update:
  # admin_module_config_path(cid, @feature_module.key.pluralize)
  def show_path_plural
    show_path("authentications")
  end

  # ── authorization ─────────────────────────────────────────────────────────

  describe "GET show — auth guards" do
    let(:guard_path) { show_path }

    it_behaves_like "an admin-guarded GET"

    it "returns 404 when the module does not exist at all" do
      sign_in admin
      get show_path("nonexistent_module_xyz")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { update_path }

    it_behaves_like "an admin-guarded request", :patch
  end

  describe "GET show entry — auth guards" do
    let(:guard_path) { "/#{customer.id}/admin/settings/modules/authentication/some_entry" }

    it_behaves_like "an admin-guarded GET"
  end

  # ── GET show ─────────────────────────────────────────────────────────────

  describe "GET show" do
    before { sign_in admin }

    it "returns 200 for the default, entry_key, and plural-key URLs" do
      [
        show_path,
        "/#{customer.id}/admin/settings/modules/authentication/some_entry",
        "/#{customer.id}/admin/settings/modules/authentications"
      ].each do |path|
        get path
        expect(response).to have_http_status(:ok)
      end
    end

    it "uses the localized task title for account security" do
      allow_any_instance_of(FeatureModules::Module).to receive(:display_name).and_return("Localized module")

      get show_path

      expect(Capybara.string(response.body)).to have_css("h1", text: I18n.t("settings_navigation.items.account_security"), exact_text: true)
      expect(Capybara.string(response.body).find("[data-settings-page]")).not_to have_text("Localized module")
    end

    %w[en zh-CN].each do |locale|
      it "uses readable task titles for generic roots, plural aliases, and entries in #{locale}" do
        {
          "authentication" => ["account_security", %w[authentication authentications authentication/some_entry]],
          "email" => ["email_sending_limit", %w[email emails emails/daily_cap]],
          "sms" => ["sms_sending_limit", %w[sms sms/daily_cap]],
          "ai_assistant" => ["ai_assistant", %w[ai_assistant ai_assistants]],
          "payment" => ["payment_providers", %w[payment payments payments/gateway]]
        }.each do |key, (task, paths)|
          enable_module!(key, customer).update!(handoff_enabled: true)
          paths.each do |path|
            get show_path(path), params: { locale: locale }
            expect(response).to have_http_status(:ok), path
            page = Capybara.string(response.body)
            expect(page).to have_css("h1", count: 1, exact_text: I18n.t("settings_navigation.items.#{task}", locale: locale))
            expect(page).to have_css("[data-settings-page]", count: 1)
            expect(page).to have_text(I18n.t("settings_modules.configuration.return_explanations.#{key}", locale: locale))
            expect(page).not_to have_css(".translation_missing")
          end
        end
      end
    end

    it "uses a future module's display name when its entry has no translated title" do
      future = enable_module!("qa_tool", customer, name: "Stored name")
      allow_any_instance_of(FeatureModules::Module).to receive(:display_name).and_call_original
      allow_any_instance_of(FeatureModules::Module).to receive(:display_name) do |record|
        record.id == future.id ? "Localized team tools" : record.name
      end
      get show_path("qa_tools/internal_entry_key")
      expect(response).to have_http_status(:ok)
      expect(Capybara.string(response.body)).to have_css("h1", exact_text: "Localized team tools")
      expect(response.body).not_to include("Internal Entry Key")
    end

    it "renders readable return defaults and an independently saved URL preference, without raw JSON" do
      customer_assignment.update!(configuration: {
        session_timeout: "45", exit_landing_page: { kind: "url", url: "https://example.com/done" }
      }.to_json)
      get show_path
      page = Capybara.string(response.body)
      content = page.find("[data-settings-page]")
      expect(content).to have_text(I18n.t("settings_modules.configuration.default_return",
                                         destination: I18n.t("settings_modules.configuration.home_destination")))
      expect(content.text).not_to include("customer_home", '"kind"', "=>")
      expect(content).not_to have_css("pre, code")
      form = content.find("section[aria-label='After finishing'] form", visible: :all)
      expect(form).to have_field("configuration[exit_landing_page][url]", with: "https://example.com/done", type: "url", visible: :all)
      expect(form).to have_button(I18n.t("settings_modules.configuration.save_return"), visible: :all)
      expect(form).not_to have_css('[name="configuration[session_timeout]"]', visible: :all)

      patch form[:action], params: { configuration: { exit_landing_page: { kind: "url", url: "https://example.com/return" } } }
      expect(response).to have_http_status(:found)
      expect(customer_assignment.reload.configuration_json).to include(
        "session_timeout" => "45", "exit_landing_page" => { "kind" => "url", "url" => "https://example.com/return" }
      )
    end

    it "hides a saved Return URL while handoff is disabled and restores it when re-enabled" do
      customer_assignment.merge_configuration!(exit_landing_page: { kind: "url", url: "https://example.com/done" })
      feature_module.update!(handoff_enabled: false)

      get show_path
      content = Capybara.string(response.body).find("[data-settings-page]")
      expect(content).to have_field("configuration[session_timeout]")
      expect(content).not_to have_field("configuration[exit_landing_page][url]", visible: :all)
      expect(content).not_to have_text("After finishing")
      expect(Capybara.string(response.body)).not_to have_link(
        I18n.t("settings_modules.configuration.return_url"), href: "#{show_path}/return_url"
      )

      feature_module.update!(handoff_enabled: true)
      get show_path
      expect(Capybara.string(response.body)).to have_field(
        "configuration[exit_landing_page][url]", with: "https://example.com/done", visible: :all
      )
    end

    it "opens the Return URL form from Settings for handoff-enabled modules with dedicated settings" do
      %w[payment captcha website].each do |key|
        enable_module!(key, customer).update!(handoff_enabled: true)
        path = show_path("#{key.pluralize}/return_url")

        get path

        expect(response).to have_http_status(:ok), key
        page = Capybara.string(response.body)
        expect(page.find("[data-settings-page]")).to have_field("configuration[exit_landing_page][url]")
        expect(page).to have_css("aside a[href='#{path}'][aria-current='page']")
      end
    end
  end

  # ── GET show when module not enabled ──────────────────────────────────────

  describe "GET show when module is not enabled for customer" do
    let!(:other_module) { find_or_create_feature_module!("ai_assistant", name: "AI Assistant") }

    before { sign_in admin }

    it "returns 404 when no CustomerAssignment exists for the module" do
      # AI Assistant has no dedicated settings root and no assignment here
      get "/#{customer.id}/admin/settings/modules/ai_assistant"
      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 when the module assignment is suspended" do
      customer_assignment.update!(status: :suspended)
      get show_path
      expect(response).to have_http_status(:not_found)
    end
  end

  # ── PATCH update — success ────────────────────────────────────────────────

  describe "PATCH update" do
    before { sign_in admin }

    it "updates configuration and redirects back to show (plural key)" do
      patch update_path,
            params: { configuration: { mfa_enabled: "1", session_timeout: "60" } }
      # Controller redirects to admin_module_config_path(cid, key.pluralize)
      expect(response).to have_http_status(:redirect)
      expect(flash[:notice]).to match(/configuration updated/i)
    end

    it "filters configuration params through the module's configuration_keys whitelist" do
      # The authentication registration exposes :mfa_enabled, :session_timeout,
      # :max_login_attempts; an unknown key must be silently dropped.
      patch update_path,
            params: { configuration: { mfa_enabled: "1", evil_key: "injected" } }
      expect(response).to have_http_status(:redirect)
      saved = JSON.parse(customer_assignment.reload.configuration)
      expect(saved.keys).not_to include("evil_key")
    end

    it "accepts an empty configuration hash (falls back gracefully)" do
      patch update_path, params: {}
      expect(response).to have_http_status(:redirect)
    end

    it "merges onto the existing blob, preserving keys written by other surfaces (B2)" do
      # The self-signup / forgot-password toggles live in the same JSON blob but
      # are written by dedicated controllers, so this page must not wipe them.
      customer_assignment.update!(configuration: { "allow_registration" => "true",
                                                   "allow_password_reset" => "false" }.to_json)

      patch update_path, params: { configuration: { mfa_enabled: "1" } }
      expect(response).to have_http_status(:redirect)

      saved = JSON.parse(customer_assignment.reload.configuration)
      expect(saved["mfa_enabled"]).to eq("1")
      expect(saved["allow_registration"]).to eq("true")
      expect(saved["allow_password_reset"]).to eq("false")
    end

    it "falls back to DEFAULT_CONFIG_KEYS when registration_class lacks configuration_keys" do
      # Stub registration_class to be an anonymous module without configuration_keys
      # to exercise the `else DEFAULT_CONFIG_KEYS` branch (line 62).
      null_reg = Module.new do
        def self.default_exit_config = nil
        def self.before_request(_controller) = nil
        def self.sidebar_contributions(_ctrl) = { entries: [], settings: [] }
      end
      allow_any_instance_of(FeatureModules::Module)
        .to receive(:registration_class).and_return(null_reg)

      patch update_path,
            params: { configuration: { exit_landing_page: { kind: "url", url: "https://example.com/done" } } }
      expect(response).to have_http_status(:redirect)
      saved = JSON.parse(customer_assignment.reload.configuration)
      expect(saved["exit_landing_page"]).to eq("kind" => "url", "url" => "https://example.com/done")
    end

    it "persists the nested exit_landing_page hash posted by the settings form" do
      patch update_path,
            params: {
              configuration: {
                mfa_enabled: "true",
                exit_landing_page: { kind: "url", url: "https://example.com/return" }
              }
            }
      expect(response).to have_http_status(:redirect)
      saved = JSON.parse(customer_assignment.reload.configuration)
      expect(saved["mfa_enabled"]).to eq("true")
      expect(saved["exit_landing_page"]).to eq("kind" => "url", "url" => "https://example.com/return")
    end

    it "ignores a forged Return URL when handoff is disabled but saves other preferences" do
      customer_assignment.merge_configuration!(exit_landing_page: { kind: "url", url: "https://example.com/old" })
      feature_module.update!(handoff_enabled: false)

      patch update_path, params: { configuration: {
        session_timeout: "45", exit_landing_page: { kind: "url", url: "https://example.com/forged" }
      } }

      expect(response).to have_http_status(:redirect)
      expect(customer_assignment.reload.configuration_json).to include(
        "session_timeout" => "45", "exit_landing_page" => { "kind" => "url", "url" => "https://example.com/old" }
      )
    end

    it "redirects with a generic alert on StandardError (e.g. corrupt record)" do
      allow_any_instance_of(FeatureModules::CustomerAssignment)
        .to receive(:update!).and_raise(StandardError, "boom")

      patch update_path,
            params: { configuration: { mfa_enabled: "1" } }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Failed to update configuration.")
      expect(flash[:alert]).not_to match(/boom/i)
    end

    it "rejects a non-object configuration without 500ing" do
      patch update_path, params: { configuration: "[]" }, as: :json

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Configuration must be an object")
      expect(response).not_to have_http_status(:internal_server_error)
    end
  end

  # ── parse_exit_override ────────────────────────────────────────────────────

  describe "GET show — parse_exit_override branches" do
    before { sign_in admin }

    # parse_exit_override rescues JSON::ParserError and returns nil.
    it "renders ok for empty JSON, invalid JSON, and nil configuration" do
      [{}.to_json, "not-json", nil].each do |config|
        customer_assignment.update_column(:configuration, config)
        get show_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ── cross-tenant isolation ────────────────────────────────────────────────

  describe "cross-tenant isolation" do
    it "admin cannot read or write another customer's module config" do
      other_customer = create(:customer)
      other_admin    = create(:user, :admin, customer: other_customer)
      sign_in other_admin

      get show_path   # accessing customer's URL, not other_customer's
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)

      original = customer_assignment.reload.configuration
      patch update_path, params: { configuration: { session_timeout: "99" } }
      expect(response).to redirect_to(Authentication::LandingPath.for(other_admin))
      expect(customer_assignment.reload.configuration).to eq(original)
    end
  end
end
