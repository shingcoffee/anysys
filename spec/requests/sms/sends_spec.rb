# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sms::Sends", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer, password: "password123") }
  let(:guard_path) { "/#{customer.id}/admin/modules/sms/sends" }

  it_behaves_like "an admin-guarded request", :post
  let!(:credential) { create(:sms_credential, mode: Rails.env.production? ? "production" : "sandbox") }
  let!(:template)   { create(:sms_template, key: "verify_code", variables: %w[code]) }

  let!(:sms_module) { enable_module!("sms", customer, name: "SMS") }

  before do
    sign_in admin
  end

  def send_sms(vars: { code: "1234" }, to: "+8613800138000", template_key: "verify_code", **extra)
    post guard_path,
         params: { to: to, template_key: template_key, vars: vars }.merge(extra), as: :json
  end

  def disable_sms!
    FeatureModules::CustomerAssignment.find_by!(customer: customer, feature_module: sms_module).update!(status: :suspended)
  end

  it "returns 202 with the durable queued ledger ID, expiry and no provider call" do
    expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)
    expect { send_sms }.to change(Sms::Message, :count).by(1)

    expect(response).to have_http_status(:accepted)
    body = response.parsed_body
    message = Sms::Message.find(body.fetch("message_id"))
    expect(message).to have_attributes(customer_id: customer.id, status: "queued", template_key: "verify_code")
    expect(body).to include("status" => "queued", "vendor_message_id" => nil, "failure_code" => nil, "failure_message" => nil)
    expect(Time.iso8601(body.fetch("expires_at"))).to be_within(1.second).of(message.expires_at)
  end

  it "returns 422 when vars don't match the template" do
    send_sms(vars: { wrong: "x" })

    expect(response).to have_http_status(:unprocessable_content)
    body = response.parsed_body
    expect(body["error"]).to eq("invalid_request")
  end

  it "sends a template with no variables when vars is omitted" do
    create(:sms_template, key: "plain_notice", variables: [], status: "active")

    post "/#{customer.id}/admin/modules/sms/sends",
         params: { to: "+8613800138000", template_key: "plain_notice" }, as: :json

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body["status"]).to eq("queued")
  end

  it "returns 422 when vars is not an object" do
    post "/#{customer.id}/admin/modules/sms/sends",
         params: { to: "+8613800138000", template_key: "verify_code", vars: "oops" }, as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.parsed_body["error"]).to eq("invalid_request")
  end

  it "normalizes explicitly nil vars to an empty object for a variable-free template" do
    create(:sms_template, key: "plain_notice", variables: [])

    send_sms(vars: nil, template_key: "plain_notice")

    expect(response).to have_http_status(:accepted)
    expect(Sms::Message.find(response.parsed_body.fetch("message_id")).vars).to eq({})
  end

  [nil, "", " ", " " * Sms::SendStandards::MAX_KEY_BYTES].each do |key|
    it "treats idempotency_key=#{key.inspect} as absent after bounded validation" do
      send_sms(idempotency_key: key)

      expect(response).to have_http_status(:accepted)
      expect(Sms::Message.find(response.parsed_body.fetch("message_id")).idempotency_key).to be_nil
    end
  end

  it "returns 404 when the SMS module is disabled for the customer" do
    disable_sms!

    expect { send_sms(vars: { code: "1234" }) }.not_to change(Sms::Message, :count)
    expect(response).to have_http_status(:not_found)
  end

  it "returns 429 when rate-limited" do
    send_sms(vars: { code: "1" })
    send_sms(vars: { code: "1" })

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body["error"]).to eq("rate_limited")
    expect(response.parsed_body["window"]).to eq("minute")
  end

  it "returns a translated credentials-missing message instead of leaking internals" do
    Sms::Credential.delete_all

    send_sms(vars: { code: "1234" })

    expect(response).to have_http_status(:service_unavailable)
    expect(response.parsed_body["error"]).to eq("credentials_missing")
    expect(response.parsed_body["message"]).to eq(I18n.t("admin_modules.sms.errors.credentials_missing"))
    expect(response.parsed_body["message"]).not_to include("sms_credentials")
  end

  describe "idempotency replay and terminal payloads" do
    it "returns the queued row on replay without another reservation" do
      send_sms(idempotency_key: "request-1")
      id = response.parsed_body.fetch("message_id")

      expect { send_sms(idempotency_key: "request-1") }.not_to change(Sms::Message, :count)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["message_id"]).to eq(id)
    end

    %w[sent delivered failed unknown suppressed expired].each do |status|
      it "returns 200 for an existing #{status} ledger row" do
        send_sms(idempotency_key: "request-1")
        message = Sms::Message.find(response.parsed_body.fetch("message_id"))
        message.update!(status: status, vendor_message_id: "BIZ-1",
                        failure_code: "VENDOR_FAILED", failure_message: Sms::Message::FAILURE_DELIVERY)

        expect { send_sms(idempotency_key: "request-1") }.not_to change(Sms::Message, :count)
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to include(
          "message_id" => message.id, "status" => status, "vendor_message_id" => "BIZ-1",
          "failure_code" => "VENDOR_FAILED", "failure_message" => I18n.t(Sms::Message::FAILURE_DELIVERY)
        )
      end
    end

    it "returns a controlled translated conflict for a key reused with different content" do
      send_sms(idempotency_key: "request-1")

      expect { send_sms(vars: { code: "different" }, idempotency_key: "request-1", locale: "zh-CN") }
        .not_to change(Sms::Message, :count)
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body).to eq(
        "error" => "idempotency_conflict",
        "message" => I18n.t("sms_integration.errors.idempotency_conflict", locale: "zh-CN")
      )
    end

    it "allows a genuine replay after module, template and credentials have been disabled" do
      send_sms(idempotency_key: "request-1")
      id = response.parsed_body.fetch("message_id")
      disable_sms!
      template.update!(status: "retired")
      credential.update!(status: "disabled")

      expect { send_sms(idempotency_key: "request-1") }.not_to change(Sms::Message, :count)
      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["message_id"]).to eq(id)
      send_sms(idempotency_key: "new-request")
      expect(response).to have_http_status(:not_found)
    end

    it "records suppression with 200 and does not call the provider" do
      create(:sms_opt_out, phone_e164: "+8613800138000")
      expect_any_instance_of(Sms::Adapters::Aliyun).not_to receive(:send_message)

      send_sms

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("suppressed")
      expect(Sms::Message.find(response.parsed_body["message_id"]).status).to eq("suppressed")
    end
  end

  describe "shape validation before the gateway" do
    {
      to: [nil, "", [], {}, 1234, true],
      template_key: [nil, "", [], {}, 1234, "Verify-Code", "x" * 129],
      idempotency_key: [[], {}, 1234, false, "x" * 129, " " * 129, "bad\nkey", "\n", "\t", "中" * 43],
      vars: ["", "oops", [], ["code"], true, 1234, { code: [] }, { code: {} }, { code: nil }, { code: true },
             { code: "" }, { code: "x" * 1_025 }, { "x" * 129 => "value" }],
      expires_at: [nil, "", "tomorrow", [], {}, "2026-12-01T00:00:00Z"]
    }.each do |field, values|
      values.each do |value|
        it "rejects #{field}=#{value.inspect} before admission" do
          expect(Sms::Gateway).not_to receive(:send)

          expect { send_sms(**{ field => value }) }.not_to change(Sms::Message, :count)

          expect(response.status).to eq(422)
          expect(response.parsed_body["error"]).to eq("invalid_request")
          expect(response.parsed_body["message"]).not_to include("translation missing")
        end
      end
    end

    it "uses the shared SQL-free standards messages in the request locale" do
      expect(Sms::Gateway).not_to receive(:send)
      send_sms(template_key: "Verify-Code", locale: "zh-CN")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["message"]).to eq(I18n.t(
        "sms_integration.errors.invalid_field", locale: "zh-CN", field: "template_key",
        message: I18n.t("sms_standards.validation.template_key", locale: "zh-CN", limit: Sms::SendStandards::MAX_KEY_BYTES)
      ))
    end
  end

  describe "inherited authorization and URL tenant identity" do
    it "does not call the gateway for an anonymous JSON request" do
      sign_out admin
      expect(Sms::Gateway).not_to receive(:send)
      send_sms
      expect(response).to have_http_status(:unauthorized)
    end

    it "forbids members before module admission" do
      sign_in create(:user, :member, customer: customer)
      disable_sms!
      expect(Sms::Gateway).not_to receive(:send)
      send_sms
      expect(response).to have_http_status(:forbidden)
    end

    it "forbids another tenant's administrator" do
      sign_in create(:user, :admin, customer: create(:customer))
      expect(Sms::Gateway).not_to receive(:send)
      send_sms
      expect(response).to have_http_status(:forbidden)
    end

    it "uses the URL customer despite conflicting JSON/query customer IDs and vendor credentials" do
      foreign_customer = create(:customer)
      post "#{guard_path}?customer_id=#{foreign_customer.id}", params: {
        customer_id: foreign_customer.id, to: "+8613800138000", template_key: "verify_code", vars: { code: "1234" },
        provider: "twilio", mode: "production", account_sid: "UNTRUSTED", auth_token: "UNTRUSTED", body: "raw text"
      }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(Sms::Message.find(response.parsed_body.fetch("message_id")))
        .to have_attributes(customer_id: customer.id, provider: "aliyun", template_key: "verify_code")
    end

    it "lets the pinned platform owner send for the URL tenant" do
      sign_in find_or_create_platform_owner
      send_sms

      expect(response).to have_http_status(:accepted)
      expect(Sms::Message.find(response.parsed_body.fetch("message_id")).customer_id).to eq(customer.id)
    end

    it "also returns 404 for new platform-owner attempts when the target tenant disables SMS" do
      sign_in find_or_create_platform_owner
      disable_sms!
      expect { send_sms }.not_to change(Sms::Message, :count)
      expect(response).to have_http_status(:not_found)
    end

    it "does not replay a foreign tenant's key or expose its message ID" do
      send_sms(idempotency_key: "shared-key")
      foreign_id = response.parsed_body.fetch("message_id")
      other_customer = create(:customer)
      enable_module!("sms", other_customer, name: "SMS")
      sign_in create(:user, :admin, customer: other_customer)

      post "/#{other_customer.id}/admin/modules/sms/sends", params: {
        to: "+8613800138000", template_key: "verify_code", vars: { code: "1234" }, idempotency_key: "shared-key"
      }, as: :json

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body["message_id"]).not_to eq(foreign_id)
      expect(Sms::Message.find(response.parsed_body.fetch("message_id")).customer_id).to eq(other_customer.id)
    end
  end
end
