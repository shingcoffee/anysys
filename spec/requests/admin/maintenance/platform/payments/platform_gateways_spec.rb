# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Maintenance::Platform::Payments::PlatformGateways", type: :request do
  let!(:platform_customer) { ensure_platform_customer(name: "Platform Owner") }
  let(:platform_owner)     { find_or_create_platform_owner }

  let(:other_customer) { create(:customer, name: "Other Corp") }
  let(:admin_user)     { create(:user, :admin, customer: other_customer, email: "admin@pg.test", password: "password123") }

  # An admin user who belongs to the PLATFORM customer (81721200) but whose
  # role is `admin` (not `owner`). RouteAuthorization requires platform_owner?
  # (owner? && customer_id == 81721200), so this user MUST be denied.
  let(:platform_admin_user) do
    create(:user, :admin, customer: platform_customer, email: "platform-admin@pg.test", password: "password123")
  end

  # Use the first registered gateway key as the test provider so the spec
  # stays valid as new gateways are added.
  let(:provider_key) { Payments::Gateways.keys.first.to_s }

  def index_path(cid = platform_customer.id)
    admin_maintenance_platform_module_settings_payment_gateways_path(cid)
  end

  def toggle_path(provider = provider_key)
    admin_maintenance_platform_module_settings_payment_gateway_path(
      platform_customer.id, provider
    )
  end

  # The platform gateway row for the test provider.
  def gateway
    Payments::PlatformGateway.for_provider(provider_key)
  end

  # MerchantAccount rows for other_customer + the test provider, read across
  # tenants so backfill assertions see rows regardless of Current.customer.
  def merchant_rows
    Payments::MerchantAccount.unscoped_by_tenant.where(
      customer_id: other_customer.id, provider: provider_key
    )
  end

  let(:guard_path) { index_path }

  it_behaves_like "a platform-owner-guarded GET"

  describe "PATCH toggle auth" do
    let(:guard_path) { toggle_path }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "regular admin (non-owner)" do
    before { sign_in admin_user }

    it "is denied on GET index of its own tenant path" do
      get index_path(other_customer.id)
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied on PATCH of its own tenant path" do
      patch admin_maintenance_platform_module_settings_payment_gateway_path(
              other_customer.id, provider_key),
            params: { available: "1" }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end
  end

  # CRITICAL: Same-tenant admin under platform customer 81721200 must NOT be
  # able to toggle tender availability. The platform area is owner-only;
  # admin role under the platform customer does not satisfy platform_owner?.
  context "as same-tenant admin under platform customer (non-owner)" do
    before { sign_in platform_admin_user }

    it "is denied on GET index even on the platform customer's own CID" do
      expect(platform_admin_user.customer_id).to eq(platform_customer.id)
      expect(platform_admin_user.platform_owner?).to be(false)

      get index_path
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "is denied even when posting to the platform customer's own CID" do
      expect(platform_admin_user.customer_id).to eq(platform_customer.id)
      expect(platform_admin_user.platform_owner?).to be(false)

      patch toggle_path, params: { available: "1" }
      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    it "cannot enable a tender by POSTing to its own customer CID" do
      availability_before = gateway.available
      patch toggle_path, params: { available: "1" }
      expect(gateway.available).to eq(availability_before)
    end
  end

  # -------------------------------------------------------------------
  # Happy path (platform owner)
  # -------------------------------------------------------------------
  context "as platform owner" do
    before { sign_in platform_owner }

    describe "GET #index" do
      it "renders gateway availability on the Providers surface" do
        find_or_create_feature_module!("payment", name: "Payments")

        get index_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-module-settings-shell="true"')
        expect(response.body).to include(I18n.t("maint_platform.module_settings.show.payment.title"))
        expect(response.body).to include('data-payment-gateway-list="true"')
        expect(response.body).to match(/data-section-nav-tab="providers"[^>]*aria-current="page"/)
        expect(response.body).not_to include('data-module-settings-pane="overview"')
        expect(response.body).not_to include('data-module-settings-section="availability"')
        expect(response.body).not_to include('data-module-settings-section="next-actions"')
      end
    end

    it "enables a tender platform-wide" do
      gateway.update!(available: false)
      patch toggle_path, params: { available: "1" }
      expect(Payments::PlatformGateway.available?(provider_key)).to be(true)
    end

    it "disables a tender platform-wide" do
      gateway.update!(available: true)
      patch toggle_path, params: { available: "0" }
      expect(Payments::PlatformGateway.available?(provider_key)).to be(false)
    end

    it "returns 404 for an unknown provider" do
      patch toggle_path("unknown_gateway_xyz"), params: { available: "1" }
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to the payment Providers list after toggling" do
      payment_module = FeatureModules::Module.find_by(key: "payment")
      skip "payment module not seeded" unless payment_module

      patch toggle_path, params: { available: "1" }
      expect(response).to redirect_to(index_path)
    end
  end

  # -------------------------------------------------------------------
  # Backfill regression (fix #2): enabling a tender seeds MerchantAccount
  # rows for customers that already have an active Payments assignment.
  # -------------------------------------------------------------------
  context "backfill on tender enable (platform owner)" do
    let(:payment_module) { FeatureModules::Module.find_by(key: "payment") }

    before do
      sign_in platform_owner
      skip "payment module not seeded" unless payment_module

      # Ensure the test provider starts disabled so enabling it is a meaningful
      # state change and the backfill code path is exercised.
      gateway.update!(available: false)

      # Seed a customer with an ACTIVE payment-module assignment. We use
      # ensure_customer_feature_module so we don't collide if the factory
      # auto-creates the row via Customer after_create hooks.
      ensure_customer_feature_module(
        other_customer, payment_module,
        status: :active, enabled_at: Time.current,
        configuration: {}.to_json
      )

      # Remove any pre-existing MerchantAccount rows for that customer + provider
      # so the count assertion is clean.
      merchant_rows.delete_all
    end

    it "creates MerchantAccount rows for active-payment-module customers when a tender is enabled" do
      expect {
        patch toggle_path, params: { available: "1" }
      }.to change { merchant_rows.count }
        .from(0).to(FeatureModules::Payment::Provisioner::MODES.size)
    end

    it "is idempotent — re-enabling does not duplicate MerchantAccount rows" do
      # First enable: creates rows
      patch toggle_path, params: { available: "1" }
      count_after_first = merchant_rows.count

      # Disable then re-enable to trigger backfill a second time
      patch toggle_path, params: { available: "0" }
      patch toggle_path, params: { available: "1" }

      expect(merchant_rows.count).to eq(count_after_first)
    end

    it "does NOT back-fill MerchantAccount rows when a tender is DISABLED" do
      # Start with the tender available so the disable path is meaningful
      gateway.update!(available: true)

      expect {
        patch toggle_path, params: { available: "0" }
      }.not_to change { merchant_rows.count }
    end

    it "disables existing tenant MerchantAccount rows when a tender is turned off" do
      gateway.update!(available: true)
      acc = Payments::MerchantAccount.unscoped_by_tenant.create!(
        customer_id: other_customer.id,
        provider: provider_key,
        mode: "sandbox",
        merchant_id: "live-#{other_customer.id}",
        status: "active"
      )

      patch toggle_path, params: { available: "0" }

      expect(acc.reload.status).to eq("disabled")
    end

    it "does NOT back-fill rows for customers whose payment assignment is suspended" do
      # Mark the assignment suspended
      FeatureModules::CustomerAssignment.find_by(
        customer_id: other_customer.id, feature_module_id: payment_module.id
      ).update!(status: :suspended)

      expect {
        patch toggle_path, params: { available: "1" }
      }.not_to change { merchant_rows.count }
    end
  end
end
