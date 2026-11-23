# frozen_string_literal: true

require "rails_helper"

RSpec.describe "billing payment method + standard plans routing", type: :routing do
  let(:cid)          { "12345678" }
  let(:platform_cid) { "81721200" }

  # ---------------------------------------------------------------------------
  # Area (b) — /:cid/admin/settings/billing/payment_methods (new consolidated routes)
  # ---------------------------------------------------------------------------
  describe "area (b): customer payment methods" do
    it "routes Stripe setup and scoped authorization/confirmation with write-only verbs" do
      expect(post: "/#{cid}/admin/settings/billing/payment_methods/setup_intent").to route_to(
        controller: "admin/settings/billing/payment_methods", action: "setup_intent", customer_id: cid
      )
      expect(get: "/#{cid}/admin/settings/billing/payment_methods/42/authorization").to route_to(
        controller: "admin/settings/billing/payment_methods", action: "authorization", customer_id: cid, id: "42"
      )
      expect(post: "/#{cid}/admin/settings/billing/payment_methods/42/confirmation").to route_to(
        controller: "admin/settings/billing/payment_methods", action: "confirmation", customer_id: cid, id: "42"
      )
      expect(get: "/#{cid}/admin/settings/billing/payment_methods/setup_intent").not_to be_routable
      expect(get: "/#{cid}/admin/settings/billing/payment_methods/42/confirmation").not_to be_routable
    end

    it "routes GET index" do
      expect(get: "/#{cid}/admin/settings/billing/payment_methods").to route_to(
        controller:  "admin/settings/billing/payment_methods",
        action:      "index",
        customer_id: cid
      )
    end

    it "routes POST create" do
      expect(post: "/#{cid}/admin/settings/billing/payment_methods").to route_to(
        controller:  "admin/settings/billing/payment_methods",
        action:      "create",
        customer_id: cid
      )
    end

    it "routes DELETE destroy" do
      expect(delete: "/#{cid}/admin/settings/billing/payment_methods/42").to route_to(
        controller:  "admin/settings/billing/payment_methods",
        action:      "destroy",
        customer_id: cid,
        id:          "42"
      )
    end

    it "routes PATCH make_default member action" do
      expect(patch: "/#{cid}/admin/settings/billing/payment_methods/42/make_default").to route_to(
        controller:  "admin/settings/billing/payment_methods",
        action:      "make_default",
        customer_id: cid,
        id:          "42"
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Area (b) — /:cid/admin/settings/billing/subscription (consolidated)
  # ---------------------------------------------------------------------------
  describe "area (b): customer subscription" do
    it "routes GET /admin/settings/billing to subscriptions#show" do
      expect(get: "/#{cid}/admin/settings/billing").to route_to(
        controller:  "admin/settings/billing/subscriptions",
        action:      "show",
        customer_id: cid
      )
    end

    it "routes GET /admin/settings/billing for the platform owner customer" do
      expect(get: "/#{platform_cid}/admin/settings/billing").to route_to(
        controller:  "admin/settings/billing/subscriptions",
        action:      "show",
        customer_id: platform_cid
      )
    end

    it "does not route POST at the billing settings root" do
      expect(post: "/#{cid}/admin/settings/billing").not_to be_routable
    end

    it "routes the read-only preview and pending-change cancellation" do
      expect(get: "/#{cid}/admin/settings/billing/subscription/plan_change_preview").to route_to(
        controller: "admin/settings/billing/subscriptions", action: "plan_change_preview", customer_id: cid
      )
      expect(delete: "/#{cid}/admin/settings/billing/subscription/plan_change").to route_to(
        controller: "admin/settings/billing/plan_changes", action: "destroy", customer_id: cid
      )
      expect(post: "/#{cid}/admin/settings/billing/subscription/plan_change_preview").not_to be_routable
      expect(get: "/#{cid}/admin/settings/billing/subscription/plan_change").not_to be_routable
    end

    it "routes cancellation, resume, and coupon actions under customer billing settings" do
      expect(post: "/#{cid}/admin/settings/billing/cancellation").to route_to(
        controller: "admin/settings/billing/cancellations", action: "create", customer_id: cid
      )
      expect(delete: "/#{cid}/admin/settings/billing/cancellation").to route_to(
        controller: "admin/settings/billing/cancellations", action: "destroy", customer_id: cid
      )
      expect(post: "/#{cid}/admin/settings/billing/coupon_redemption").to route_to(
        controller: "admin/settings/billing/coupon_redemptions", action: "create", customer_id: cid
      )
    end

    it "routes GET show" do
      expect(get: "/#{cid}/admin/settings/billing/subscription").to route_to(
        controller:  "admin/settings/billing/subscriptions",
        action:      "show",
        customer_id: cid
      )
    end

    it "routes PATCH update" do
      expect(patch: "/#{cid}/admin/settings/billing/subscription").to route_to(
        controller:  "admin/settings/billing/subscriptions",
        action:      "update",
        customer_id: cid
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Area (b) — /:cid/admin/settings/billing/invoices (consolidated)
  # ---------------------------------------------------------------------------
  describe "area (b): customer invoices" do
    it "routes invoice recovery without adding a public or member write" do
      expect(post: "/#{cid}/admin/settings/billing/invoices/7/payment").to route_to(
        controller: "admin/settings/billing/invoice_payments", action: "create", customer_id: cid, invoice_id: "7"
      )
      expect(get: "/#{cid}/admin/settings/billing/invoices/7/payment").not_to be_routable
      expect(post: "/#{cid}/member/billing/invoices/7/payment").not_to be_routable
    end

    it "routes GET index" do
      expect(get: "/#{cid}/admin/settings/billing/invoices").to route_to(
        controller:  "admin/settings/billing/invoices",
        action:      "index",
        customer_id: cid
      )
    end

    it "routes GET show" do
      expect(get: "/#{cid}/admin/settings/billing/invoices/7").to route_to(
        controller:  "admin/settings/billing/invoices",
        action:      "show",
        customer_id: cid,
        id:          "7"
      )
    end

    it "routes GET download" do
      expect(get: "/#{cid}/admin/settings/billing/invoices/7/download").to route_to(
        controller:  "admin/settings/billing/invoices",
        action:      "download",
        customer_id: cid,
        id:          "7"
      )
    end
  end
end
