# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::AiAssistant::Settings", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@stt.test", password: "password123") }

  def settings_path(cid = platform_customer.id)
    "/#{cid}/admin/maintenance/platform/module_settings/ai_assistant/settings"
  end

  def edit_path(cid = platform_customer.id)
    "#{settings_path(cid)}/edit"
  end

  def test_connection_path(cid = platform_customer.id)
    "#{settings_path(cid)}/test_connection"
  end

  def stub_update(success: true, errors: [])
    result = instance_double(
      "AiAssistant::Activities::UpdateProviderSettings::Result",
      success?: success, errors: errors
    )
    allow(AiAssistant::Activities::UpdateProviderSettings).to receive(:call)
      .and_return(result)
    result
  end

  let(:guard_path) { settings_path }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET edit auth" do
    let(:guard_path) { edit_path }

    it_behaves_like "a platform-owner-guarded GET"
  end

  it_behaves_like "a platform-owner-guarded request", :patch

  describe "POST test_connection auth" do
    let(:guard_path) { test_connection_path }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "regular admin (non-owner)" do
    before { sign_in admin_user }

    it "is denied on show (own tenant path)" do
      get settings_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on update (own tenant path)" do
      patch settings_path(other_customer.id),
            params: { ai_assistant_provider_settings: { transcribe_active: "1" } }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # -------------------------------------------------------------------
  # Platform owner — allowed
  # -------------------------------------------------------------------
  context "as platform owner" do
    before do
      FeatureModules::AiAssistant::Registration.register!
      sign_in platform_owner
    end

    it "renders show including the Cursor provider tab" do
      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("ai_assistant.providers.openai_whisper.name"))
      expect(response.body).to include(I18n.t("ai_assistant.providers.aws_transcribe.name"))
      expect(response.body).to include(I18n.t("ai_assistant.providers.aliyun.name"))
      expect(response.body).to include(I18n.t("ai_assistant.providers.cursor.name"))
      expect(response.body).to include(I18n.t("ai_assistant.providers.aws_bedrock.name"))
      expect(response.body).to include(I18n.t("ai_assistant.providers.deepseek.name"))
      expect(response.body).to include(I18n.t("ai_assistant.providers.qwen.name"))
    end

    it "renders jobs edit without credential inputs" do
      get edit_path
      expect(response).to have_http_status(:ok)

      get "#{edit_path}?section=jobs"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("transcribe_assignee")
      expect(response.body).not_to include('name="ai_assistant_provider_settings[api_key]"')
    end

    it "renders vendor edit without job assignee selects" do
      get "#{edit_path}?section=vendor"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="ai_assistant_provider_settings[api_key]"')
      expect(response.body).not_to include("transcribe_assignee")
    end

    it "updates and redirects with the updated flash" do
      stub_update

      patch settings_path, params: {
        ai_assistant_provider_settings: { transcribe_active: "1", model: "whisper-1" }
      }

      expect(response).to have_http_status(:redirect)
      expect(response.location).to include("/module_settings/ai_assistant/settings")
      expect(flash[:notice]).to eq(I18n.t("ai_assistant.platform_settings.flash.updated"))
    end

    it "does not 500 when assigning generation to Cursor" do
      stub_update

      patch settings_path, params: {
        provider: "cursor",
        ai_assistant_provider_settings: { generation_active: "1" }
      }

      expect(response).not_to have_http_status(:internal_server_error)
      expect(response).to have_http_status(:redirect)
    end

    it "assigns Cursor generation from assignee params without clearing another vendor's transcribe" do
      aliyun = create(:ai_assistant_provider_settings,
                      provider: "aliyun",
                      api_key: "AKS",
                      transcribe_active: true,
                      generation_active: false,
                      config: { access_key_id: "AKID", app_key: "app-1" }.to_json)

      patch settings_path, params: {
        provider: "cursor",
        ai_assistant_provider_settings: {
          api_key: "cur-test",
          transcribe_assignee: "aliyun",
          generation_assignee: "cursor"
        }
      }

      expect(response).to have_http_status(:redirect)
      expect(aliyun.reload).to have_attributes(transcribe_active: true, generation_active: false)
      cursor = AiAssistant::ProviderSettings.find_by!(provider: "cursor")
      expect(cursor).to have_attributes(generation_active: true, transcribe_active: false)
    end

    it "re-renders edit with 422 when the activity reports errors" do
      stub_update(success: false, errors: ["API key can't be blank."])

      patch settings_path, params: {
        ai_assistant_provider_settings: { transcribe_active: "1" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    describe "POST test_connection (live probe)" do
      let!(:cursor) do
        create(:ai_assistant_provider_settings, provider: "cursor", api_key: "cur-test",
               transcribe_active: false, generation_active: true)
      end

      def cursor_response(status:, body:)
        OutboundHttp::Response.new(status: status, headers: {}, body: body.to_json)
      end

      it "probes the vendor inline without enqueuing a job and flashes OK" do
        allow(OutboundHttp).to receive(:request)
          .and_return(cursor_response(status: 200, body: { items: [ { id: "gpt-5", displayName: "GPT-5" } ] }))

        expect {
          post test_connection_path, params: { provider: "cursor" }
        }.not_to have_enqueued_job(AiAssistant::TestConnectionJob)

        expect(response).to redirect_to("#{settings_path}?provider=cursor")
        expect(flash[:notice]).to eq(I18n.t("ai_assistant.platform_settings.test.ok"))
        expect(cursor.reload).to have_attributes(last_health_check_status: "ok", last_health_check_message: nil)
        expect(cursor.config_value(:generation_models)).to eq([ { "id" => "gpt-5", "display_name" => "GPT-5" } ])
      end

      it "reports the vendor's own error message when the credentials are rejected" do
        allow(OutboundHttp).to receive(:request)
          .and_return(cursor_response(status: 401, body: { code: "error", message: "Invalid User API Key" }))

        post test_connection_path, params: { provider: "cursor" }

        expect(flash[:alert]).to eq(
          I18n.t("ai_assistant.platform_settings.test.failed_detail",
                 summary: I18n.t("ai_assistant.platform_settings.test.configuration_error"),
                 message: "Invalid User API Key")
        )
        expect(cursor.reload).to have_attributes(
          last_health_check_status: "configuration_error",
          last_health_check_message: "Invalid User API Key"
        )

        follow_redirect!
        expect(response.body).to include("Invalid User API Key")
      end

      it "reports the transport error message when the vendor is unreachable" do
        allow(OutboundHttp).to receive(:request)
          .and_raise(OutboundHttp::TransportError, "Failed to open TCP connection to api.cursor.com:443")

        post test_connection_path, params: { provider: "cursor" }

        expect(flash[:alert]).to eq(
          I18n.t("ai_assistant.platform_settings.test.failed_detail",
                 summary: I18n.t("ai_assistant.platform_settings.test.unreachable"),
                 message: "Failed to open TCP connection to api.cursor.com:443")
        )
      end

      it "reports the HTTP status when the vendor error has no message body" do
        allow(OutboundHttp).to receive(:request)
          .and_return(OutboundHttp::Response.new(status: 502, headers: {}, body: "<html>Bad gateway</html>"))

        post test_connection_path, params: { provider: "cursor" }

        expect(flash[:alert]).to eq(
          I18n.t("ai_assistant.platform_settings.test.failed_detail",
                 summary: I18n.t("ai_assistant.platform_settings.test.unreachable"),
                 message: I18n.t("ai_assistant.platform_settings.test.http_status", status: 502))
        )
      end
    end
  end
end
