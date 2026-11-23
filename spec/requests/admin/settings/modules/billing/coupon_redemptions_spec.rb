# frozen_string_literal: true

require "rails_helper"

RSpec.describe "admin/settings/billing/coupon_redemptions", type: :request do
  include_context "admin records"
  let!(:subscription) { create(:billing_subscription, customer: customer) }
  let!(:coupon) { create(:billing_coupon, code: "SAVE20") }
  let(:guard_path) { admin_settings_billing_coupon_redemption_path(customer.id) }

  it_behaves_like "an admin-guarded request", :post

  describe "tenant coupon orchestration" do
    before { sign_in admin }

    it "delegates coupon attachment even after existing invoice history" do
      create(:billing_invoice, :paid, customer: customer, subscription: subscription)
      expect(Billing::Activities::ApplyCoupon).to receive(:call).with(subscription: subscription, coupon: coupon)
        .and_return(Billing::Result.new(status: :applied))
      post guard_path, params: { coupon_redemption: { coupon_code: coupon.code, amount_off_cents: 100000, currency: "USD" } }
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq(I18n.t("admin_settings.flash.coupon_redemptions.applied", code: coupon.code))
    end

    it "keeps repeated attachment idempotence in A's command" do
      expect(Billing::Activities::ApplyCoupon).to receive(:call).with(subscription: subscription, coupon: coupon)
        .and_return(Billing::Result.new(status: :unchanged))
      post guard_path, params: { coupon_redemption: { coupon_code: coupon.code } }
      expect(response).to have_http_status(:see_other)
    end

    it "returns 422 and retains the submitted code for an unknown coupon" do
      expect(Billing::Activities::ApplyCoupon).not_to receive(:call)
      post guard_path, params: { coupon_redemption: { coupon_code: "UNKNOWN" } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["reason"]).to eq("coupon_not_found")
    end

    it "returns the domain conflict instead of catching exception text or flashing success" do
      allow(Billing::Activities::ApplyCoupon).to receive(:call).and_return(
        Billing::Result.new(status: :conflict, reason: :already_applied)
      )
      post guard_path, params: { coupon_redemption: { coupon_code: coupon.code } }, as: :json
      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["reason"]).to eq("already_applied")
      expect(flash[:notice]).to be_nil
    end

    it "does not accept another tenant's subscription via a submitted ID" do
      other = create(:billing_subscription, customer: create(:customer))
      expect(Billing::Activities::ApplyCoupon).to receive(:call).with(subscription: subscription, coupon: coupon)
        .and_return(Billing::Result.new(status: :applied))
      post guard_path, params: { coupon_redemption: { coupon_code: coupon.code, subscription_id: other.id } }
      expect(response).to have_http_status(:see_other)
    end

    it "denies a foreign tenant URL before attachment" do
      expect(Billing::Activities::ApplyCoupon).not_to receive(:call)
      post admin_settings_billing_coupon_redemption_path(create(:customer).id),
           params: { coupon_redemption: { coupon_code: coupon.code } }, as: :json
      expect(response).to have_http_status(:forbidden)
    end
  end
end
