# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::SendActivityDeliveries", type: :request do
  include_context "as admin"
  let(:other_customer) { create(:customer) }

  let!(:email_module) { enable_module!("email", customer, name: "Email") }
  let!(:credential) { create(:email_credential, mode: "sandbox") }

  def delivery_path(campaign)
    "/#{customer.id}/admin/modules/emails/send_activities/#{campaign.id}/delivery"
  end

  # ---------------------------------------------------------------------------
  # POST create — happy path transitions draft → sending and enqueues job
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/send_activities/:send_activity_id/delivery" do
    let(:campaign) { create(:email_send_activity, customer: customer) }
    let(:guard_path) { delivery_path(campaign) }

    it_behaves_like "an admin-guarded request", :post

    it "transitions the campaign to 'sending' and redirects to show" do
      expect {
        post delivery_path(campaign)
      }.not_to raise_error
      expect(response).to redirect_to(/emails\/send_activities\/#{campaign.id}/)
      expect(campaign.reload.status).to eq("processing")
    end

    it "starts the campaign, enqueues SendActivityJob, and redirects" do
      expect do
        post delivery_path(campaign)
      end.to have_enqueued_job(Emails::SendActivities::SendActivityJob).with(campaign.id)
      expect(response).to redirect_to(/emails\/send_activities\/#{campaign.id}/)
      expect(campaign.reload.status).to eq("processing")
    end

    it "returns a localized transport rejection instead of a success notice for Aliyun" do
      credential.update!(status: "disabled")
      aliyun = create(:email_credential, provider: "aliyun", mode: "sandbox", username: nil,
                      config: { "access_key_id" => "AKID", "from_email" => "api@example.com" })

      expect { post delivery_path(campaign) }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)

      expect(response).to redirect_to(/emails\/send_activities\/#{campaign.id}/)
      expect(flash[:alert]).to include(I18n.t("email.providers.errors.unsupported_campaign", provider: aliyun.provider_class.display_name))
      expect(flash[:notice]).to be_nil
      expect(campaign.reload.status).to eq("pending")
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      expect {
        post delivery_path(campaign)
      }.not_to have_enqueued_job(Emails::SendActivities::SendActivityJob)
      expect(response).to have_http_status(:not_found)
      expect(campaign.reload.status).to eq("pending")
    end

    # -------------------------------------------------------------------------
    # Multi-tenant isolation
    # -------------------------------------------------------------------------
    it "returns 404 when the campaign belongs to another tenant" do
      other = create(:email_send_activity, customer: other_customer)
      post delivery_path(other)
      expect(response).to have_http_status(:not_found)
    end
  end
end
