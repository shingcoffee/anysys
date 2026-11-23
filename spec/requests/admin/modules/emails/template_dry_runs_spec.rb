require 'rails_helper'

RSpec.describe "Admin::Modules::Emails::TemplateDryRuns", type: :request do
  include_context "as admin"

  let!(:email_module) { enable_module!("email", customer, name: "Email") }

  before do
    allow(Emails::DeliverMessageJob).to receive(:perform_later)
  end

  let!(:credential) { create(:email_credential, mode: "sandbox") }

  describe "POST /:customer_id/admin/modules/emails/templates/preview" do
    let(:guard_path) { preview_admin_modules_emails_templates_path(customer.id) }

    it_behaves_like "an admin-guarded request", :post
    it "renders unpersisted template with mock variables" do
      allow(Emails::VariableContext).to receive(:for).with(user: admin).and_return({ "first_name" => "Dave" })

      post preview_admin_modules_emails_templates_path(customer.id), params: {
        email_template: {
          name: "Unsaved template",
          subject: "Draft Hello #{platform_token('first_name')}",
          editor_type: "code",
          body_html: "<h1>Unsaved content</h1>"
        }
      }, as: :json

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["subject"]).to eq("Draft Hello Dave")
      expect(json["body_html"]).to include("Unsaved content")
    end

    it "does not serve authored HTML as the response document, even for full_page preview" do
      post preview_admin_modules_emails_templates_path(customer.id), params: {
        preview_mode: "full_page",
        email_template: {
          name: "Unsaved template",
          subject: "Draft Hello #{platform_token('first_name')}",
          editor_type: "code",
          body_html: "<h1>Unsaved content</h1><script>alert(1)</script>"
        }
      }

      expect(response).to have_http_status(:success)
      expect(response.media_type).to eq("application/json")
      json = JSON.parse(response.body)
      expect(json["body_html"]).to include("Unsaved content")
      expect(json["body_srcdoc"]).to include("Unsaved content")
    end
  end

  describe "POST /:customer_id/admin/modules/emails/templates/test_send" do
    let(:guard_path) { test_send_admin_modules_emails_templates_path(customer.id) }

    it_behaves_like "an admin-guarded request", :post

    it "sends transactional email for unpersisted template and returns success JSON" do
      expect {
        post test_send_admin_modules_emails_templates_path(customer.id), params: {
          email_template: {
            name: "Unsaved template",
            subject: "Hi",
            editor_type: "code",
            body_html: "<p>Unsaved code</p>"
          },
          to: "tester@example.com"
        }, as: :json
      }.to change { Emails::Message.where(message_type: "transactional").count }.by(1)

      expect(response).to have_http_status(:success)
      json = JSON.parse(response.body)
      expect(json["success"]).to be true
      expect(json["message"]).to include("tester@example.com")
    end
  end
end
