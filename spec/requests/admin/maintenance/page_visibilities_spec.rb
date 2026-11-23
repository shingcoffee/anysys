# frozen_string_literal: true

require "rails_helper"

# PATCH /:cid/admin/maintenance/pages/:page_id/visibility
# Permits visible_audiences[] and action_key. Shared-row identity writes stay
# on the platform prefix.
RSpec.describe "Admin::Maintenance::PageVisibilities", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin) { create(:user, :admin, customer: customer) }
  let(:page_rec) { create(:page, customer: customer) }

  def visibility_path(cid = customer.id, page = page_rec)
    "/#{cid}/admin/maintenance/pages/#{page.id}/visibility"
  end

  def patch_visibility(page: page_rec, cid: customer.id, audiences: %w[admin], action_key: nil, **extra)
    body = { page: { visible_audiences: audiences } }
    body[:page][:action_key] = action_key unless action_key.nil?
    extra.each { |key, value| body[key] = value }
    patch visibility_path(cid, page), params: body
  end

  let(:guard_path) { visibility_path }

  it_behaves_like "an admin-guarded request", :patch

  context "as a same-tenant admin" do
    before { sign_in admin }

    it "persists the action key with the audience set" do
      patch_visibility(audiences: %w[admin member], action_key: "enroll")

      expect(response).to have_http_status(:redirect)
      page_rec.reload
      expect(page_rec.visible_audiences).to contain_exactly("admin", "member")
      expect(page_rec.action_key).to eq("enroll")
    end

    it "alerts with page_action_key_invalid for a malformed action key" do
      patch_visibility(audiences: %w[admin], action_key: "Enroll")

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include(I18n.t("maint_core.errors.validations.page_action_key_invalid"))
      expect(page_rec.reload.action_key).to be_nil
    end

    it "alerts with action_audience_taken when the slot is already live" do
      Current.set(customer: customer) do
        create(:page, :launched, :member_only, customer: customer, action_key: "enroll")
        page_rec.update!(launched: true, action_key: "enroll")
      end

      patch_visibility(audiences: %w[admin member], action_key: "enroll")

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include(
        I18n.t("maint_core.errors.page_launch.action_audience_taken",
               audience: I18n.t("common.visibility.member"), action: "enroll")
      )
      expect(page_rec.reload.visible_audiences).to eq(%w[admin])
    end

    it "alerts instead of confirming when the locked save refuses the change" do
      allow_any_instance_of(Pages::VisibilityContract).to receive(:save).and_return(false)

      patch_visibility(audiences: %w[admin member], action_key: "enroll")

      expect(flash[:notice]).to be_nil
      expect(flash[:alert]).to be_present
      expect(page_rec.reload.action_key).to be_nil
    end

    it "refuses a tenant-path update of a shared page (shared_page_readonly)" do
      shared = create(:page, :shared, name: "SharedVisLock")

      patch_visibility(page: shared, audiences: %w[admin member public], action_key: "enroll")

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq(I18n.t("maint_core.flash.shared_resources.platform_path_only"))
      expect(shared.reload.visible_audiences).to eq(%w[admin])
      expect(shared.action_key).to be_nil
    end

    it "returns shared_page_readonly as JSON on a tenant-path shared write" do
      shared = create(:page, :shared, name: "SharedVisJson")

      patch visibility_path(customer.id, shared),
            params: { page: { visible_audiences: %w[admin member], action_key: "enroll" } },
            as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq("error" => "shared_page_readonly")
      expect(shared.reload.action_key).to be_nil
    end
  end

  context "cross-tenant isolation" do
    it "does not let another tenant's admin change this page" do
      other = create(:customer)
      sign_in create(:user, :admin, customer: other)

      patch_visibility(cid: other.id, audiences: %w[admin member public], action_key: "enroll")

      expect(response).not_to have_http_status(:ok)
      expect(page_rec.reload.visible_audiences).to eq(%w[admin])
      expect(page_rec.action_key).to be_nil
    end
  end
end
