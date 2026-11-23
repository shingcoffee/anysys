# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Admin::SubscriptionsTableComponent, type: :component do
  let(:plan) { instance_double(Billing::Plan, name: "Pro Monthly", code: "pro-monthly") }
  let(:active_sub)    { build_sub(id: 1, status: "active") }
  let(:trialing_sub)  { build_sub(id: 2, status: "trialing", customer_id: "99999999") }
  let(:cancelled_sub) { build_sub(id: 3, status: "cancelled") }
  let(:component)     { described_class.new(subscriptions: [], customer_id: "81721200") }

  def build_sub(id:, status:, customer_id: "12345678", customer: nil)
    instance_double(
      Billing::Subscription,
      id:                  id,
      plan:                plan,
      status:              status,
      amount_cents:        9900,
      currency:            "CNY",
      interval:            "monthly",
      customer_id:         customer_id,
      customer:            customer,
      cancel_at_period_end?: false,
      current_period_end:  Time.zone.local(2026, 7, 1)
    )
  end

  before do
    stub_helpers = double(
      "helpers",
      admin_maintenance_platform_billing_subscription_path:             "/81721200/admin/maintenance/platform/billing/subscriptions/1",
      admin_maintenance_platform_billing_subscriptions_path:            "/81721200/admin/maintenance/platform/billing/subscriptions",
      admin_maintenance_platform_billing_subscription_cancellation_path: "/81721200/admin/maintenance/platform/billing/subscriptions/1/cancellation",
      protect_against_forgery?: false
    )
    allow_any_instance_of(described_class).to receive(:helpers).and_return(stub_helpers)
  end

  describe "empty state" do
    it "shows empty state when no subscriptions" do
      render_inline(described_class.new(subscriptions: [], customer_id: "81721200", platform: true))
      expect(page).to have_text("No subscriptions found.")
    end
  end

  describe "platform mode" do
    before do
      render_inline(described_class.new(
        subscriptions: [active_sub, trialing_sub, cancelled_sub],
        customer_id:   "81721200",
        platform:      true
      ))
    end

    it "renders plan names" do
      expect(page).to have_text("Pro Monthly", count: 6)
    end

    it "renders status badges" do
      expect(page).to have_text("Active")
      expect(page).to have_text("Trialing")
      expect(page).to have_text("Cancelled")
    end

    it "renders formatted amounts" do
      expect(page).to have_text("¥99.00", count: 6)
    end

    it "renders View links for all rows" do
      expect(page).to have_link("View", count: 6)
    end

    it "keeps immediate cancellation beside consequences on detail" do
      expect(page).not_to have_button("Cancel")
    end

    it "renders Customer column header" do
      expect(page).to have_css("th", text: "Customer")
    end

    it "shows customer IDs in rows" do
      expect(page).to have_text("12345678")
      expect(page).to have_text("99999999")
    end

    it "merges interval into the plan cell and keeps both layouts" do
      expect(page).to have_css("ul.lg\\:hidden li", text: "Monthly")
      expect(page).to have_css("table th[scope='row']", text: "Monthly")
      expect(page).not_to have_css("th", text: "Interval")
    end
  end

  describe "empty filtered state" do
    it "offers a filter reset from a filtered empty state" do
      render_inline(described_class.new(subscriptions: [], customer_id: "81721200", platform: true, filters: { status: "void" }))
      expect(page).to have_text("No billing records match these filters.")
      expect(page).to have_link("Reset", href: "/81721200/admin/maintenance/platform/billing/subscriptions")
    end
  end

  describe "customer name from the loaded association" do
    it "shows the customer name beneath the id when the association is present" do
      named = build_sub(id: 4, status: "active", customer: instance_double(Customer, name: "Acme Tenant"))
      render_inline(described_class.new(subscriptions: [named], customer_id: "81721200", platform: true))
      expect(page).to have_text("12345678")
      expect(page).to have_text("Acme Tenant")
    end
  end

  describe "status_variant" do
    {
      "trialing"  => :info,
      "active"    => :success,
      "past_due"  => :danger,
      "paused"    => :warning,
      "cancelled" => :default,
      "expired"   => :default
    }.each do |status, expected|
      it "returns #{expected} for #{status}" do
        expect(component.status_variant(status)).to eq(expected)
      end
    end
  end

  describe "format_amount" do
    it "formats CNY cents correctly" do
      expect(component.format_amount(9900, "CNY")).to eq("¥99.00 CNY")
    end
  end
end
