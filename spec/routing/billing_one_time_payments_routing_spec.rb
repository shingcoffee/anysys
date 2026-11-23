# frozen_string_literal: true

require "rails_helper"

RSpec.describe "billing one-time payment routing", type: :routing do
  let(:cid) { "12345678" }

  describe "area (b): invoice one-time payment" do
    it "routes GET show" do
      expect(get: "/#{cid}/admin/settings/billing/invoices/7/one_time_payment").to route_to(
        controller: "admin/settings/billing/one_time_payments",
        action: "show",
        customer_id: cid,
        invoice_id: "7"
      )
    end

    it "routes POST create" do
      expect(post: "/#{cid}/admin/settings/billing/invoices/7/one_time_payment").to route_to(
        controller: "admin/settings/billing/one_time_payments",
        action: "create",
        customer_id: cid,
        invoice_id: "7"
      )
    end

    it "routes GET status" do
      expect(get: "/#{cid}/admin/settings/billing/invoices/7/one_time_payment/status").to route_to(
        controller: "admin/settings/billing/one_time_payments",
        action: "status",
        customer_id: cid,
        invoice_id: "7"
      )
    end

    it "routes POST confirm" do
      expect(post: "/#{cid}/admin/settings/billing/invoices/7/one_time_payment/confirm").to route_to(
        controller: "admin/settings/billing/one_time_payments",
        action: "confirm",
        customer_id: cid,
        invoice_id: "7"
      )
    end

    it "does not route write-only verbs as GET or member/public paths" do
      expect(get: "/#{cid}/admin/settings/billing/invoices/7/one_time_payment/confirm").not_to be_routable
      expect(post: "/#{cid}/admin/settings/billing/invoices/7/one_time_payment/status").not_to be_routable
      expect(post: "/#{cid}/member/billing/invoices/7/one_time_payment").not_to be_routable
    end

    it "exposes the invoice one-time payment named helpers" do
      expect(admin_settings_billing_invoice_one_time_payment_path(cid, 7)).to eq(
        "/#{cid}/admin/settings/billing/invoices/7/one_time_payment"
      )
      expect(status_admin_settings_billing_invoice_one_time_payment_path(cid, 7)).to eq(
        "/#{cid}/admin/settings/billing/invoices/7/one_time_payment/status"
      )
      expect(confirm_admin_settings_billing_invoice_one_time_payment_path(cid, 7)).to eq(
        "/#{cid}/admin/settings/billing/invoices/7/one_time_payment/confirm"
      )
    end
  end

  describe "area (b): subscription one-time payment" do
    it "routes POST create" do
      expect(post: "/#{cid}/admin/settings/billing/subscription/one_time_payment").to route_to(
        controller: "admin/settings/billing/subscription_one_time_payments",
        action: "create",
        customer_id: cid
      )
    end

    it "does not route GET or member writes" do
      expect(get: "/#{cid}/admin/settings/billing/subscription/one_time_payment").not_to be_routable
      expect(post: "/#{cid}/member/billing/subscription/one_time_payment").not_to be_routable
    end

    it "exposes the subscription one-time payment named helper" do
      expect(admin_settings_billing_subscription_one_time_payment_path(cid)).to eq(
        "/#{cid}/admin/settings/billing/subscription/one_time_payment"
      )
    end
  end
end
