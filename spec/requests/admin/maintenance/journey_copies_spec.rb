# frozen_string_literal: true

require "rails_helper"

# POST /:cid/admin/maintenance/entities/journeys/:journey_id/copy
# (Admin::Maintenance::JourneyCopiesController)
RSpec.describe "Admin::Maintenance::JourneyCopies", type: :request do
  let(:customer) { create(:customer) }
  let(:admin) { create(:user, customer: customer, role: :admin) }
  let(:platform_owner) { find_or_create_platform_owner }
  let(:journey) { create(:journey, customer: customer) }

  def url(cid = customer.id, record = journey) = "/#{cid}/admin/maintenance/entities/journeys/#{record.id}/copy"
  def edit_path(record) = "/#{customer.id}/admin/maintenance/entities/journeys/#{record.id}/edit"

  let(:guard_path) { url }

  it_behaves_like "a platform-owner-guarded request", :post

  context "as the platform owner" do
    before { sign_in platform_owner }

    it "creates a draft copy and opens it for editing" do
      source = journey
      expect { post url }.to change(Journey, :count).by(1)

      copy = Journey.where.not(id: source.id).order(:id).last
      expect(copy).to be_draft
      expect(copy.customer_id).to eq(customer.id)
      expect(copy.name).to eq(I18n.t("journeys.admin.copy_name", name: source.name))
      expect(copy.key).to eq("#{source.key}_copy")
      expect(response).to redirect_to(edit_path(copy))
      expect(flash[:notice]).to eq(I18n.t("journeys.admin.flash.duplicated"))
    end

    it "names the copy in zh-CN" do
      source = create(:journey, customer: customer, name: "Enrolment", key: "enrolment")

      post url(customer.id, source), params: { locale: "zh-CN" }

      copy = Journey.where.not(id: source.id).order(:id).last
      expect(copy.name).to eq(I18n.t("journeys.admin.copy_name", name: "Enrolment", locale: :"zh-CN"))
      expect(copy.key).to eq("enrolment_copy")
    end

    it "404s for another customer's journey on this customer's URL" do
      foreign = create(:journey)

      expect { post url(customer.id, foreign) }.not_to change(Journey, :count)
      expect(response).to have_http_status(:not_found)
    end
  end

  context "as a tenant admin of the same customer" do
    before { sign_in admin }

    it "is refused with the owner-required message and creates nothing" do
      journey
      expect { post url }.not_to change(Journey, :count)
      expect(response).to have_http_status(:found)
      expect(response.location).not_to include("/admin/maintenance/entities/journeys")
      expect(flash[:alert]).to eq(I18n.t("common.errors.authorization.platform_owner_required"))
    end

    it "gets 403 on a JSON request" do
      journey
      expect { post url, as: :json }.not_to change(Journey, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end

  context "as a member of the same customer" do
    before { sign_in create(:user, :member, customer: customer) }

    it "is refused and creates nothing" do
      journey
      expect { post url }.not_to change(Journey, :count)
      expect(response).to have_http_status(:found)
      expect(response.location).not_to include("/admin/maintenance/entities/journeys")
      expect(flash[:notice]).to be_nil
    end

    it "gets 403 on a JSON request" do
      journey
      expect { post url, as: :json }.not_to change(Journey, :count)
      expect(response).to have_http_status(:forbidden)
    end
  end
end
