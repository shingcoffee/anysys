# frozen_string_literal: true

require "rails_helper"

# POST|DELETE /:cid/admin/maintenance/entities/journeys/:journey_id/launch
# (Admin::Maintenance::JourneyLaunchesController)
RSpec.describe "Admin::Maintenance::JourneyLaunches", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, customer: customer, role: :admin) }
  let(:platform_owner) { find_or_create_platform_owner }
  let(:journey) { create(:journey, customer: customer) }

  def url(cid = customer.id, record = journey) = "/#{cid}/admin/maintenance/entities/journeys/#{record.id}/launch"
  def edit_path = "/#{customer.id}/admin/maintenance/entities/journeys/#{journey.id}/edit"

  let(:guard_path) { url }

  it_behaves_like "a platform-owner-guarded request", :post

  context "as the platform owner" do
    include_context "student course association"

    before { sign_in platform_owner }

    it "launches a journey whose checks pass" do
      student_journey_page
      course_journey_page

      post url
      expect(response).to redirect_to(edit_path)
      expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.launched"))
      expect(journey.reload).to be_launched
    end

    it "keeps a journey with failing checks a draft and shows the first error" do
      post url
      expect(response).to redirect_to(edit_path)
      expect(flash[:alert]).to eq(Journeys::LaunchChecks.new(journey).errors.first)
      expect(flash[:alert]).to eq(I18n.t("journeys.launch.errors.page_missing", step: "start",
                                                                                audience: I18n.t("journeys.audiences.admin")))
      expect(journey.reload).to be_draft
    end

    it "takes a launched journey offline" do
      journey.update!(status: :launched)

      delete url
      expect(response).to redirect_to(edit_path)
      expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.taken_offline"))
      expect(journey.reload).to be_draft
    end

    it "404s for another customer's journey on this customer's URL" do
      foreign = create(:journey, :launched)

      post url(customer.id, foreign)
      expect(response).to have_http_status(:not_found)
      sign_in platform_owner
      delete url(customer.id, foreign)
      expect(response).to have_http_status(:not_found)
      expect(foreign.reload).to be_launched
    end
  end

  context "as a tenant admin of the same customer" do
    before { sign_in admin }

    it "is refused with the owner-required message and changes nothing" do
      journey.update!(status: :launched)

      delete url
      expect(response).to have_http_status(:found)
      expect(response.location).not_to include("/admin/maintenance/entities/journeys")
      expect(flash[:alert]).to eq(I18n.t("common.errors.authorization.platform_owner_required"))
      expect(journey.reload).to be_launched
    end

    it "gets 403 on a JSON request" do
      post url, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(journey.reload).to be_draft
    end
  end

  context "as a member of the same customer" do
    before { sign_in create(:user, :member, customer: customer) }

    it "is refused and changes nothing" do
      post url
      expect(response).to have_http_status(:found)
      expect(response.location).not_to include("/admin/maintenance/entities/journeys")
      expect(flash[:notice]).to be_nil
      expect(journey.reload).to be_draft
    end

    it "gets 403 on a JSON request" do
      post url, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(journey.reload).to be_draft
    end
  end
end
