# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Modules::Emails::SendActivityCancellations", type: :request do
  include_context "as admin"
  let(:other_customer) { create(:customer) }

  let!(:email_module) { enable_module!("email", customer, name: "Email") }

  def cancellation_path(campaign)
    "/#{customer.id}/admin/modules/emails/send_activities/#{campaign.id}/cancellation"
  end

  # ---------------------------------------------------------------------------
  # POST create — cancel a campaign
  # ---------------------------------------------------------------------------
  describe "POST /:cid/admin/modules/emails/send_activities/:send_activity_id/cancellation" do
    let(:campaign) { create(:email_send_activity, :processing, customer: customer) }
    let(:guard_path) { cancellation_path(campaign) }

    it_behaves_like "an admin-guarded request", :post

    it "transitions a sending campaign to 'cancelled' and redirects to show" do
      post cancellation_path(campaign)
      expect(response).to redirect_to(/emails\/send_activities\/#{campaign.id}/)
      expect(campaign.reload.status).to eq("cancelled")
    end

    it "transitions a scheduled campaign to 'cancelled' and redirects" do
      campaign = create(:email_send_activity, :pending, customer: customer)
      post cancellation_path(campaign)
      expect(response).to redirect_to(/emails\/send_activities\/#{campaign.id}/)
      expect(campaign.reload.status).to eq("cancelled")
    end

    it "returns 404 when the Email module is disabled" do
      FeatureModules::CustomerAssignment.find_by!(
        customer: customer, feature_module: email_module
      ).update!(status: :suspended)

      post cancellation_path(campaign)
      expect(response).to have_http_status(:not_found)
      expect(campaign.reload.status).to eq("processing")
    end

    it "alerts when the campaign is already terminal" do
      campaign = create(:email_send_activity, :succeed, customer: customer)
      post cancellation_path(campaign)
      expect(campaign.reload.status).to eq("succeed")
      expect(flash[:alert]).to eq(
        I18n.t("admin_modules.flash.send_activities.not_cancellable",
               status: I18n.t("admin_modules.emails.send_activities.statuses.succeed"))
      )
    end

    # -------------------------------------------------------------------------
    # Multi-tenant isolation
    # -------------------------------------------------------------------------
    it "returns 404 when the campaign belongs to another tenant" do
      other = create(:email_send_activity, :processing, customer: other_customer)
      post cancellation_path(other)
      expect(response).to have_http_status(:not_found)
      expect(other.reload.status).to eq("processing")
    end
  end
end
