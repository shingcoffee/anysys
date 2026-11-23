# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::PageVisibilities", type: :request do
  let_it_be(:customer) { create(:customer) }
  let(:admin)    { create(:user, :admin, customer: customer) }
  let(:page_rec) { create(:page, customer: customer) }

  # Sends the new array-param form shape.
  def patch_visibility(audiences)
    patch "/#{customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility",
          params: { page: { visible_audiences: audiences } }
  end

  let(:guard_path) { "/#{customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility" }

  it_behaves_like "an admin-guarded request", :patch

  context "as admin" do
    before { sign_in admin }

    it "PATCHes ['admin','member','public'] to the exact audience set" do
      patch_visibility(%w[admin member public])
      expect(response).to have_http_status(:redirect)
      page_rec.reload
      expect(page_rec.visible_to?(:admin)).to be(true)
      expect(page_rec.visible_to?(:member)).to be(true)
      expect(page_rec.visible_to?(:public)).to be(true)
      expect(page_rec.visible_audiences).to eq(%w[admin member public])
    end

    it "PATCHes ['admin','member'] without implying public" do
      patch_visibility(%w[admin member])
      expect(response).to have_http_status(:redirect)
      page_rec.reload
      expect(page_rec.visible_to?(:public)).to be(false)
      expect(page_rec.visible_audiences).to eq(%w[admin member])
    end

    it "PATCHes ['admin'] to admin only" do
      page_rec.update!(visible_audiences: %w[admin member public])
      patch_visibility(%w[admin])
      expect(response).to have_http_status(:redirect)
      expect(page_rec.reload.visible_audiences).to eq(%w[admin])
    end

    it "honors a safe return_to path" do
      return_to = "/#{customer.id}/admin/pages/#{page_rec.id}"
      patch "/#{customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility",
            params: { return_to: return_to, page: { visible_audiences: %w[admin member] } }
      expect(response).to redirect_to(return_to)
      expect(page_rec.reload.visible_audiences).to eq(%w[admin member])
    end

    it "ignores a protocol-relative return_to" do
      patch "/#{customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility",
            params: { return_to: "//evil.example/phish", page: { visible_audiences: %w[admin] } }
      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_rec))
    end

    it "ignores a backslash protocol-relative return_to" do
      patch "/#{customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility",
            params: { return_to: "/\\evil.example/phish", page: { visible_audiences: %w[admin] } }
      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_rec))
    end

    it "ignores a cross-tenant return_to path" do
      other = create(:customer)
      patch "/#{customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility",
            params: { return_to: "/#{other.id}/admin/pages/#{page_rec.id}", page: { visible_audiences: %w[admin] } }
      expect(response).to redirect_to(admin_maintenance_page_path(customer.id, page_rec))
    end

    it "stores exact-set membership: a public-only page is not visible to members or admins" do
      patch_visibility(%w[public])
      expect(response).to have_http_status(:redirect)
      page_rec.reload
      expect(page_rec.visible_audiences).to eq(%w[public])
      expect(page_rec.visible_to?(:public)).to be(true)
      expect(page_rec.visible_to?(:member)).to be(false)
      expect(page_rec.visible_to?(:admin)).to be(false)
    end

    it "rejects an empty array and leaves the existing audience set unchanged" do
      page_rec.update!(visible_audiences: %w[admin member public])
      patch_visibility([])
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include(I18n.t("maint_core.errors.validations.page_audiences_blank"))
      expect(page_rec.reload.visible_audiences).to eq(%w[admin member public])
    end

    it "rejects unknown-only values and leaves the existing audience set unchanged" do
      page_rec.update!(visible_audiences: %w[admin member public])
      patch_visibility(%w[everyone superuser])
      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to include(I18n.t("maint_core.errors.validations.page_audiences_blank"))
      expect(page_rec.reload.visible_audiences).to eq(%w[admin member public])
    end
  end

  context "as member (admin route guard)" do
    it "does not mutate visibility" do
      member = create(:user, :member, customer: customer)
      sign_in member
      patch_visibility(%w[admin member public])
      expect(page_rec.reload.visible_audiences).to contain_exactly("admin")
    end
  end

  context "anonymous user" do
    it "redirects to sign-in and does not mutate visibility" do
      patch_visibility(%w[admin member public])
      expect(response).to redirect_to("/auth/sign_in")
      expect(page_rec.reload.visible_audiences).to contain_exactly("admin")
    end
  end

  context "cross-tenant isolation" do
    it "an admin of a different customer cannot update a page belonging to this customer" do
      other_customer = create(:customer)
      other_admin    = create(:user, :admin, customer: other_customer)
      sign_in other_admin

      # Attempt to reach the page owned by `customer` while authenticated as
      # an admin of `other_customer`. The path encodes the other customer's
      # tenant id so it passes the path-prefix guard, but Page.for_current_customer
      # is scoped to the signed-in user's tenant — the page will not be found.
      patch "/#{other_customer.id}/admin/maintenance/pages/#{page_rec.id}/visibility",
            params: { page: { visible_audiences: %w[admin member public] } }

      expect(response).to have_http_status(:not_found).or have_http_status(:redirect)
      # Visibility on the target page must not have changed.
      expect(page_rec.reload.visible_audiences).to eq(%w[admin])
    end
  end
end
