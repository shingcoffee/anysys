# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Public page submission via PublicPagesController", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:entity) { create(:entity, customer: customer) }
  let!(:fm)  { create(:feature_module, :handoffable, key: "demo", name: "Demo") }
  let!(:cfm) do
    create(:customer_feature_module,
           customer: customer, feature_module: fm,
           status: :active, configuration: {}.to_json)
  end

  let(:registration) do
    Class.new(FeatureModules::BaseModule) do
      def self.module_key = "demo"
      def self.module_name = "Demo"
      def self.provision!(_c) = nil
      entry_path { |c| "/#{c.id}/demo/start" }
    end
  end

  before do
    allow_any_instance_of(FeatureModules::Module).to receive(:registration_class).and_return(registration)
  end

  def page_url(page)
    "/#{customer.id}/page/#{page.public_uuid}"
  end

  def build_page(extra_form_settings: {})
    Current.set(customer: customer) do
      create(:page, :for_member, :for_public,
             customer: customer,
             entity: entity,
             launched: true,
             configuration: {
               form_settings: extra_form_settings,
               metadata: {
                 entity_id: entity.id,
                 entity_name: entity.name
               },
               fields: []
             }.to_json)
    end
  end

  def with_module_handoff(page, input:)
    bind_page_flowchart(page, steps: [{
      "action" => "hand_off_to_module",
      "config" => { "moduleKey" => "demo", "input" => input }
    }])
    page
  end

  describe "when the bound flowchart hands off to a module" do
    let!(:page) { with_module_handoff(build_page, input: [{ "key" => "amount", "value" => "100" }]) }

    it "redirects to the framework handoff hop and stashes the invocation in the session" do
      post page_url(page)
      expect(response).to redirect_to("/#{customer.id}/handoff")
      expect(session[:feature_module_invocation][:module_key]).to eq("demo")
      expect(session[:feature_module_invocation][:input][:amount]).to eq(100)
    end

    it "redirects back to the page with an alert when the module is disabled" do
      cfm.update!(status: :suspended)

      post page_url(page)
      expect(response).to redirect_to(page_url(page))
      expect(flash[:alert]).to eq(
        I18n.t("public_views.flash.response_save_error",
               errors: I18n.t("flowchart_runtime.errors.hand_off_to_module.module_unavailable"))
      )
      alert = flash[:alert]
      follow_redirect!
      expect(response.body).to include(ERB::Util.html_escape(alert))
    end

    it "does not keep the submitted entry when handoff fails" do
      cfm.update!(status: :suspended)

      expect { post page_url(page) }.not_to change(EntityEntry, :count)
    end

    it "rolls back an update without destroying the existing entry when handoff fails" do
      entity.update!(property_schema_json: [{ "name_slug" => "name", "type" => "String" }])
      existing = create(:entity_entry, customer: customer, entity: entity, data: { "name" => "Original" }.to_json)
      page.update_columns(audience_admin: true)
      sign_in create(:user, :admin, customer: customer)
      cfm.update!(status: :suspended)

      expect { post "#{page_url(page)}?entry_id=#{existing.id}", params: { entity: { name: "Changed" } } }
        .not_to change(EntityEntry, :count)
      expect(JSON.parse(existing.reload.data)).to eq("name" => "Original")
      expect(URI(response.location).path).to eq(admin_entity_pages_path(customer.id, entity))
      expect(flash[:alert]).to eq(
        I18n.t("public_views.flash.response_save_error",
               errors: I18n.t("flowchart_runtime.errors.hand_off_to_module.module_unavailable"))
      )
    end
  end

  describe "when handoff maps a field from submitted params" do
    let(:registration) do
      Class.new(FeatureModules::BaseModule) do
        def self.module_key = "demo"
        def self.module_name = "Demo"
        def self.provision!(_c) = nil
        entry_path { |c| "/#{c.id}/demo/start" }
        input_contract do
          property :amount, validates: { presence: true, numericality: { greater_than: 0 } }
        end
      end
    end

    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "amount" }
      ].to_json)
    end

    let!(:page) do
      with_module_handoff(build_page, input: [{ "key" => "amount", "value" => "ctx[:params]['amount']" }])
    end

    it "maps the allowlisted nested field, not a forged top-level amount" do
      post page_url(page), params: { entity: { amount: "99.00" }, amount: "0.01" }

      expect(response).to redirect_to("/#{customer.id}/handoff")
      expect(session[:feature_module_invocation][:input][:amount]).to eq(99.0)
    end
  end

  describe "when handoff is NOT configured" do
    let!(:page) { build_page }

    it "redirects back to the page with a success notice" do
      expect { post page_url(page) }.to change(EntityEntry, :count).by(1)
      expect(response).to redirect_to(page_url(page))
      expect(flash[:notice]).to match(/thank you/i)
      expect(session[:feature_module_invocation]).to be_nil
    end
  end

  describe "submit when the bound flowchart fails" do
    let!(:page) { build_page }

    it "redirects back with an alert when the flowchart raises" do
      bind_page_flowchart(page, body: 'raise "deliberate failure"')

      expect { post page_url(page) }.not_to change(EntityEntry, :count)

      expect(response).to redirect_to(page_url(page))
      expect(flash[:alert]).to eq(
        I18n.t("public_views.flash.response_save_error", errors: I18n.t("common.errors.dynamic.activity_execution_failed"))
      )
      expect(flash[:alert]).not_to include("deliberate failure")
      follow_redirect!
      expect(response.body).not_to include("deliberate failure")
    end
  end

  describe "submit when a required field is blank" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        {
          "name" => "Name",
          "name_slug" => "name",
          "type" => "String",
          "html_type" => "text",
          "validators" => [{ "type" => "presence" }]
        }
      ].to_json)
    end
    let!(:page) { build_page }

    it "redirects with the contract's field message in English" do
      post page_url(page)

      expect(response).to redirect_to(page_url(page))
      expect(flash[:alert]).to include("can't be blank")
      expect(flash[:alert]).to eq(
        I18n.t("public_views.flash.response_save_error", errors: flash[:alert][/:\s*(.*)\z/, 1])
      )
      expect(flash[:alert]).not_to include(I18n.t("common.errors.dynamic.activity_execution_failed"))
    end

    it "redirects with the contract's field message in zh-CN" do
      post page_url(page), params: { locale: "zh-CN" }

      expect(response).to redirect_to("#{page_url(page)}?locale=zh-CN")
      expect(flash[:alert]).to start_with(
        I18n.t("public_views.flash.response_save_error", locale: :"zh-CN", errors: "")
      )
      expect(flash[:alert]).to include(I18n.t("errors.messages.blank", locale: :"zh-CN"))
      expect(flash[:alert]).not_to include(
        I18n.t("common.errors.dynamic.activity_execution_failed", locale: :"zh-CN")
      )
    end
  end

  describe "submit flash HTML escaping" do
    let!(:page) { build_page }

    it "HTML-escapes collected error text in the flash banner" do
      bind_page_flowchart(page, body: %q(ctx[:errors] = ['<script>alert("xss")</script>']; false))

      post page_url(page)
      follow_redirect!

      expect(response.body).to include("&lt;script&gt;alert(&quot;xss&quot;)&lt;/script&gt;")
      expect(response.body).not_to include('<script>alert("xss")</script>')
    end
  end

  describe "GET show" do
    let!(:page) { build_page }

    it "renders 200 for a launched public page" do
      get page_url(page)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "an unknown page uuid" do
    let(:missing_url) { "/#{customer.id}/page/#{SecureRandom.uuid}" }

    it "renders the not-found body for GET" do
      get missing_url

      expect(response).to have_http_status(:not_found)
      expect(response.body).to eq(I18n.t("public_views.public_pages.not_found"))
    end

    it "returns 404 for POST without running a submission" do
      expect { post missing_url }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "a page that only edits records" do
    let!(:page) { build_page(extra_form_settings: { modes: ["update"] }) }

    it "renders GET successfully" do
      get page_url(page)
      expect(response).to have_http_status(:ok)
    end

    it "rejects an anonymous POST with 405 and writes nothing" do
      expect { post page_url(page) }.not_to change(EntityEntry, :count)
      expect(response).to have_http_status(:method_not_allowed)
      expect(response.body).to eq(I18n.t("common.errors.dynamic.page_not_executable"))
    end
  end

  describe "a leftover flowchart_id in the page configuration" do
    let!(:page) { build_page(extra_form_settings: { flowchart_id: 0 }) }

    it "is ignored and the record is saved" do
      expect { post page_url(page) }.to change(EntityEntry, :count).by(1)

      expect(response).to redirect_to(page_url(page))
      expect(flash[:notice]).to eq(I18n.t("public_views.flash.response_submitted"))
    end
  end

  describe "schema-allowlisted fields" do
    let(:entity) do
      create(:entity, customer: customer, property_schema: [
        { "name_slug" => "name" },
        { "name_slug" => "email" }
      ].to_json)
    end
    let!(:page) { build_page }

    it "allows anonymous POST and only persists schema-allowlisted fields" do
      expect {
        post page_url(page), params: {
          name: "Alice",
          email: "a@example.com",
          secret_admin_flag: "1"
        }
      }.to change(EntityEntry, :count).by(1)

      expect(response).to redirect_to(page_url(page))
      raw = EntityEntry.last.data
      data = raw.is_a?(String) ? JSON.parse(raw) : raw
      expect(data).to include("name" => "Alice", "email" => "a@example.com")
      expect(data).not_to have_key("secret_admin_flag")
    end
  end

  describe "unsupported base-model writes" do
    let!(:page) { build_page }
    let(:member) { create(:user, :member, customer: customer) }
    let(:other_member) { create(:user, :member, customer: customer) }

    it "rejects a signed-in member's base write without modifying another member or saving an entry" do
      original_email = other_member.email
      sign_in member
      expect do
        post page_url(page), params: {
          base: { authentication_user: { id: other_member.id, email: "forged@example.com" } },
          current_user_id: other_member.id, current_user_role: "owner"
        }
      end.not_to change(EntityEntry, :count)
      expect(other_member.reload.email).to eq(original_email)
      expect(response).to redirect_to(member_page_path(customer_id: customer.id, id: page.id))
      expect(flash[:alert]).to eq(I18n.t("public_views.flash.response_save_error",
        errors: I18n.t("common.errors.dynamic.activity_execution_failed")))
    end
  end
end
