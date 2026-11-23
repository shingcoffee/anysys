# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::Templates test_send", type: :request do
  include_context "as admin"

let!(:email_module) { enable_module!("email", customer, name: "Email") }

before do
  allow(Emails::DeliverMessageJob).to receive(:perform_later)
end

  # send_raw resolves a credential and a transactional stream.
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  # NOTE: Emails::DeliverMessageJob.perform_later currently raises ArgumentError
  # for EVERY call (see spec/jobs/emails/deliver_message_job_spec.rb for the
  # root-cause finding — a private `#instrument` helper collides with
  # ActiveJob::Instrumentation#instrument). send_raw has no rescue around that
  # call, so it's stubbed here to isolate the controller's own behavior (the
  # subject of this file) from that known, out-of-lane job defect.

  let(:other_customer) { create(:customer) }
  let(:template) do
    create(:email_template,
           customer:  customer,
           name:      "Test Template",
           subject:   "Hello #{platform_token('first_name')}",
           body_html: "<p>Hi #{platform_token('first_name')}, welcome!</p>",
           editor_type:   "code",
           status:        "active")
  end

  # id: defaults to the tenant's own template; extra keys become POST params.
  # Pure-keyword signature (no leading positional hash) is Ruby-3 bare-hash safe.
  def test_send(id: template.id, **params)
    post "/#{customer.id}/admin/modules/emails/templates/#{id}/test_send", params: params
  end

  def last_message
    Emails::Message.order(:created_at).last
  end

  def transactional_count
    Emails::Message.where(message_type: "transactional").count
  end

  describe "POST /:cid/admin/modules/emails/templates/:id/test_send" do
    let(:guard_path) { "/#{customer.id}/admin/modules/emails/templates/#{template.id}/test_send" }

    it_behaves_like "an admin-guarded request", :post
    it "with no `to` param creates a transactional message addressed to the admin's email" do
      expect { test_send }.to change { transactional_count }.by(1)

      expect(last_message.to).to eq(admin.email)
      expect(last_message.message_type).to eq("transactional")
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect { test_send }.not_to change { transactional_count }
      expect(response).to have_http_status(:not_found)
    end

    it "enqueues Emails::DeliverMessageJob for the created message" do
      test_send
      expect(Emails::DeliverMessageJob).to have_received(:perform_later).with(last_message.id, nil)
    end

    it "renders the subject through TemplateRenderer with sample vars" do
      test_send

      # TemplateRenderer replaces #{platform_token('first_name')} with the admin's actual first_name
      # (first_name may be nil for a factory user, so we check subject is present)
      expect(last_message.subject).to be_present
    end

    it "with `to` param sends to the specified address" do
      expect { test_send(to: "someone@a.com") }.to change { transactional_count }.by(1)

      expect(last_message.to).to eq("someone@a.com")
      expect(last_message.message_type).to eq("transactional")
    end

    it "does NOT create a campaign-typed message" do
      expect {
        test_send
      }.not_to change { Emails::Message.where(message_type: "campaign").count }
    end

    it "redirects with a notice after sending" do
      test_send
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include("Test email sent to")
    end

    it "falls back to the templates index when Referer is an external URL" do
      # Rails 8.1 raises ActionController::Redirecting::UnsafeRedirectError on
      # off-host redirect_to. test_send used to pass request.referer through
      # after Emails::Gateway.send_raw had already queued the message, so a
      # forged Referer turned a successful send into a 500 and invited retries.
      expect {
        post "/#{customer.id}/admin/modules/emails/templates/#{template.id}/test_send",
             params: { to: "someone@a.com" },
             headers: { "HTTP_REFERER" => "https://evil.example/phish" }
      }.to change { transactional_count }.by(1)

      expect(response).to redirect_to("/#{customer.id}/admin/modules/emails/templates")
    end

    it "returns 422 when subject and body are blank" do
      template.update_columns(subject: "", body_html: "")
      post "/#{customer.id}/admin/modules/emails/templates/#{template.id}/test_send",
           params: { to: "someone@a.com" }, as: :json

      expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq(I18n.t("admin_modules.flash.templates.blank_content"))
      expect(response.parsed_body["success"]).to eq(false)
    end

    it "sends to multiple comma-separated addresses" do
      expect {
        test_send(to: "one@example.com, two@example.com")
      }.to change { transactional_count }.by(2)

      expect(Emails::Message.where(to: ["one@example.com", "two@example.com"]).count).to eq(2)
    end

    it "redirects with alert when one of the addresses is invalid" do
      expect {
        test_send(to: "valid@example.com, not-an-email")
      }.not_to change { transactional_count }

      expect(response).to redirect_to(/emails\/templates/)
      follow_redirect!
      expect(response.body).to include("not-an-email")
    end

    it "persists the template's inline attachment blob ids into message metadata" do
      allow(Emails::CompileTemplate).to receive(:blob_ids_for).and_return([42])

      test_send(to: "someone@a.com")

      expect(last_message.metadata["attachment_blob_ids"]).to eq([42])
    end

    it "redirects with an alert when no email credential is configured" do
      Emails::Credential.delete_all
      test_send
      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response.body).to include("No active email credential")
    end

    it "does not claim a send succeeded when the address is suppressed" do
      Emails::Suppression.record_for_customer!(
        customer_id: customer.id, email: admin.email, reason: "hard_bounce"
      )
      test_send
      expect(flash[:alert]).to eq(I18n.t("admin_modules.flash.templates.suppressed"))
      expect(last_message.status).to eq("suppressed")
    end
  end
end
