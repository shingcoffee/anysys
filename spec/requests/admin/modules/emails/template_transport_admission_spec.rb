# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email template transport admission", type: :request do
  include_context "as admin"

  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) do
    create(:email_credential, provider: "aliyun", mode: "sandbox", username: "historical-smtp@example.com",
           config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })
  end
  let(:template) { create(:email_template, customer: customer, body_html: '<img src="cid:blob-123">') }
  let(:base_path) { "/#{customer.id}/admin/modules/emails/templates" }

  %i[member collection].each do |mount|
    %i[json html].each do |format|
      it "rejects an unsupported CID test-send at the #{mount} #{format} entrypoint before queue acceptance" do
        path = mount == :member ? "#{base_path}/#{template.id}/test_send" : "#{base_path}/test_send"
        params = { to: "recipient@example.com" }
        if mount == :collection
          params[:email_template] = { editor_type: "code", subject: "Inline", body_html: '<img src="cid:blob-123">' }
        end
        expect {
          post path, params: params, as: format
        }.not_to change(Emails::Message, :count)

        reason = I18n.t("email.providers.errors.unsupported_message", provider: credential.provider_class.display_name)
        if format == :json
          expect(response).to have_http_status(:unprocessable_entity)
          expect(response.parsed_body).to include("success" => false, "code" => "UNSUPPORTED_FEATURE", "error" => reason)
        else
          expect(response).to have_http_status(:redirect)
          expect(flash[:alert]).to eq(reason)
          expect(flash[:notice]).to be_nil
        end
      end
    end
  end

  it "accepts a supported plain transactional test-send with the API From address" do
    post "#{base_path}/test_send", params: {
      to: "recipient@example.com", email_template: { editor_type: "code", subject: "Plain", body_html: "<p>Plain</p>" }
    }, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["success"]).to be(true)
    expect(Emails::Message.last.from).to eq("api@example.com")
  end
end
