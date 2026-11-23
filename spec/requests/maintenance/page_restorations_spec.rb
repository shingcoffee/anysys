# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageRestorations", type: :request do
  include_context "as admin"

  let(:other_customer) { create(:customer) }

  def restoration_url(cid, page_id)
    "/#{cid}/admin/maintenance/pages/#{page_id}/restoration"
  end

  describe "PATCH /restoration" do
    let(:deleted_page) do
      p = create(:page, customer: customer)
      p.soft_delete
      p
    end
    let(:guard_path) { restoration_url(customer.id, deleted_page.id) }

    it_behaves_like "an admin-guarded request", :patch

    context "with a valid soft-deleted page" do

      it "returns 200 with status and id via JSON" do
        patch restoration_url(customer.id, deleted_page.id),
              headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["status"]).to eq("success")
        expect(body["id"]).to eq(deleted_page.id)
      end

      it "restores the page via HTML and redirects" do
        patch restoration_url(customer.id, deleted_page.id)

        expect(response).to have_http_status(:redirect)
        deleted_page.reload
        expect(deleted_page.active?).to be(true)
      end
    end

    context "when a live page took the trashed page's action and audience" do
      let!(:trashed) do
        Current.set(customer: customer) do
          create(:page, :launched, :member_only, customer: customer, action_key: "enroll").tap(&:soft_delete)
        end
      end

      before do
        Current.set(customer: customer) do
          create(:page, :launched, :member_only, customer: customer, action_key: "enroll")
        end
      end

      it "refuses the restore with action_audience_taken" do
        patch restoration_url(customer.id, trashed.id)

        expect(flash[:alert]).to include(
          I18n.t("maint_core.errors.page_launch.action_audience_taken",
                 audience: I18n.t("common.visibility.member"), action: "enroll")
        )
        expect(Page.with_deleted.find(trashed.id)).to be_deleted
      end

      it "restores once the slot is free again" do
        Current.set(customer: customer) { Page.find_by!(action_key: "enroll").take_offline! }

        patch restoration_url(customer.id, trashed.id)

        expect(Page.with_deleted.find(trashed.id)).to be_active
      end
    end

    context "when the page belongs to a different customer (tenant isolation)" do
      let(:other_deleted_page) do
        p = create(:page, customer: other_customer)
        p.soft_delete
        p
      end

      it "returns 404 for JSON request" do
        patch restoration_url(customer.id, other_deleted_page.id),
              headers: { "Accept" => "application/json" }

        expect(response).to have_http_status(:not_found)
      end

      it "does not restore the other customer's page" do
        patch restoration_url(customer.id, other_deleted_page.id),
              headers: { "Accept" => "application/json" }

        other_deleted_page.reload
        expect(other_deleted_page.inactive?).to be(true)
      end
    end
  end
end
