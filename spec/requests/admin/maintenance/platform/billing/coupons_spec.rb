# frozen_string_literal: true

require "rails_helper"

# Area (d) — /:cid/admin/maintenance/platform/module_settings/billing/coupons
# Tests: owner-only authorization + CRUD happy paths.
RSpec.describe "admin/maintenance/platform/billing/coupons", type: :request do
  let!(:platform_owner) { find_or_create_platform_owner }
  let!(:platform_cid)   { ensure_platform_customer.id }

  let!(:regular_customer) { create(:customer) }
  let!(:regular_admin)    { create(:user, :admin, customer: regular_customer) }

  let!(:coupon) { create(:billing_coupon, code: "TESTCPN", name: "Test Coupon", active: true) }
  let(:guard_path) { admin_maintenance_platform_billing_coupons_path(platform_cid) }

  it_behaves_like "a platform-owner-guarded GET"

  describe "GET show — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET new — auth guards" do
    let(:guard_path) { new_admin_maintenance_platform_billing_coupon_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "GET edit — auth guards" do
    let(:guard_path) { edit_admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id) }

    it_behaves_like "a platform-owner-guarded GET"
  end

  describe "POST create — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_coupons_path(platform_cid) }

    it_behaves_like "a platform-owner-guarded request", :post
  end

  describe "PATCH update — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id) }

    it_behaves_like "a platform-owner-guarded request", :patch
  end

  describe "DELETE destroy — auth guards" do
    let(:guard_path) { admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id) }

    it_behaves_like "a platform-owner-guarded request", :delete
  end

  describe "regular admin access" do
    before { sign_in regular_admin }

    it "is blocked on index" do
      get admin_maintenance_platform_billing_coupons_path(regular_customer.id)
      expect(response).not_to have_http_status(:ok)
    end
  end

  # -------------------------------------------------------------------------
  # Happy paths — platform owner
  # -------------------------------------------------------------------------
  describe "platform owner" do
    before { sign_in platform_owner }

    describe "GET index" do
      it "returns 200 and lists coupons" do
        get admin_maintenance_platform_billing_coupons_path(platform_cid)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("TESTCPN")
      end
    end

    describe "GET show, new, and edit" do
      it "returns 200 for each form page" do
        [
          admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id),
          new_admin_maintenance_platform_billing_coupon_path(platform_cid),
          edit_admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id)
        ].each do |path|
          get path
          expect(response).to have_http_status(:ok)
        end
      end

      it "formats a fixed USD coupon with the coupon currency, not a hardcoded yen prefix" do
        usd = create(:billing_coupon, :fixed, code: "USD10", currency: "USD", amount_off_cents: 1000)
        get admin_maintenance_platform_billing_coupon_path(platform_cid, usd.id)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(Billing::CurrencyResolver.format(1000, "USD"))
        expect(response.body).not_to include("¥10.00")
      end

      it "localizes discount_type and duration instead of CSS-capitalized English keys" do
        get admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id)
        expect(response.body).to include(I18n.t("comp_billing.coupon_form.discount_types.percent"))
        expect(response.body).to include(I18n.t("comp_billing.coupon_table.durations.once"))
      end

      it "localizes discount_type and duration in zh-CN" do
        get admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id), params: { locale: "zh-CN" }
        expect(response.body).to include(I18n.t("comp_billing.coupon_form.discount_types.percent", locale: :"zh-CN"))
        expect(response.body).to include(I18n.t("comp_billing.coupon_table.durations.once", locale: :"zh-CN"))
      end

      it "localizes redeem_by instead of ISO strftime" do
        expiry = Time.zone.local(2027, 12, 31, 15, 0)
        dated = create(:billing_coupon, code: "EXP2027", redeem_by: expiry)
        get admin_maintenance_platform_billing_coupon_path(platform_cid, dated.id)

        expect(response.body).to include(I18n.l(expiry, format: :long))
        expect(response.body).not_to include(expiry.strftime("%Y-%m-%d %H:%M"))
      end

      it "localizes redeem_by in zh-CN" do
        expiry = Time.zone.local(2027, 12, 31, 15, 0)
        dated = create(:billing_coupon, code: "EXPZH", redeem_by: expiry)
        get admin_maintenance_platform_billing_coupon_path(platform_cid, dated.id), params: { locale: "zh-CN" }

        expect(response.body).to include(I18n.l(expiry, format: :long, locale: :"zh-CN"))
      end
    end

    describe "POST create" do
      it "creates a coupon record and redirects to index" do
        expect {
          post admin_maintenance_platform_billing_coupons_path(platform_cid),
               params: {
                 billing_coupon: {
                   code: "NEWCPN", name: "New Coupon", discount_type: "percent",
                   percent_off: 15, duration: "once", active: true
                 }
               }
        }.to change(Billing::Coupon, :count).by(1)
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include(
          admin_maintenance_platform_billing_coupons_path(platform_cid)
        )
      end
    end

    describe "PATCH update" do
      it "updates coupon record and redirects to index" do
        patch admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id),
              params: { billing_coupon: { name: "Renamed Coupon" } }
        coupon.reload
        expect(coupon.name).to eq("Renamed Coupon")
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include(
          admin_maintenance_platform_billing_coupons_path(platform_cid)
        )
      end
    end

    describe "DELETE destroy" do
      it "archives the coupon without deleting redemption history" do
        expect {
          delete admin_maintenance_platform_billing_coupon_path(platform_cid, coupon.id)
        }.not_to change(Billing::Coupon, :count)
        expect(coupon.reload.archived_at).to be_present
        expect(coupon.active).to be(false)
        expect(response).to have_http_status(:see_other)
        expect(response.location).to include(
          admin_maintenance_platform_billing_coupons_path(platform_cid)
        )
      end
    end

    it "retains the submitted coupon Reform form on validation failure" do
      form = Billing::Contracts::Coupon.new(coupon)
      form.validate(name: "Submitted Coupon", percent_off: "invalid")
      expect(Billing::Catalog::SaveCoupon).to receive(:call).and_return(
        Billing::Result.new(status: :invalid, form: form, errors: form.errors.messages)
      )
      expect_any_instance_of(Admin::Maintenance::Platform::Billing::CouponsController).to receive(:render)
        .with(:edit, status: :unprocessable_entity).and_wrap_original do |original, *args, **kwargs|
          expect(original.receiver.instance_variable_get(:@form)).to equal(form)
          original.call(*args, **kwargs)
        end
      patch admin_maintenance_platform_billing_coupon_path(platform_cid, coupon),
            params: { billing_coupon: { name: "Submitted Coupon", percent_off: "invalid" } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(coupon.reload.name).to eq("Test Coupon")
    end
  end
end
