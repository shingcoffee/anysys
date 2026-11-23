# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::ModuleSettings", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@ms.test", password: "password123") }
  let(:member_user)    { create(:user, :member, customer: other_customer, email: "member@ms.test", password: "password123") }

  let!(:feature_module) do
    create(:feature_module, key: "test_ms_module_#{SecureRandom.hex(4)}", name: "Test MS Module",
           status: :inactive, required: false)
  end

  def index_path
    admin_maintenance_platform_module_settings_path(platform_customer.id)
  end

  def show_path(mod = feature_module)
    admin_maintenance_platform_module_setting_path(platform_customer.id, mod)
  end

  def configuration_path(mod = feature_module)
    configuration_admin_maintenance_platform_module_setting_path(platform_customer.id, mod)
  end

  def developer_path(mod = feature_module)
    developer_admin_maintenance_platform_module_setting_path(platform_customer.id, mod)
  end

  def update_path(mod = feature_module)
    admin_maintenance_platform_module_setting_path(platform_customer.id, mod)
  end

  # -------------------------------------------------------------------
  # Authorization
  # -------------------------------------------------------------------
  let(:guard_path) { index_path }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET show auth" do
    let(:guard_path) { show_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET configuration auth" do
    let(:guard_path) { configuration_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET developer auth" do
    let(:guard_path) { developer_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "PATCH update auth" do
    let(:guard_path) { update_path }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  context "as non-owner admin" do
    before { sign_in admin_user }

    it "is denied on index" do
      get admin_maintenance_platform_module_settings_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on show" do
      get admin_maintenance_platform_module_setting_path(other_customer.id, feature_module)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on configuration" do
      get configuration_admin_maintenance_platform_module_setting_path(other_customer.id, feature_module)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on developer" do
      get developer_admin_maintenance_platform_module_setting_path(other_customer.id, feature_module)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on update" do
      patch admin_maintenance_platform_module_setting_path(other_customer.id, feature_module),
            params: { status_active: "1" }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  context "as member" do
    before { sign_in member_user }

    it "is denied on index" do
      get admin_maintenance_platform_module_settings_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Happy path + branches (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    describe "GET /index" do
      it "renders the stats summary with correct counts" do
        get index_path
        modules = FeatureModules::Module.by_name.to_a
        expected = I18n.t("maint_platform.module_settings.index.stats_summary",
                           total: modules.size, active: modules.count(&:active?), required: modules.count(&:required?))
        expect(response.body).to include(expected)
      end
    end

    describe "GET /show" do
      it "renders Overview without Developer pane content, and Developer as a nav tab" do
        get show_path
        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('data-controller="tabs"')
        expect(response.body).to include("data-module-settings-nav")
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.nav.developer"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.sections.availability"))
        expect(response.body).to include('data-module-settings-pane="overview"')
        expect(response.body).to include('data-module-settings-section="availability"')
        expect(response.body).to include('data-module-settings-section="details"')
        expect(response.body).to match(/data-section-nav-tab="overview"[^>]*aria-current="page"/)
        expect(response.body).not_to include('data-developer-reference="true"')
        expect(response.body).not_to include(I18n.t("maint_platform.module_settings.show.handoff_target"))
        expect(response.body).not_to include("Integration Contract")
      end

      it "renders the availability controls panel on Overview" do
        get show_path
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.sections.availability"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.module_status"))
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.required_module"))
        expect(response.body).not_to include(I18n.t("maint_platform.module_settings.show.handoff_target"))
      end

      it "links to AI Assistant platform credentials from the ai_assistant module show" do
        ai_assistant = find_or_create_feature_module!("ai_assistant", name: "AI Assistant")
        get show_path(ai_assistant)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(
          admin_maintenance_platform_module_settings_ai_assistant_settings_path(platform_customer.id)
        )
        expect(response.body).to include("data-module-settings-nav")
      end

      it "renders the module section nav on the email overview" do
        email = find_or_create_feature_module!("email", name: "Email")
        get show_path(email)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("data-module-settings-nav")
        expect(response.body).to include(
          admin_maintenance_platform_module_settings_email_credentials_path(platform_customer.id)
        )
        expect(response.body).to include(configuration_path(email))
      end

      it "renders payment Overview and points Providers at the gateways path" do
        payment = find_or_create_feature_module!("payment", name: "Payments")

        get show_path(payment)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-pane="overview"')
        expect(response.body).to include('data-module-settings-section="availability"')
        expect(response.body).to match(/data-section-nav-tab="overview"[^>]*aria-current="page"/)
        expect(response.body).to include(
          admin_maintenance_platform_module_settings_payment_gateways_path(platform_customer.id)
        )
        expect(response.body).to include(
          admin_maintenance_platform_module_settings_payment_webhook_events_path(platform_customer.id)
        )
        expect(response.body).not_to include(I18n.t("maint_platform.module_settings.show.payment.title"))
      end

      it "renders captcha Overview and points Resources at the pages path" do
        captcha = find_or_create_feature_module!("captcha", name: "Captcha")

        get show_path(captcha)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-pane="overview"')
        expect(response.body).to include('data-module-settings-section="availability"')
        expect(response.body).to include(
          admin_maintenance_platform_module_settings_captcha_pages_path(platform_customer.id)
        )
        expect(response.body).not_to include(I18n.t("maint_platform.module_settings.show.captcha.pages_title"))
      end
    end

    describe "GET /configuration" do
      it "returns 200 and renders the Configuration pane" do
        feature_module.update!(configuration_schema: {
          "daily_cap" => { "type" => "integer", "default" => 1 }
        }.to_json)

        get configuration_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-pane="configuration"')
        expect(response.body).to include('data-module-settings-section="defaults"')
        expect(response.body).to match(/data-section-nav-tab="configuration"[^>]*aria-current="page"/)
        expect(response.body).not_to include('data-module-settings-section="availability"')
      end
    end

    describe "GET /developer" do
      it "renders the Integration Contract section" do
        get developer_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Integration Contract")
        expect(response.body).to include('data-module-settings-pane="developer"')
        expect(response.body).to include('data-developer-reference="true"')
        expect(response.body).to include('data-module-settings-section="contract"')
      end

      it "renders model attributes with template token switches and omits Routes card" do
        auth_module = FeatureModules::Module.find_by!(key: "authentication")
        get developer_path(auth_module)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-section="models"')
        expect(response.body).to include('data-controller="template-token-checkbox"')
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.tokens.token_status"))
        expect(response.body).not_to include('data-module-settings-section="availability"')
        expect(response.body).not_to include("Routes")
      end

      it "opens the model named in ?model=" do
        auth_module = FeatureModules::Module.find_by!(key: "authentication")
        get developer_admin_maintenance_platform_module_setting_path(platform_customer.id, auth_module,
                                                                    model: "Authentication::User")
        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-model="Authentication::User"')
      end

      context "for a module that declares a handoff contract (payment)" do
        let!(:payment_module) { find_or_create_feature_module!("payment", name: "Payments") }

        it "lists the module's input and output fields" do
          get developer_path(payment_module)
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("Integration Contract")
          expect(response.body).to include("amount")
          expect(response.body).to include("payment_reference")
        end
      end
    end

    describe "PATCH /update — activate a module" do
      it "sets status to active and redirects with notice" do
        patch update_path, params: { status_active: "1" }
        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.status).to eq("active")
      end
    end

    describe "PATCH /update — workspace pane context" do
      it "returns to Configuration after a successful update" do
        patch update_path, params: { section: "configuration", status_active: "1" }

        expect(response).to redirect_to(configuration_path)
      end

      it "returns to Configuration after a failed update" do
        allow(FeatureModules::Module).to receive(:find).with(feature_module.id.to_s).and_return(feature_module)
        allow(feature_module).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(feature_module))

        patch update_path, params: { section: "configuration", status_active: "1" }

        expect(response).to redirect_to(configuration_path)
      end

      it "returns to Developer after a successful update" do
        patch update_path, params: { section: "developer", status_active: "1" }

        expect(response).to redirect_to(developer_path)
      end

      it "returns to the selected Developer model and drops a malformed model value" do
        patch update_path, params: { section: "developer", model: "Payments::Order", status_active: "1" }
        expect(response).to redirect_to(
          developer_admin_maintenance_platform_module_setting_path(platform_customer.id, feature_module, model: "Payments::Order")
        )

        patch update_path, params: { section: "developer", model: "https://evil.example", status_active: "1" }
        expect(response).to redirect_to(developer_path)
      end

      it "returns to Developer after a failed update" do
        allow(FeatureModules::Module).to receive(:find).with(feature_module.id.to_s).and_return(feature_module)
        allow(feature_module).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(feature_module))

        patch update_path, params: { section: "developer", status_active: "1" }

        expect(response).to redirect_to(developer_path)
      end

      it "falls back to Overview for an unknown section after a successful update" do
        patch update_path, params: { section: "operations", status_active: "1" }

        expect(response).to redirect_to(show_path)
      end

      it "falls back to Overview for an unknown section after a failed update" do
        allow(FeatureModules::Module).to receive(:find).with(feature_module.id.to_s).and_return(feature_module)
        allow(feature_module).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(feature_module))

        patch update_path, params: { section: "providers", status_active: "1" }

        expect(response).to redirect_to(show_path)
      end

      it "does not reflect a crafted section value" do
        patch update_path, params: { section: "https://attacker.example/redirect", status_active: "1" }

        expect(response).to redirect_to(show_path)
      end

      it "ignores a leftover tab param and stays on Overview" do
        patch update_path, params: { tab: "developer", status_active: "1" }

        expect(response).to redirect_to(show_path)
      end
    end

    describe "PATCH /update — deactivate a module" do
      it "sets status inactive and clears required + handoff_enabled" do
        feature_module.update!(status: :active, required: true, handoff_enabled: true)
        patch update_path, params: { status_active: "0" }
        feature_module.reload
        expect(feature_module.status).to eq("inactive")
        expect(feature_module.required).to be(false)
        expect(feature_module.handoff_enabled).to be(false)
      end

      it "deprovisions every customer so leftover Payments credentials cannot charge" do
        payment_mod = find_or_create_feature_module!("payment", name: "Payments")
        payment_mod.update!(status: :active, required: false, handoff_enabled: false)
        enable_module!("payment", other_customer, name: "Payments")
        account = Payments::MerchantAccount.unscoped_by_tenant.find_or_create_by!(
          customer_id: other_customer.id, provider: "alipay", mode: "sandbox"
        ) do |acc|
          acc.merchant_id = "2088deprov"
          acc.status = "disabled"
        end
        account.update!(status: "active")

        patch update_path(payment_mod), params: { status_active: "0" }

        expect(payment_mod.reload.status).to eq("inactive")
        expect(account.reload.status).to eq("disabled")
      end
    end

    describe "PATCH /update — toggle handoff_enabled" do
      it "opts an active module into being a handoff target" do
        feature_module.update!(status: :active, handoff_enabled: false)
        patch update_path, params: { handoff_enabled: "1" }
        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.handoff_enabled).to be(true)
      end

      it "opts a module back out when toggled off" do
        feature_module.update!(status: :active, handoff_enabled: true)
        patch update_path, params: { handoff_enabled: "0" }
        expect(feature_module.reload.handoff_enabled).to be(false)
      end

      it "refuses to enable handoff while the module is inactive" do
        expect(feature_module.status).to eq("inactive")
        patch update_path, params: { handoff_enabled: "1" }
        expect(feature_module.reload.handoff_enabled).to be(false)
      end
    end

    describe "PATCH /update — refuse to mark required while inactive" do
      it "does not set required when module is inactive" do
        expect(feature_module.status).to eq("inactive")
        patch update_path, params: { required: "1" }
        expect(feature_module.reload.required).to be(false)
      end
    end

    describe "PATCH /update — set required when active" do
      it "sets required: true and redirects with notice" do
        feature_module.update!(status: :active, required: false)
        patch update_path, params: { required: "1" }
        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.required).to be(true)
      end

      it "sets required: false when toggled off" do
        feature_module.update!(status: :active, required: true)
        patch update_path, params: { required: "0" }
        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.required).to be(false)
      end
    end

    describe "PATCH /update — a mandatory module" do
      it "keeps status/required fixed (no-op) but still succeeds" do
        auth = find_or_create_feature_module!("authentication", name: "User Authentication")

        original_status   = auth.status
        original_required = auth.required
        patch admin_maintenance_platform_module_setting_path(platform_customer.id, auth),
              params: { status_active: "0", required: "0" }
        auth.reload
        expect(auth.status).to eq(original_status)
        expect(auth.required).to eq(original_required)
      end

      it "still lets the platform owner edit its config defaults" do
        auth = find_or_create_feature_module!("authentication", name: "User Authentication")

        auth.update!(configuration_schema: { "mfa_enabled" => { "type" => "boolean", "default" => false } }.to_json)
        patch admin_maintenance_platform_module_setting_path(platform_customer.id, auth),
              params: { config_defaults: { mfa_enabled: "true" } }

        expect(auth.reload.configuration_schema_json["mfa_enabled"]["default"]).to eq("true")
      end

      it "renders the boolean schema default as a checkbox with an unchecked fallback" do
        auth = find_or_create_feature_module!("authentication", name: "User Authentication")

        auth.update!(configuration_schema: { "mfa_enabled" => { "type" => "boolean", "default" => false, "description" => "x" } }.to_json)
        get configuration_admin_maintenance_platform_module_setting_path(platform_customer.id, auth)

        expect(response.body).to match(/<input[^>]*type="hidden"[^>]*name="config_defaults\[mfa_enabled\]"[^>]*value="0"/)
        expect(response.body).to match(/<input[^>]*type="checkbox"[^>]*name="config_defaults\[mfa_enabled\]"[^>]*value="1"/)
      end

      it "toggles public customer sign-up" do
        auth = find_or_create_feature_module!("authentication", name: "User Authentication")

        Authentication::PlatformSettings.instance.update!(allow_customer_signup: true)
        patch admin_maintenance_platform_module_setting_path(platform_customer.id, auth),
              params: { allow_customer_signup: "0" }

        expect(Authentication::PlatformSettings.customer_signup_enabled?).to be(false)
        get configuration_admin_maintenance_platform_module_setting_path(platform_customer.id, auth)
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.authentication.customer_signup"))
      end
    end

    describe "PATCH /update — toggle token_attribute" do
      it "creates platform template token when enabled" do
        source_key = "authentication_user.email"
        ::Emails::TemplateToken.where(source_key: source_key).destroy_all

        patch update_path, params: {
          token_model: "Authentication::User",
          token_attribute: "email",
          token_enabled: "1"
        }

        expect(response).to redirect_to(show_path)
        token = ::Emails::TemplateToken.platform.find_by(source_key: source_key)
        expect(token).to be_present
        expect(token.label).to eq("User.email")
      end

      it "creates platform template token via JSON AJAX request" do
        source_key = "authentication_user.email"
        ::Emails::TemplateToken.where(source_key: source_key).destroy_all

        patch update_path, params: {
          token_model: "Authentication::User",
          token_attribute: "email",
          token_enabled: "1"
        }, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["success"]).to be true
        expect(json["enabled"]).to be true
        expect(Emails::TemplateToken.platform.where(source_key: source_key)).to exist
      end

      it "destroys platform template token when disabled" do
        source_key = "authentication_user.email"
        ::Emails::TemplateToken.find_or_create_by!(
          source_type: ::Emails::TemplateToken::SOURCE_PLATFORM,
          source_key: source_key
        ) { |t| t.label = "User.email" }

        patch update_path, params: {
          token_model: "Authentication::User",
          token_attribute: "email",
          token_enabled: "0"
        }

        expect(response).to redirect_to(show_path)
        expect(::Emails::TemplateToken.platform.find_by(source_key: source_key)).to be_nil
      end

      it "does not create a platform token for otp_secret" do
        source_key = "authentication_user.otp_secret"
        ::Emails::TemplateToken.where(source_key: source_key).destroy_all

        patch update_path, params: {
          token_model: "Authentication::User",
          token_attribute: "otp_secret",
          token_enabled: "1"
        }, headers: { "ACCEPT" => "application/json" }

        expect(response).to have_http_status(422)
        expect(Emails::TemplateToken.platform.where(source_key: source_key)).not_to exist
      end

      it "destroys an existing sensitive platform token when disabled" do
        source_key = "authentication_user.otp_secret"
        ::Emails::TemplateToken.find_or_create_by!(
          source_type: ::Emails::TemplateToken::SOURCE_PLATFORM,
          source_key: source_key
        ) { |t| t.label = "User.otp_secret" }

        patch update_path, params: {
          token_model: "Authentication::User",
          token_attribute: "otp_secret",
          token_enabled: "0"
        }

        expect(response).to redirect_to(show_path)
        expect(::Emails::TemplateToken.platform.find_by(source_key: source_key)).to be_nil
      end
    end

    describe "PATCH /update — toggle extendable_model" do
      it "marks a known model as extendable" do
        allow(ModuleModelDiscovery).to receive(:call).with(feature_module.key)
          .and_return([{ name: "Payments::Order" }])

        patch update_path, params: { extendable_model: "Payments::Order", extendable: "1" }

        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.extendable_model?("Payments::Order")).to be(true)
      end

      it "removes a model from extendable set" do
        allow(ModuleModelDiscovery).to receive(:call).with(feature_module.key)
          .and_return([{ name: "Payments::Order" }])
        feature_module.set_extendable_model!("Payments::Order", true)

        patch update_path, params: { extendable_model: "Payments::Order", extendable: "0" }

        expect(feature_module.reload.extendable_model?("Payments::Order")).to be(false)
      end

      it "shows an attribute section for an extendable model and saves the owner's selection" do
        discovered = [{
          name: "Payments::Order", table_name: "payment_orders", columns_count: 2, associations_count: 0,
          columns: [{ name: "amount", label: "Amount" }, { name: "currency", label: "Currency" }]
        }]
        allow(ModuleModelDiscovery).to receive(:call).with(feature_module.key).and_return(discovered)
        feature_module.set_extendable_model!("Payments::Order", true)

        get developer_path
        expect(response).to have_http_status(:ok)
        document = Capybara.string(response.body)
        expect(document).to have_text(I18n.t("maint_platform.module_settings.show.models.extendable_attributes_hint"))
        expect(document).to have_text("amount")
        expect(document.find("#extendable_attribute_payments_order_amount")).not_to be_checked
        expect(document.find("#extendable_attribute_payments_order_currency")).not_to be_checked

        patch update_path, params: {
          section: "developer",
          extendable_model: "Payments::Order",
          extendable_attribute: "amount",
          extendable_attribute_enabled: "1"
        }

        expect(response).to redirect_to(developer_path)
        expect(feature_module.reload.extendable_attributes_for("Payments::Order")).to eq(["amount"])
      end

      it "rejects an unknown class name not discovered by ModuleModelDiscovery" do
        allow(ModuleModelDiscovery).to receive(:call).with(feature_module.key)
          .and_return([{ name: "Payments::Order" }])

        patch update_path, params: { extendable_model: "Evil::Klass", extendable: "1" }

        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.extendable_model?("Evil::Klass")).to be(false)
      end
    end

    describe "PATCH /update — edit config_defaults" do
      before do
        schema = {
          "mfa_enabled" => { "type" => "boolean", "default" => false, "label" => "MFA" },
          "session_timeout" => { "type" => "integer", "default" => 30, "label" => "Timeout" }
        }
        feature_module.update!(configuration_schema: schema.to_json)
      end

      it "updates the default value for a declared schema key" do
        patch update_path, params: { config_defaults: { mfa_enabled: "true", session_timeout: "60" } }

        expect(response).to redirect_to(show_path)
        schema = feature_module.reload.configuration_schema_json
        expect(schema["mfa_enabled"]["default"]).to eq("true")
        expect(schema["session_timeout"]["default"]).to eq("60")
      end

      it "ignores a non-whitelisted key (not in schema)" do
        patch update_path, params: { config_defaults: { injected_key: "malicious" } }

        expect(response).to redirect_to(show_path)
        schema = feature_module.reload.configuration_schema_json
        expect(schema).not_to have_key("injected_key")
      end

      it "does nothing when module has no configuration_schema" do
        feature_module.update!(configuration_schema: nil)

        patch update_path, params: { config_defaults: { anything: "value" } }

        expect(response).to redirect_to(show_path)
        expect(feature_module.reload.configuration_schema_json).to be_empty
      end

      it "rejects config_defaults when it is not an object" do
        original = feature_module.configuration_schema

        patch update_path, params: { config_defaults: "[]" }, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(feature_module.reload.configuration_schema).to eq(original)
      end
    end
  end
end
